module SocialMedia
  class LinkedinService
    API_BASE_URL = 'https://api.linkedin.com/v2'
    
    def initialize(user)
      @user = user
    end
    
    # Fetch user's LinkedIn organizations
    # @return [Array] Array of organization hashes with id, name, and urn
    def fetch_organizations
      unless @user.linkedin_access_token.present?
        raise "User does not have LinkedIn connected"
      end
      
      begin
        # Get organizational entity ACLs to find organizations user has access to
        url = "#{API_BASE_URL}/organizationalEntityAcls"
        headers = {
          'Authorization' => "Bearer #{@user.linkedin_access_token}",
          'X-Restli-Protocol-Version' => '2.0.0'
        }
        
        response = HTTParty.get(url, headers: headers)
        
        unless response.success?
          Rails.logger.error "LinkedIn fetch_organizations error: #{response.code} - #{response.body}"
          return []
        end
        
        data = JSON.parse(response.body)
        organizations = []
        
        if data['elements']
          data['elements'].each do |element|
            org_urn = element['organizationalTarget']
            next unless org_urn
            
            # Extract organization ID from URN (format: urn:li:organization:123)
            org_id = org_urn.split(':').last
            
            # Fetch organization details
            begin
              org_url = "#{API_BASE_URL}/organizations/#{org_id}"
              org_response = HTTParty.get(org_url, headers: headers)
              
              if org_response.success?
                org_data = JSON.parse(org_response.body)
                organizations << {
                  id: org_id,
                  name: org_data['localizedName'] || org_data['name'] || 'Unknown',
                  urn: org_urn
                }
              end
            rescue => e
              Rails.logger.warn "Failed to fetch organization #{org_id}: #{e.message}"
            end
          end
        end
        
        organizations
      rescue => e
        Rails.logger.error "LinkedIn fetch_organizations error: #{e.message}"
        []
      end
    end
    
    # Get personal profile URN
    # @return [String] URN in format urn:li:person:profile_id
    def get_personal_profile_urn
      # If profile ID exists, return URN
      if @user.linkedin_profile_id.present?
        return "urn:li:person:#{@user.linkedin_profile_id}"
      end
      
      # Otherwise, try to fetch it
      profile_id = fetch_profile_id
      if profile_id
        return "urn:li:person:#{profile_id}"
      end
      
      # If still no profile ID, try /me endpoint
      begin
        url = "#{API_BASE_URL}/me"
        headers = {
          'Authorization' => "Bearer #{@user.linkedin_access_token}",
          'X-Restli-Protocol-Version' => '2.0.0'
        }
        
        response = HTTParty.get(url, headers: headers)
        if response.success?
          data = JSON.parse(response.body)
          if data['id']
            profile_id = data['id']
            @user.update!(linkedin_profile_id: profile_id)
            return "urn:li:person:#{profile_id}"
          end
        end
      rescue => e
        Rails.logger.warn "Failed to get profile URN from /me: #{e.message}"
      end
      
      # Last resort: try userInfo endpoint
      begin
        url = "https://api.linkedin.com/v2/userinfo"
        headers = {
          'Authorization' => "Bearer #{@user.linkedin_access_token}"
        }
        
        response = HTTParty.get(url, headers: headers)
        if response.success?
          data = JSON.parse(response.body)
          if data['sub']
            profile_id = data['sub'].to_s.split(':').last
            @user.update!(linkedin_profile_id: profile_id)
            return "urn:li:person:#{profile_id}"
          end
        end
      rescue => e
        Rails.logger.warn "Failed to get profile URN from userInfo: #{e.message}"
      end
      
      nil
    end
    
    # Post to LinkedIn with image
    # @param message [String] Post text
    # @param image_path [String] Local path to image file
    # @return [Hash] Response from LinkedIn API
    def post_with_image(message, image_path)
      unless @user.linkedin_access_token.present?
        raise "User does not have LinkedIn connected"
      end
      
      # Try to get profile ID if not stored - but don't fail if we can't get it
      # We'll try to extract it from the posting API response
      unless @user.linkedin_profile_id.present?
        begin
          fetch_profile_id
        rescue => e
          Rails.logger.warn "Could not fetch LinkedIn profile ID: #{e.message}. Will try to extract from posting API."
        end
      end
      
      # If still no profile ID, try to get it from the access token or posting flow
      unless @user.linkedin_profile_id.present?
        profile_id = extract_profile_id_from_token
        if profile_id
          @user.update!(linkedin_profile_id: profile_id)
          Rails.logger.info "LinkedIn profile ID extracted from token: #{profile_id}"
        end
      end
      
      # Step 1: Register upload
      asset_urn = register_upload
      
      # Step 2: Upload image
      upload_image(asset_urn, image_path)
      
      # Step 3: Create post
      create_post(message, asset_urn)
    end
    
    private
    
    # Fetch user's LinkedIn profile ID
    # Note: This may fail if scopes are not available - that's OK, we'll try other methods
    def fetch_profile_id
      # Try /me endpoint first (requires r_liteprofile scope)
      profile_id = fetch_profile_id_from_me
      
      # Fallback to userInfo endpoint if /me doesn't work (requires openid scope)
      if profile_id.nil?
        Rails.logger.warn "/me endpoint didn't return ID, trying userInfo endpoint"
        profile_id = fetch_profile_id_from_userinfo
      end
      
      if profile_id
        @user.update!(linkedin_profile_id: profile_id)
        Rails.logger.info "LinkedIn profile ID saved: #{profile_id}"
        return profile_id
      else
        Rails.logger.warn "Failed to fetch LinkedIn profile ID from API endpoints - will try to extract from token or posting flow"
        return nil
      end
    end
    
    # Try to extract profile ID from the access token or by making a test API call
    def extract_profile_id_from_token
      # Try multiple methods to get profile ID
      
      # Method 1: Try to decode access token if it's a JWT (OpenID Connect tokens are JWTs)
      begin
        # LinkedIn access tokens might be JWTs that contain user info
        token_parts = @user.linkedin_access_token.split('.')
        if token_parts.length == 3 # JWT has 3 parts
          # Decode the payload (second part)
          require 'base64'
          payload = Base64.urlsafe_decode64(token_parts[1])
          token_data = JSON.parse(payload)
          
          # Check for common JWT claims that might contain user ID
          if token_data['sub']
            profile_id = token_data['sub'].to_s.split(':').last
            Rails.logger.info "Extracted LinkedIn profile ID from JWT token: #{profile_id}"
            return profile_id
          end
        end
      rescue => e
        Rails.logger.debug "Access token is not a JWT or doesn't contain profile ID: #{e.message}"
      end
      
      # Method 2: Try /me endpoint with minimal projection
      begin
        url = "#{API_BASE_URL}/me?projection=(id)"
        headers = {
          'Authorization' => "Bearer #{@user.linkedin_access_token}",
          'X-Restli-Protocol-Version' => '2.0.0'
        }
        
        response = HTTParty.get(url, headers: headers)
        if response.success?
          data = JSON.parse(response.body)
          return data['id'] if data['id']
        end
      rescue => e
        Rails.logger.debug "Could not get profile ID from /me endpoint: #{e.message}"
      end
      
      nil
    end
    
    # Fetch profile ID using /me endpoint (requires r_liteprofile scope)
    def fetch_profile_id_from_me
      url = "#{API_BASE_URL}/me"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      response = HTTParty.get(url, headers: headers)
      
      unless response.success?
        Rails.logger.warn "LinkedIn /me endpoint failed: #{response.code} - #{response.body}"
        return nil
      end
      
      data = JSON.parse(response.body)
      Rails.logger.info "LinkedIn /me response: #{data.inspect}"
      
      # Try to extract ID from various possible fields
      if data['id']
        return data['id']
      end
      
      nil
    end
    
    # Fetch profile ID using userInfo endpoint (OpenID Connect - requires openid scope, may not be available)
    def fetch_profile_id_from_userinfo
      url = "https://api.linkedin.com/v2/userinfo"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}"
      }
      
      response = HTTParty.get(url, headers: headers)
      
      unless response.success?
        Rails.logger.warn "LinkedIn userInfo endpoint failed: #{response.code} - #{response.body}"
        return nil
      end
      
      data = JSON.parse(response.body)
      Rails.logger.info "LinkedIn userInfo response: #{data.inspect}"
      
      # userInfo endpoint returns 'sub' as the user ID (format: urn:li:person:xxxxx or just xxxxx)
      if data['sub']
        # Extract just the ID part if it's a URN
        profile_id = data['sub'].to_s.split(':').last
        Rails.logger.info "Extracted profile ID from userInfo: #{profile_id}"
        return profile_id
      end
      
      nil
    end
    
    # Register an upload with LinkedIn
    # @return [String] Asset URN
    def register_upload
      # Profile ID is required for registerUpload - if we don't have it, we need to get it first
      unless @user.linkedin_profile_id.present?
        # Try one more time to get it from token
        profile_id = extract_profile_id_from_token
        if profile_id
          @user.update!(linkedin_profile_id: profile_id)
          Rails.logger.info "LinkedIn profile ID extracted from token before upload: #{profile_id}"
        else
          # Try to get it by attempting upload without owner - LinkedIn error might tell us
          Rails.logger.warn "No LinkedIn profile ID available - will try upload without owner to extract from error"
        end
      end
      
      url = "#{API_BASE_URL}/assets?action=registerUpload"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'Content-Type' => 'application/json',
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      # Profile ID is required - if we still don't have it, try without owner to get error with profile ID
      owner_urn = @user.linkedin_profile_id.present? ? "urn:li:person:#{@user.linkedin_profile_id}" : nil
      
      body = {
        registerUploadRequest: {
          recipes: ['urn:li:digitalmediaRecipe:feedshare-image'],
          serviceRelationships: [
            {
              relationshipType: 'OWNER',
              identifier: 'urn:li:userGeneratedContent'
            }
          ]
        }
      }
      
      # Owner is required - if we don't have profile ID, try without it to see error
      if owner_urn
        body[:registerUploadRequest][:owner] = owner_urn
      end
      
      response = HTTParty.post(url, headers: headers, body: body.to_json)
      data = JSON.parse(response.body)
      
      # If registration failed, try to extract profile ID from error
      unless response.success?
        error_msg = data['message'] || data.to_s || response.body
        Rails.logger.warn "LinkedIn upload registration failed: #{error_msg}"
        Rails.logger.warn "Full error response: #{data.inspect}"
        
        # Try multiple patterns to extract profile ID from error
        profile_id = nil
        
        # Pattern 1: urn:li:person:XXXXX
        if error_msg.include?('person:')
          match = error_msg.match(/urn:li:person:([A-Za-z0-9_-]+)/)
          profile_id = match[1] if match
        end
        
        # Pattern 2: Look for numeric ID in error
        unless profile_id
          match = error_msg.match(/person[:\s]+([A-Za-z0-9_-]+)/i)
          profile_id = match[1] if match
        end
        
        # Pattern 3: Check if error contains a LinkedIn URN format
        unless profile_id
          match = error_msg.match(/([A-Za-z0-9_-]{10,})/)
          # LinkedIn profile IDs are typically alphanumeric and at least 10 characters
          profile_id = match[1] if match && match[1].length >= 10
        end
        
        if profile_id && !@user.linkedin_profile_id.present?
          @user.update!(linkedin_profile_id: profile_id)
          Rails.logger.info "Extracted LinkedIn profile ID from error message: #{profile_id}"
          # Retry with the extracted profile ID
          return register_upload
        end
        
        # If we still don't have profile ID, provide helpful error
        if !@user.linkedin_profile_id.present?
          raise "LinkedIn profile ID is required for posting. Please enable OpenID Connect in your LinkedIn app settings (Products > Sign In with LinkedIn using OpenID Connect) and reconnect your LinkedIn account. Error: #{error_msg}"
        else
          raise "Failed to register LinkedIn upload: #{error_msg}"
        end
      end
      
      if data['value']
        upload_url = data['value']['uploadMechanism']['com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest']['uploadUrl']
        asset_urn = data['value']['asset']
        
        # Store upload URL for next step
        @upload_url = upload_url
        
        asset_urn
      else
        raise "Failed to register LinkedIn upload: #{data['message'] || 'Unknown error'}"
      end
    end
    
    # Upload image to LinkedIn
    # @param asset_urn [String] Asset URN from registration
    # @param image_path [String] Local path to image or URL
    def upload_image(asset_urn, image_path)
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      # Handle URLs by downloading to temp file
      temp_file = nil
      actual_path = image_path
      
      if image_path.start_with?('http://') || image_path.start_with?('https://')
        temp_file = download_image_to_temp(image_path)
        actual_path = temp_file.path
      end
      
      begin
        # Read image file in binary mode
        image_data = File.binread(actual_path)
        Rails.logger.info "LinkedIn upload - file size: #{image_data.length} bytes, upload_url: #{@upload_url}"
        
        # Detect image content type from file
        content_type = detect_image_content_type(actual_path, image_data)
        headers['Content-Type'] = content_type if content_type
        Rails.logger.info "LinkedIn upload - Content-Type: #{content_type}"
        
        response = HTTParty.post(@upload_url, 
          headers: headers,
          body: image_data,
          timeout: 30
        )
        
        Rails.logger.info "LinkedIn upload response - status: #{response.code}, body: #{response.body[0..500]}"
        
        unless response.success?
          error_msg = response.body || "Unknown error"
          Rails.logger.error "LinkedIn upload failed - status: #{response.code}, error: #{error_msg}"
          raise "Failed to upload image to LinkedIn: #{response.code} - #{error_msg}"
        end
      rescue => e
        Rails.logger.error "LinkedIn upload exception: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      ensure
        # Clean up temp file if we created one
        if temp_file
          temp_file.close
          temp_file.unlink
        end
      end
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
      temp_file = Tempfile.new(['linkedin_image', extension])
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
    
    # Detect image content type from file path or data
    # @param file_path [String] Path to image file
    # @param image_data [String] Image file data (first few bytes for magic number detection)
    # @return [String] Content-Type header value
    def detect_image_content_type(file_path, image_data = nil)
      # Try to detect from file extension first
      extension = File.extname(file_path).downcase
      case extension
      when '.jpg', '.jpeg'
        return 'image/jpeg'
      when '.png'
        return 'image/png'
      when '.gif'
        return 'image/gif'
      when '.webp'
        return 'image/webp'
      end
      
      # If extension doesn't help, try magic number detection
      if image_data && image_data.length >= 4
        magic = image_data[0..3]
        case magic
        when "\xFF\xD8\xFF".b
          return 'image/jpeg'
        when "\x89PNG".b
          return 'image/png'
        when "GIF8".b
          return 'image/gif'
        when "RIFF".b
          return 'image/webp' if image_data[8..11] == "WEBP".b
        end
      end
      
      # Default to JPEG if we can't determine
      'image/jpeg'
    end
    
    # Create LinkedIn post
    # @param message [String] Post text
    # @param asset_urn [String] Asset URN of uploaded image
    # @return [Hash] Response from LinkedIn API
    def create_post(message, asset_urn)
      # Profile ID is required for posting - if we still don't have it, we can't proceed
      unless @user.linkedin_profile_id.present?
        raise "LinkedIn profile ID is required for posting. Please reconnect LinkedIn with OpenID Connect enabled in your LinkedIn app settings, or contact support."
      end
      
      url = "#{API_BASE_URL}/ugcPosts"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'Content-Type' => 'application/json',
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      body = {
        author: "urn:li:person:#{@user.linkedin_profile_id}",
        lifecycleState: 'PUBLISHED',
        specificContent: {
          'com.linkedin.ugc.ShareContent' => {
            shareCommentary: {
              text: message
            },
            shareMediaCategory: 'IMAGE',
            media: [
              {
                status: 'READY',
                description: {
                  text: message
                },
                media: asset_urn,
                title: {
                  text: message
                }
              }
            ]
          }
        },
        visibility: {
          'com.linkedin.ugc.MemberNetworkVisibility' => 'PUBLIC'
        }
      }
      
      response = HTTParty.post(url, headers: headers, body: body.to_json)
      data = JSON.parse(response.body)
      
      unless response.success?
        error_msg = data['message'] || response.body
        Rails.logger.error "LinkedIn post creation failed: #{error_msg}"
        
        # Try to extract profile ID from error if it's mentioned
        if error_msg.include?('person:') && !@user.linkedin_profile_id.present?
          match = error_msg.match(/urn:li:person:(\w+)/)
          if match
            profile_id = match[1]
            @user.update!(linkedin_profile_id: profile_id)
            Rails.logger.info "Extracted LinkedIn profile ID from post error: #{profile_id}"
            # Retry the post
            return create_post(message, asset_urn)
          end
        end
        
        raise "Failed to create LinkedIn post: #{error_msg}"
      end
      
      data
    end
  end
end
