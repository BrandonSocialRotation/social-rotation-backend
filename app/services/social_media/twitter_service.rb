module SocialMedia
  class TwitterService
    API_BASE_URL = 'https://api.twitter.com/2'
    UPLOAD_URL = 'https://upload.twitter.com/1.1/media/upload.json'
    
    def initialize(user)
      @user = user
    end
    
    # Post a tweet with media
    # @param message [String] Tweet text (max 280 characters)
    # @param image_path [String] Local path to image file or URL
    # @return [Hash] Response from Twitter API
    def post_tweet(message, image_path)
      unless @user.twitter_oauth_token.present? && @user.twitter_oauth_token_secret.present?
        raise "User does not have Twitter connected"
      end
      
      # Truncate message to 280 characters
      message = message[0...280] if message.length > 280
      
      # Handle URLs by downloading to temp file
      temp_file = nil
      actual_path = image_path
      
      if image_path.start_with?('http://') || image_path.start_with?('https://')
        temp_file = download_image_to_temp(image_path)
        actual_path = temp_file.path
      end
      
      begin
        # Step 1: Upload media
        media_id = upload_media(actual_path)
        
        unless media_id
          raise "Failed to upload media to Twitter"
        end
        
        # Step 2: Create tweet with media
        create_tweet(message, media_id)
      ensure
        # Clean up temp file if we created one
        if temp_file
          temp_file.close
          temp_file.unlink
        end
      end
    end
    
    private
    
    # Upload media to Twitter
    # @param image_path [String] Local path to image
    # @return [String] Media ID
    def upload_media(image_path)
      consumer_key = ENV['TWITTER_API_KEY'] || ENV['TWITTER_CONSUMER_KEY']
      consumer_secret = ENV['TWITTER_API_SECRET_KEY'] || ENV['TWITTER_CONSUMER_SECRET']
      
      unless consumer_key && consumer_secret
        raise "Twitter API credentials not configured"
      end
      
      # Create OAuth consumer
      consumer = ::OAuth::Consumer.new(
        consumer_key,
        consumer_secret,
        site: 'https://upload.twitter.com'
      )
      
      # Create access token from stored credentials
      access_token = ::OAuth::AccessToken.new(
        consumer,
        @user.twitter_oauth_token,
        @user.twitter_oauth_token_secret
      )
      
      # Read image file in binary mode
      image_data = File.binread(image_path)
      Rails.logger.info "Twitter upload - file size: #{image_data.length} bytes"
      
      # Upload media using multipart form data
      response = access_token.post(
        '/1.1/media/upload.json',
        {
          media: image_data,
          media_category: 'tweet_image'
        },
        {
          'Content-Type' => 'multipart/form-data'
        }
      )
      
      Rails.logger.info "Twitter upload response - status: #{response.code}, body: #{response.body[0..500]}"
      
      unless response.is_a?(Net::HTTPSuccess)
        error_msg = response.body || "Unknown error"
        Rails.logger.error "Twitter upload failed - status: #{response.code}, error: #{error_msg}"
        raise "Failed to upload media to Twitter: #{response.code} - #{error_msg}"
      end
      
      data = JSON.parse(response.body)
      media_id = data['media_id_string'] || data['media_id']
      
      unless media_id
        Rails.logger.error "Twitter upload response missing media_id: #{data.inspect}"
        raise "Twitter upload succeeded but no media_id returned"
      end
      
      Rails.logger.info "Twitter media uploaded successfully - media_id: #{media_id}"
      media_id
    rescue => e
      Rails.logger.error "Twitter upload exception: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
    
    # Create a tweet with media
    # @param message [String] Tweet text
    # @param media_id [String] Media ID from upload
    # @return [Hash] Response from Twitter API
    def create_tweet(message, media_id)
      consumer_key = ENV['TWITTER_API_KEY'] || ENV['TWITTER_CONSUMER_KEY']
      consumer_secret = ENV['TWITTER_API_SECRET_KEY'] || ENV['TWITTER_CONSUMER_SECRET']
      
      # Create OAuth consumer
      consumer = ::OAuth::Consumer.new(
        consumer_key,
        consumer_secret,
        site: 'https://api.twitter.com'
      )
      
      # Create access token from stored credentials
      access_token = ::OAuth::AccessToken.new(
        consumer,
        @user.twitter_oauth_token,
        @user.twitter_oauth_token_secret
      )
      
      # Build tweet payload for Twitter API v2
      # Media IDs should be an array of strings at the root level
      payload = {
        text: message
      }
      
      # Add media if provided (Twitter API v2 format)
      if media_id
        payload[:media] = {
          media_ids: [media_id.to_s]
        }
      end
      
      Rails.logger.info "Twitter creating tweet with payload: #{payload.inspect}"
      
      # Create tweet using Twitter API v2
      response = access_token.post(
        '/2/tweets',
        payload.to_json,
        {
          'Content-Type' => 'application/json'
        }
      )
      
      Rails.logger.info "Twitter tweet response - status: #{response.code}, body: #{response.body[0..500]}"
      
      unless response.is_a?(Net::HTTPSuccess)
        error_msg = response.body || "Unknown error"
        Rails.logger.error "Twitter tweet creation failed - status: #{response.code}, error: #{error_msg}"
        raise "Failed to create tweet: #{response.code} - #{error_msg}"
      end
      
      data = JSON.parse(response.body)
      Rails.logger.info "Twitter tweet created successfully: #{data.inspect}"
      data
    rescue => e
      Rails.logger.error "Twitter tweet creation exception: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
    
    # Download image from URL to a temporary file
    # @param image_url [String] URL of the image
    # @return [Tempfile] Temporary file object
    def download_image_to_temp(image_url)
      require 'open-uri'
      require 'tempfile'
      
      # Try to detect file extension from URL
      extension = File.extname(URI.parse(image_url).path)
      extension = '.jpg' if extension.empty? || !['.jpg', '.jpeg', '.png', '.gif'].include?(extension.downcase)
      
      # Create a temporary file with appropriate extension
      temp_file = Tempfile.new(['twitter_image', extension])
      temp_file.binmode
      
      begin
        # Download the image
        URI.open(image_url, 'rb') do |remote_file|
          temp_file.write(remote_file.read)
        end
        
        temp_file.rewind
        temp_file
      rescue => e
        temp_file.close
        temp_file.unlink
        Rails.logger.error "Failed to download image from #{image_url}: #{e.message}"
        raise "Failed to download image: #{e.message}"
      end
    end
  end
end
