module SocialMedia
  class FacebookService
    GRAPH_API_VERSION = 'v18.0'
    BASE_URL = "https://graph.facebook.com/#{GRAPH_API_VERSION}"
    
    def initialize(user)
      @user = user
    end
    
    # Post a photo to Facebook page
    # @param message [String] The post message/caption
    # @param image_url [String] Public URL of the image to post
    # @param page_id [String] Optional Facebook page ID to post to (if not provided, uses first page)
    # @return [Hash] Response from Facebook API
    def post_photo(message, image_url, page_id: nil)
      unless @user.fb_user_access_key.present?
        raise "User does not have Facebook connected"
      end
      
      # Get page access token (for specific page if page_id provided)
      page_token = get_page_access_token(page_id: page_id)
      
      unless page_token
        raise "Could not get Facebook page access token"
      end
      
      # Determine if it's a video or photo
      extension = File.extname(image_url).downcase
      
      if ['.gif', '.mp4'].include?(extension)
        post_video(message, image_url, page_token, page_id: page_id)
      else
        post_image(message, image_url, page_token, page_id: page_id)
      end
    end
    
    # Post to Instagram (via Facebook)
    # @param message [String] The post caption
    # @param media_url [String] Public URL of the image or video
    # @param is_video [Boolean] Whether the media is a video
    # @param page_id [String] Optional Facebook page ID that has the Instagram account
    # @return [Hash] Response from Instagram API
    def post_to_instagram(message, media_url, is_video: false, page_id: nil)
      # If page_id is provided, get Instagram account from that specific page
      instagram_id = nil
      page_token = nil
      
      if page_id
        # Get the specific page and its Instagram account
        url = "#{BASE_URL}/#{page_id}"
        params = {
          access_token: @user.fb_user_access_key,
          fields: 'access_token,instagram_business_account{id}'
        }
        response = HTTParty.get(url, query: params)
        if response.success?
          data = JSON.parse(response.body)
          page_token = data['access_token']
          if data['instagram_business_account']
            instagram_id = data['instagram_business_account']['id']
          end
        end
      end
      
      # Fallback to user's stored Instagram account
      instagram_id ||= @user.instagram_business_id
      unless instagram_id.present?
        raise "User does not have Instagram connected"
      end
      
      page_token ||= get_page_access_token(page_id: page_id)
      
      unless page_token
        raise "Could not get Facebook page access token for Instagram. Your Instagram account must be linked to a Facebook Page to post content. Please link your Instagram Business/Creator account to a Facebook Page in your Facebook Page settings."
      end
      
      # Step 1: Create media container
      create_url = "#{BASE_URL}/#{@user.instagram_business_id}/media"
      create_params = {
        caption: message.presence || '',
        access_token: page_token
      }
      
      Rails.logger.info "Instagram post - caption: '#{message}', caption length: #{message.to_s.length}"
      
      if is_video
        create_params[:media_type] = 'REELS' # or 'VIDEO' for regular posts
        create_params[:video_url] = media_url
      else
        create_params[:image_url] = media_url
      end
      
      response = HTTParty.post(create_url, body: create_params)
      data = JSON.parse(response.body)
      
      unless data['id']
        error_message = if data['error']
          error_code = data['error']['code']
          error_msg = data['error']['message']
          
          # Provide helpful error messages for common issues
          if error_msg.include?('business account') || error_msg.include?('not a business account') || error_code == 10
            "Your Instagram account must be a Business or Creator account linked to a Facebook Page. Please: 1) Convert your Instagram account to Business/Creator in Instagram settings, 2) Link it to a Facebook Page in your Facebook Page settings, then reconnect Instagram."
          else
            "#{error_msg} (Code: #{error_code})"
          end
        else
          "Unknown error: #{data.inspect}"
        end
        Rails.logger.error "Instagram media creation failed: #{error_message}, URL: #{media_url}"
        raise "Failed to create Instagram media container: #{error_message}"
      end
      
      creation_id = data['id']
      
      # For videos, wait for processing status
      if is_video
        wait_for_video_processing(creation_id, page_token)
      end
      
      # Step 2: Publish the media
      publish_url = "#{BASE_URL}/#{@user.instagram_business_id}/media_publish"
      publish_params = {
        creation_id: creation_id,
        access_token: page_token
      }
      
      response = HTTParty.post(publish_url, body: publish_params)
      publish_data = JSON.parse(response.body)
      
      if publish_data['error']
        error_code = publish_data['error']['code']
        error_msg = publish_data['error']['message']
        
        # Provide helpful error messages for common issues
        error_message = if error_msg.include?('business account') || error_msg.include?('not a business account') || error_code == 10
          "Your Instagram account must be a Business or Creator account linked to a Facebook Page. Please: 1) Convert your Instagram account to Business/Creator in Instagram settings, 2) Link it to a Facebook Page in your Facebook Page settings, then reconnect Instagram."
        else
          "#{error_msg} (Code: #{error_code})"
        end
        
        Rails.logger.error "Instagram publish failed: #{error_message}"
        raise "Failed to publish Instagram media: #{error_message}"
      end
      
      publish_data
    end
    
    # Fetch user's Facebook pages
    # @return [Array] Array of page hashes with id, name, and access_token
    def fetch_pages
      unless @user.fb_user_access_key.present?
        raise "User does not have Facebook connected"
      end
      
      url = "#{BASE_URL}/me/accounts"
      params = {
        access_token: @user.fb_user_access_key,
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      
      unless response.success?
        error_data = JSON.parse(response.body) rescue {}
        error_msg = error_data.dig('error', 'message') || 'Facebook API error'
        Rails.logger.error "Facebook fetch_pages API error: #{error_msg}"
        raise "Facebook API error: #{error_msg}"
      end
      
      data = JSON.parse(response.body)
      
      if data['data'] && data['data'].any?
        data['data'].map do |page|
          page_info = {
            id: page['id'],
            name: page['name'],
            access_token: page['access_token']
          }
          
          # Include Instagram account if linked to this page
          if page['instagram_business_account']
            instagram_account = page['instagram_business_account']
            page_info[:instagram_account] = {
              id: instagram_account['id'],
              username: instagram_account['username']
            }
          end
          
          page_info
        end
      else
        []
      end
    rescue => e
      Rails.logger.error "Facebook fetch_pages error: #{e.message}"
      # Re-raise if it's an authentication error
      if e.message.include?('does not have Facebook connected') || e.message.include?('Facebook API error')
        raise e
      end
      raise "User does not have Facebook connected" if e.is_a?(RuntimeError)
      []
    end
    
    # Wait for video to finish processing on Instagram
    # @param creation_id [String] Media container ID
    # @param page_token [String] Page access token
    # @param max_wait [Integer] Maximum seconds to wait (default 300)
    def wait_for_video_processing(creation_id, page_token, max_wait = 300)
      status_url = "#{BASE_URL}/#{creation_id}"
      start_time = Time.now
      
      while Time.now - start_time < max_wait
        response = HTTParty.get(status_url, query: {
          fields: 'status_code',
          access_token: page_token
        })
        
        data = JSON.parse(response.body)
        status = data['status_code']
        
        if status == 'FINISHED'
          return true
        elsif status == 'ERROR'
          raise "Instagram video processing failed: #{data['error']}"
        end
        
        # Wait 5 seconds before checking again
        sleep(5)
      end
      
      raise "Instagram video processing timeout after #{max_wait} seconds"
    end
    
    private
    
    # Post an image to Facebook
    def post_image(message, image_url, page_token, page_id: nil)
      # Use page_id if provided, otherwise use /me endpoint
      endpoint = page_id ? "#{BASE_URL}/#{page_id}/photos" : "#{BASE_URL}/me/photos"
      params = {
        message: message.presence || '',
        url: image_url,
        access_token: page_token
      }
      
      Rails.logger.info "Facebook post_image - message: '#{message}', message length: #{message.to_s.length}"
      
      response = HTTParty.post(endpoint, body: params)
      result = JSON.parse(response.body)
      
      if result['error']
        Rails.logger.error "Facebook post_image error: #{result['error']}"
      else
        Rails.logger.info "Facebook post_image success - post ID: #{result['post_id'] || result['id']}"
      end
      
      result
    end
    
    # Post a video to Facebook
    def post_video(message, video_url, page_token, page_id: nil)
      # Use page_id if provided, otherwise use /me endpoint
      endpoint = page_id ? "#{BASE_URL}/#{page_id}/videos" : "#{BASE_URL}/me/videos"
      params = {
        description: message,
        file_url: video_url,
        access_token: page_token
      }
      
      response = HTTParty.post(endpoint, body: params)
      JSON.parse(response.body)
    end
    
    # Get the page access token from user's access token
    # @param page_id [String] Optional specific page ID to get token for
    # @return [String] Page access token
    def get_page_access_token(page_id: nil)
      url = "#{BASE_URL}/me/accounts"
      params = {
        access_token: @user.fb_user_access_key,
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      data = JSON.parse(response.body)
      
      if data['data'] && data['data'].any?
        if page_id
          # Find the specific page
          page = data['data'].find { |p| p['id'] == page_id }
          page ? page['access_token'] : data['data'].first['access_token']
        else
          # Return the first page's access token
          data['data'].first['access_token']
        end
      else
        nil
      end
    end
  end
end
