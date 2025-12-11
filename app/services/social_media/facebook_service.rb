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
    # @param page_id [String, nil] Optional page ID to post to. If nil, uses first available page.
    # @return [Hash] Response from Facebook API
    def post_photo(message, image_url, page_id: nil)
      unless @user.fb_user_access_key.present?
        raise "User does not have Facebook connected"
      end
      
      # Get page access token for the specified page
      page_token, selected_page_id = get_page_access_token(page_id: page_id)
      
      unless page_token
        raise "Could not get Facebook page access token"
      end
      
      # Determine if it's a video or photo
      extension = File.extname(image_url).downcase
      
      if ['.gif', '.mp4'].include?(extension)
        post_video(message, image_url, page_token, selected_page_id)
      else
        post_image(message, image_url, page_token, selected_page_id)
      end
    end
    
    # Fetch all Facebook pages the user has access to
    # @return [Array<Hash>] Array of page objects with id, name, and access_token
    def fetch_pages
      unless @user.fb_user_access_key.present?
        raise "User does not have Facebook connected"
      end
      
      # First, check if the user's access token has the required permissions
      check_token_permissions
      
      url = "#{BASE_URL}/me/accounts"
      params = {
        access_token: @user.fb_user_access_key,
        fields: 'id,name,access_token',
        limit: 1000
      }
      
      Rails.logger.info "Fetching Facebook pages from: #{url}"
      Rails.logger.info "Using access token (first 20 chars): #{@user.fb_user_access_key[0..20]}..."
      
      response = HTTParty.get(url, query: params)
      
      unless response.success?
        Rails.logger.error "Facebook pages fetch failed: #{response.code} - #{response.body}"
        error_data = begin
          JSON.parse(response.body)
        rescue
          { 'error' => { 'message' => response.body } }
        end
        
        error_message = error_data.dig('error', 'message') || error_data['error'] || response.body
        error_code = error_data.dig('error', 'code')
        error_type = error_data.dig('error', 'type')
        
        Rails.logger.error "Facebook API Error Details - Code: #{error_code}, Type: #{error_type}, Message: #{error_message}"
        
        # Check for specific permission errors
        if error_code == 200 || error_type == 'OAuthException' || error_message.include?('permission') || error_message.include?('scope')
          raise "Facebook permission error: #{error_message}. Please reconnect your Facebook account to grant the 'pages_manage_posts' permission."
        end
        
        raise "Facebook API error (#{error_code}): #{error_message}"
      end
      
      data = JSON.parse(response.body)
      Rails.logger.info "Facebook pages API response keys: #{data.keys.inspect}"
      Rails.logger.info "Facebook pages API response (full): #{data.inspect}"
      
      if data['error']
        error_message = data['error']['message'] || data['error'].to_s
        error_code = data['error']['code']
        error_type = data['error']['type']
        
        Rails.logger.error "Facebook API returned error: Code: #{error_code}, Type: #{error_type}, Message: #{error_message}"
        
        # Check for permission errors
        if error_code == 200 || error_type == 'OAuthException' || error_message.include?('permission') || error_message.include?('scope')
          raise "Facebook permission error: #{error_message}. Please reconnect your Facebook account to grant the 'pages_manage_posts' permission."
        end
        
        raise "Facebook API error: #{error_message}"
      end
      
      if data['data']
        pages = data['data'].map do |page|
          {
            id: page['id'],
            name: page['name'],
            access_token: page['access_token']
          }
        end
        Rails.logger.info "Successfully fetched #{pages.length} Facebook pages: #{pages.map { |p| p[:name] }.join(', ')}"
        pages
      else
        Rails.logger.warn "No 'data' in Facebook pages response. Full response: #{data.inspect}"
        
        # If we got a successful response but no data, check if it's a permissions issue
        if data['paging'] || data.empty?
          Rails.logger.warn "User may not have any pages, or may not have granted pages_manage_posts permission"
        end
        
        []
      end
    end
    
    # Check if the user's access token has the required permissions
    # Uses Facebook's debug_token endpoint to verify permissions
    def check_token_permissions
      app_id = ENV['FACEBOOK_APP_ID']
      app_secret = ENV['FACEBOOK_APP_SECRET']
      
      # Skip debug check if app credentials are not available
      unless app_id.present? && app_secret.present?
        Rails.logger.warn "Facebook app credentials not configured, skipping token debug check"
        return
      end
      
      debug_url = "#{BASE_URL}/debug_token"
      app_access_token = "#{app_id}|#{app_secret}"
      params = {
        input_token: @user.fb_user_access_key,
        access_token: app_access_token
      }
      
      begin
        response = HTTParty.get(debug_url, query: params)
        debug_data = JSON.parse(response.body)
        
        if debug_data['data']
          token_data = debug_data['data']
          scopes = token_data['scopes'] || []
          expires_at = token_data['expires_at']
          is_valid = token_data['is_valid']
          
          Rails.logger.info "Facebook token debug - Valid: #{is_valid}, Scopes: #{scopes.join(', ')}, Expires: #{expires_at}"
          
          # Check if token has expired
          if expires_at && expires_at > 0 && Time.at(expires_at) < Time.now
            raise "Facebook access token has expired. Please reconnect your Facebook account."
          end
          
          # Check if token is valid
          unless is_valid
            raise "Facebook access token is invalid. Please reconnect your Facebook account."
          end
          
          # Check for required permissions
          required_permissions = ['pages_manage_posts', 'pages_read_engagement']
          missing_permissions = required_permissions - scopes
          
          if missing_permissions.any?
            Rails.logger.warn "Missing Facebook permissions: #{missing_permissions.join(', ')}. Current scopes: #{scopes.join(', ')}"
            # Don't raise here - let the actual API call fail with a better error message
            # But log it for debugging
          else
            Rails.logger.info "Facebook token has all required permissions"
          end
        elsif debug_data['error']
          Rails.logger.warn "Facebook debug_token error: #{debug_data['error']}"
        else
          Rails.logger.warn "Could not debug Facebook token: #{debug_data.inspect}"
        end
      rescue => e
        Rails.logger.warn "Failed to check Facebook token permissions (non-blocking): #{e.message}"
        # Don't fail the request if debug fails - continue with the actual API call
      end
    end
    
    # Post to Instagram (via Facebook)
    # @param message [String] The post caption
    # @param media_url [String] Public URL of the image or video
    # @param is_video [Boolean] Whether the media is a video
    # @return [Hash] Response from Instagram API
    def post_to_instagram(message, media_url, is_video: false)
      unless @user.instagram_business_id.present?
        raise "User does not have Instagram connected"
      end
      
      page_token = get_page_access_token
      
      unless page_token
        raise "Could not get Facebook page access token for Instagram"
      end
      
      # Step 1: Create media container
      create_url = "#{BASE_URL}/#{@user.instagram_business_id}/media"
      create_params = {
        caption: message,
        access_token: page_token
      }
      
      if is_video
        create_params[:media_type] = 'REELS' # or 'VIDEO' for regular posts
        create_params[:video_url] = media_url
      else
        create_params[:image_url] = media_url
      end
      
      response = HTTParty.post(create_url, body: create_params)
      data = JSON.parse(response.body)
      
      unless data['id']
        raise "Failed to create Instagram media container: #{data['error']}"
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
      JSON.parse(response.body)
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
    def post_image(message, image_url, page_token, page_id)
      url = "#{BASE_URL}/#{page_id}/photos"
      params = {
        message: message,
        url: image_url,
        access_token: page_token
      }
      
      response = HTTParty.post(url, body: params)
      JSON.parse(response.body)
    end
    
    # Post a video to Facebook
    def post_video(message, video_url, page_token, page_id)
      url = "#{BASE_URL}/#{page_id}/videos"
      params = {
        description: message,
        file_url: video_url,
        access_token: page_token
      }
      
      response = HTTParty.post(url, body: params)
      JSON.parse(response.body)
    end
    
    # Get the page access token from user's access token
    # @param page_id [String, nil] Optional page ID. If nil, uses first available page.
    # @return [Array<String, String>] Returns [page_token, page_id] or [nil, nil] if no pages found
    def get_page_access_token(page_id: nil)
      url = "#{BASE_URL}/me/accounts"
      params = {
        access_token: @user.fb_user_access_key,
        fields: 'id,name,access_token',
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      data = JSON.parse(response.body)
      
      if data['data'] && data['data'].any?
        if page_id
          # Find the specific page
          page = data['data'].find { |p| p['id'] == page_id }
          if page
            [page['access_token'], page['id']]
          else
            # Page not found, use first page as fallback
            first_page = data['data'].first
            [first_page['access_token'], first_page['id']]
          end
        else
          # Return the first page's access token
          first_page = data['data'].first
          [first_page['access_token'], first_page['id']]
        end
      else
        [nil, nil]
      end
    end
  end
end

