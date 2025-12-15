class SocialMediaVideoPosterService
  # Social media platform bit flags (from BucketSchedule model)
  BIT_FACEBOOK = 1
  BIT_TWITTER = 2
  BIT_INSTAGRAM = 4
  BIT_LINKEDIN = 8
  BIT_GMB = 16
  BIT_PINTEREST = 32
  BIT_YOUTUBE = 64
  
  def initialize(user, bucket_video, post_to_flags, description, twitter_description = nil)
    @user = user
    @bucket_video = bucket_video
    @post_to = post_to_flags
    @description = description
    @twitter_description = twitter_description || description
    @temp_files = [] # Track temp files for cleanup
  end
  
  # Post to all selected social media platforms
  # @return [Hash] Results from each platform
  def post_to_all
    results = {}
    
    begin
      # Get video URL (needs to be publicly accessible)
      video_url = get_public_video_url
      video_path = get_local_video_path
      
      # Post to Facebook
      if should_post_to?(BIT_FACEBOOK)
        results[:facebook] = post_to_facebook(video_url)
      end
      
      # Post to Instagram
      if should_post_to?(BIT_INSTAGRAM)
        results[:instagram] = post_to_instagram(video_url)
      end
      
      # Post to YouTube
      if should_post_to?(BIT_YOUTUBE)
        results[:youtube] = post_to_youtube(video_path)
      end
      
      # Note: Twitter, LinkedIn, GMB, Pinterest typically don't support video posts
      # or have different APIs for video
      
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
  
  # Get public URL for the video
  # @return [String] Public URL
  def get_public_video_url
    # For local development
    if Rails.env.development?
      "http://localhost:3000/#{@bucket_video.video.file_path}"
    else
      # For production with Digital Ocean Spaces
      @bucket_video.video.get_source_url
    end
  end
  
  # Get local file path for the video
  # Downloads the video if it's a URL, otherwise returns local path
  # @return [String] Local file path
  def get_local_video_path
    file_path = @bucket_video.video.file_path
    
    # If it's a URL (http:// or https://), download it to a temp file
    if file_path.start_with?('http://') || file_path.start_with?('https://')
      download_video_to_temp(file_path)
    else
      # Local file path
      Rails.root.join('public', file_path).to_s
    end
  end
  
  # Download video from URL to a temporary file
  # @param video_url [String] URL of the video
  # @return [String] Path to temporary file
  def download_video_to_temp(video_url)
    require 'open-uri'
    require 'tempfile'
    
    # Determine file extension from URL
    extension = File.extname(URI.parse(video_url).path)
    extension = '.mp4' if extension.empty?
    
    # Create a temporary file
    temp_file = Tempfile.new(['rss_video', extension])
    temp_file.binmode
    
    begin
      # Download the video
      URI.open(video_url, 'rb') do |remote_file|
        temp_file.write(remote_file.read)
      end
      
      temp_file.rewind
      # Track temp file for cleanup
      @temp_files << temp_file
      temp_file.path
    rescue => e
      temp_file.close
      temp_file.unlink
      Rails.logger.error "Failed to download video from #{video_url}: #{e.message}"
      raise "Failed to download video: #{e.message}"
    end
  end
  
  # Post to Facebook
  def post_to_facebook(video_url)
    begin
      service = SocialMedia::FacebookService.new(@user)
      response = service.post_photo(@description, video_url) # post_photo handles videos too
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Facebook video posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to Instagram
  def post_to_instagram(video_url)
    begin
      service = SocialMedia::FacebookService.new(@user)
      response = service.post_to_instagram(@description, video_url, is_video: true)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "Instagram video posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Post to YouTube
  def post_to_youtube(video_path)
    begin
      service = SocialMedia::YouTubeService.new(@user)
      # Use friendly_name as title, description as description
      title = @bucket_video.friendly_name || @bucket_video.video.friendly_name || 'Video Post'
      response = service.post_video(title, @description, video_path)
      
      { success: true, response: response }
    rescue => e
      Rails.logger.error "YouTube posting error: #{e.message}"
      { success: false, error: e.message }
    end
  end
end


