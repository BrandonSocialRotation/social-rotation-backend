class SocialMediaPosterService
  # Social media platform bit flags (from BucketSchedule model)
  BIT_FACEBOOK = 1
  BIT_TWITTER = 2
  BIT_INSTAGRAM = 4
  BIT_LINKEDIN = 8
  BIT_GMB = 16
  BIT_PINTEREST = 32
  
  def initialize(user, bucket_image, post_to_flags, description, twitter_description = nil, facebook_page_id: nil, linkedin_organization_urn: nil)
    @user = user
    @bucket_image = bucket_image
    @post_to = post_to_flags
    @description = description
    @twitter_description = twitter_description || description
    @facebook_page_id = facebook_page_id
    @linkedin_organization_urn = linkedin_organization_urn
    @temp_files = [] # Track temp files for cleanup
  end
  
  # Post to all selected social media platforms
  # @return [Hash] Results from each platform
  def post_to_all
    # Check if user has active subscription before posting
    account = @user.account
    unless account&.has_active_subscription?
      subscription = account&.subscription
      error_message = if subscription&.canceled?
        'Your subscription has been canceled. Please resubscribe to post content.'
      elsif subscription
        'Your subscription is not active. Please update your payment method to post content.'
      else
        'You need an active subscription to post content. Please subscribe to continue.'
      end
      
      raise StandardError.new(error_message)
    end
    
    results = {}
    
    begin
      # Get image URL (needs to be publicly accessible)
      image_url = get_public_image_url
      image_path = get_local_image_path
    
    # Post to Facebook
    if should_post_to?(BIT_FACEBOOK)
      results[:facebook] = post_to_facebook(image_url)
    end
    
    # Post to Twitter
    if should_post_to?(BIT_TWITTER)
      results[:twitter] = post_to_twitter(image_path)
    end
    
    # Post to Instagram
    if should_post_to?(BIT_INSTAGRAM)
      results[:instagram] = post_to_instagram(image_url)
    end
    
    # Post to LinkedIn
    if should_post_to?(BIT_LINKEDIN)
      results[:linkedin] = post_to_linkedin(image_path)
    end
    
    # Post to Google My Business
    if should_post_to?(BIT_GMB)
      results[:gmb] = post_to_gmb(image_url)
    end
    
    results
    ensure
      # Clean up any temporary files
      @temp_files.each do |temp_file|
        begin
          temp_file.close
          temp_file.unlink
        rescue => e
          Rails.logger.warn "Failed to clean up temp file: #{e.message}"
        end
      end
    end
  end
  
  private
  
  # Check if should post to a specific platform
  # @param bit_flag [Integer] Platform bit flag
  # @return [Boolean]
  def should_post_to?(bit_flag)
    (@post_to & bit_flag) != 0
  end
  
  # Get public URL for the image
  # @return [String] Public URL
  def get_public_image_url
    # For local development
    if Rails.env.development?
      "http://localhost:3000/#{@bucket_image.image.file_path}"
    else
      # For production with Digital Ocean Spaces
      @bucket_image.image.get_source_url
    end
  end
  
  # Get local file path for the image
  # Downloads the image if it's a URL, otherwise returns local path
  # @return [String] Local file path or URL if local file doesn't exist
  def get_local_image_path
    file_path = @bucket_image.image.file_path
    return nil if file_path.nil?
    
    # If it's a URL (http:// or https://), return it (TwitterService will download it)
    if file_path.start_with?('http://') || file_path.start_with?('https://')
      return file_path
    end
    
    # Check if file_path starts with environment prefix (production/, development/, etc.)
    if file_path.start_with?('production/') || file_path.start_with?('development/') || file_path.start_with?('test/')
      # This is a Digital Ocean Spaces path, not a local file
      # Return the public URL instead
      return get_public_image_url
    end
    
    # Try local file path
    local_path = Rails.root.join('public', file_path).to_s
    
    # Check if file actually exists
    if File.exist?(local_path)
      local_path
    else
      # File doesn't exist locally, use public URL instead
      Rails.logger.warn "Local file not found at #{local_path}, using public URL instead"
      get_public_image_url
    end
  end
  
  # Download image from URL to a temporary file
  # @param image_url [String] URL of the image
  # @return [String] Path to temporary file
  def download_image_to_temp(image_url)
    require 'open-uri'
    require 'tempfile'
    
    # Create a temporary file
    temp_file = Tempfile.new(['rss_image', '.jpg'])
    temp_file.binmode
    
    begin
      # Download the image
      URI.open(image_url, 'rb') do |remote_file|
        temp_file.write(remote_file.read)
      end
      
      temp_file.rewind
      # Track temp file for cleanup
      @temp_files << temp_file
      temp_file.path
    rescue => e
      temp_file.close
      temp_file.unlink
      Rails.logger.error "Failed to download image from #{image_url}: #{e.message}"
      raise "Failed to download image: #{e.message}"
    end
  end
  
    # Post to Facebook
    def post_to_facebook(image_url)
      begin
        service = SocialMedia::FacebookService.new(@user)
        # Use page_id from bucket_image or bucket_schedule if available
        page_id = @bucket_image.facebook_page_id || @facebook_page_id
        response = service.post_photo(@description, image_url, page_id: page_id)
        
        { success: true, response: response }
      rescue => e
        Rails.logger.error "Facebook posting error: #{e.message}"
        { success: false, error: e.message }
      end
    end
  
  # Post to Twitter
  def post_to_twitter(image_path)
    begin
      return { success: false, error: 'Image path is required' } if image_path.nil?
      
      service = SocialMedia::TwitterService.new(@user)
      response = service.post_tweet(@twitter_description, image_path)

      { success: true, response: response }
    rescue => e
      Rails.logger.error "Twitter posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to Instagram
  def post_to_instagram(image_url)
    begin
      # Ensure URL is HTTPS (Instagram requires HTTPS)
      instagram_url = image_url
      if instagram_url.start_with?('http://')
        instagram_url = instagram_url.sub('http://', 'https://')
        Rails.logger.warn "Converted HTTP to HTTPS for Instagram: #{instagram_url}"
      end
      
      service = SocialMedia::FacebookService.new(@user)
      # Use page_id from bucket_image or bucket_schedule if available
      # Instagram is linked to a Facebook page, so we need the page that has the Instagram account
      page_id = @bucket_image.facebook_page_id || @facebook_page_id
      response = service.post_to_instagram(@description, instagram_url, page_id: page_id)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Instagram posting error: #{e.message}"
      Rails.logger.error "Image URL was: #{image_url}"
      { success: false, error: e.message }
    end
  end
  
  # Post to LinkedIn
  def post_to_linkedin(image_path)
    begin
      return { success: false, error: 'Image path is required' } if image_path.nil?
      
      service = SocialMedia::LinkedinService.new(@user)
      # Use organization_urn from bucket_image or bucket_schedule if available
      organization_urn = @bucket_image.linkedin_organization_urn || @linkedin_organization_urn
      response = service.post_with_image(@description, image_path, organization_urn: organization_urn)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "LinkedIn posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to Google My Business
  def post_to_gmb(image_url)
    begin
      service = SocialMedia::GoogleService.new(@user)
      response = service.post_to_gmb(@description, image_url)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Google My Business posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
