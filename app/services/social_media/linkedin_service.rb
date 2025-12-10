module SocialMedia
  class LinkedinService
    API_BASE_URL = 'https://api.linkedin.com/v2'
    
    def initialize(user)
      @user = user
    end
    
    # Post to LinkedIn with image
    # @param message [String] Post text
    # @param image_path [String] Local path to image file
    # @param organization_id [String, nil] Optional organization/company URN to post to. If nil, posts to personal profile.
    # @return [Hash] Response from LinkedIn API
    def post_with_image(message, image_path, organization_id: nil)
      unless @user.linkedin_access_token.present?
        raise "User does not have LinkedIn connected"
      end
      
      # Determine the author URN (personal profile or organization)
      author_urn = organization_id || get_personal_profile_urn
      
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
      asset_urn = register_upload(author_urn: author_urn)
      
      # Step 2: Upload image
      upload_image(asset_urn, image_path)
      
      # Step 3: Create post
      create_post(message, asset_urn, author_urn: author_urn)
    end
    
    # Fetch all LinkedIn organizations/companies the user manages
    # @return [Array<Hash>] Array of organization objects with id, name, and URN
    def fetch_organizations
      unless @user.linkedin_access_token.present?
        raise "User does not have LinkedIn connected"
      end
      
      url = "#{API_BASE_URL}/organizationAcls?q=roleAssignee"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      response = HTTParty.get(url, headers: headers)
      
      unless response.success?
        Rails.logger.warn "LinkedIn organizations fetch failed: #{response.code} - #{response.body}"
        return []
      end
      
      data = JSON.parse(response.body)
      organizations = []
      
      if data['elements']
        # Extract organization URNs from the ACLs
        org_urns = data['elements'].map { |acl| acl['organization~'] }.compact.uniq
        
        # Fetch details for each organization
        org_urns.each do |org_urn|
          begin
            org_data = fetch_organization_details(org_urn)
            organizations << org_data if org_data
          rescue => e
            Rails.logger.warn "Failed to fetch details for organization #{org_urn}: #{e.message}"
          end
        end
      end
      
      organizations
    end
    
    # Get personal profile URN
    # @return [String] URN in format "urn:li:person:PROFILE_ID"
    def get_personal_profile_urn
      unless @user.linkedin_profile_id.present?
        fetch_profile_id
      end
      
      if @user.linkedin_profile_id.present?
        "urn:li:person:#{@user.linkedin_profile_id}"
      else
        raise "LinkedIn profile ID is required"
      end
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
    # @param author_urn [String] URN of the author (person or organization)
    # @return [String] Asset URN
    def register_upload(author_urn: nil)
      # Use provided author_urn or get personal profile URN
      owner_urn = author_urn || get_personal_profile_urn
      
      url = "#{API_BASE_URL}/assets?action=registerUpload"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'Content-Type' => 'application/json',
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      body = {
        registerUploadRequest: {
          owner: owner_urn,
          recipes: ['urn:li:digitalmediaRecipe:feedshare-image'],
          serviceRelationships: [
            {
              relationshipType: 'OWNER',
              identifier: 'urn:li:userGeneratedContent'
            }
          ]
        }
      }
      
      response = HTTParty.post(url, headers: headers, body: body.to_json)
      data = JSON.parse(response.body)
      
      unless response.success?
        error_msg = data['message'] || data.to_s || response.body
        Rails.logger.error "LinkedIn upload registration failed: #{error_msg}"
        raise "Failed to register LinkedIn upload: #{error_msg}"
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
    # @param author_urn [String] URN of the author (person or organization)
    # @return [Hash] Response from LinkedIn API
    def create_post(message, asset_urn, author_urn: nil)
      # Use provided author_urn or get personal profile URN
      owner_urn = author_urn || get_personal_profile_urn
      
      url = "#{API_BASE_URL}/ugcPosts"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'Content-Type' => 'application/json',
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      body = {
        author: owner_urn,
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
        raise "Failed to create LinkedIn post: #{error_msg}"
      end
      
      data
    end
    
    # Fetch organization details
    # @param org_urn [String] Organization URN (e.g., "urn:li:organization:12345")
    # @return [Hash, nil] Organization details with id, name, and URN
    def fetch_organization_details(org_urn)
      # Extract organization ID from URN
      org_id = org_urn.split(':').last
      
      url = "#{API_BASE_URL}/organizations/#{org_id}"
      headers = {
        'Authorization' => "Bearer #{@user.linkedin_access_token}",
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      params = {
        projection: '(id,localizedName)'
      }
      
      response = HTTParty.get(url, headers: headers, query: params)
      
      unless response.success?
        Rails.logger.warn "Failed to fetch organization details for #{org_urn}: #{response.code}"
        return nil
      end
      
      data = JSON.parse(response.body)
      
      {
        id: data['id'],
        name: data['localizedName'] || data['name'] || "Organization #{org_id}",
        urn: org_urn
      }
    end
  end
end

