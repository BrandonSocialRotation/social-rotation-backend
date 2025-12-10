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
    
    # Safely get page IDs from bucket_image if columns exist
    if facebook_page_id.nil? && bucket_image.class.column_names.include?('facebook_page_id')
      @facebook_page_id = bucket_image.facebook_page_id
    else
      @facebook_page_id = facebook_page_id
    end
    
    if linkedin_organization_urn.nil? && bucket_image.class.column_names.include?('linkedin_organization_urn')
      @linkedin_organization_urn = bucket_image.linkedin_organization_urn
    else
      @linkedin_organization_urn = linkedin_organization_urn
    end
    
    @temp_files = [] # Track temp files for cleanup
  end
  
  # Post to all selected social media platforms
  # @return [Hash] Results from each platform
  def post_to_all
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
  # @return [String] Local file path
  def get_local_image_path
    file_path = @bucket_image.image.file_path
    
    # If it's a URL (http:// or https://), download it to a temp file
    if file_path.start_with?('http://') || file_path.start_with?('https://')
      download_image_to_temp(file_path)
    else
      # Local file path
      Rails.root.join('public', file_path).to_s
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
      response = service.post_photo(@description, image_url, page_id: @facebook_page_id)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Facebook posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to Twitter
  def post_to_twitter(image_path)
    begin
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
      service = SocialMedia::FacebookService.new(@user)
      response = service.post_to_instagram(@description, image_url)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Instagram posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to LinkedIn
  def post_to_linkedin(image_path)
    begin
      service = SocialMedia::LinkedinService.new(@user)
      response = service.post_with_image(@description, image_path, organization_id: @linkedin_organization_urn)
      
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

