class Api::V1::UserInfoController < ApplicationController
  before_action :authenticate_user!

  # GET /api/v1/user_info
  def show
    begin
      # Fetch YouTube channel name if missing (non-blocking)
      fetch_youtube_channel_name_if_missing(current_user)
      
      user_data = user_json(current_user)
      Rails.logger.info "UserInfoController#show - User #{current_user.id} (#{current_user.email}): account_id=#{current_user.account_id}, super_admin=#{user_data[:super_admin]}"
      
      render json: {
        user: user_data,
        connected_accounts: get_connected_accounts
      }
    rescue => e
      Rails.logger.error "User info error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        error: 'Failed to load user info',
        message: e.message
      }, status: :internal_server_error
    end
  end

  # PATCH /api/v1/user_info
  def update
    if current_user.update(user_params)
      render json: {
        user: user_json(current_user),
        message: 'User information updated successfully'
      }
    else
      render json: {
        errors: current_user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/user_info/watermark
  def update_watermark
    begin
      # Handle watermark logo removal (empty string or nil)
      if params[:watermark_logo].present? && (params[:watermark_logo] == '' || params[:watermark_logo] == 'null')
        current_user.update!(watermark_logo: nil)
        return render json: {
          user: user_json(current_user),
          message: 'Watermark logo removed successfully'
        }
      end
      
      # Handle watermark logo file upload
      if params[:watermark_logo].present? && params[:watermark_logo].respond_to?(:read)
        uploaded_file = params[:watermark_logo]
        
        # Validate file type
        unless uploaded_file.content_type&.start_with?('image/')
          return render json: { error: 'Invalid file type. Please upload an image file.' }, status: :bad_request
        end
        
        # Generate unique filename
        file_extension = File.extname(uploaded_file.original_filename).presence || '.png'
        unique_filename = "#{SecureRandom.uuid}#{file_extension}"
        
        # Upload to storage (DigitalOcean Spaces or local)
        if Rails.env.production?
          spaces_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
          if spaces_key.present?
            watermark_path = upload_watermark_to_spaces(uploaded_file, unique_filename)
          else
            return render json: { error: 'Storage not configured' }, status: :internal_server_error
          end
        else
          watermark_path = upload_watermark_locally(uploaded_file, unique_filename)
        end
        
        # Update user with watermark logo filename
        current_user.update!(watermark_logo: unique_filename)
      end

      # Update watermark settings (opacity, scale, position)
      watermark_params = params.permit(:watermark_opacity, :watermark_scale, :watermark_offset_x, :watermark_offset_y)
      
      if current_user.update(watermark_params)
        render json: {
          user: user_json(current_user),
          message: 'Watermark settings updated successfully'
        }
      else
        render json: {
          errors: current_user.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Watermark update error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        error: 'Failed to update watermark',
        message: e.message
      }, status: :internal_server_error
    end
  end
  
  private
  
  # Upload watermark logo to DigitalOcean Spaces
  def upload_watermark_to_spaces(uploaded_file, unique_filename)
    require 'aws-sdk-s3'
    
    access_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
    secret_key = ENV['DO_SPACES_SECRET'] || ENV['DIGITAL_OCEAN_SPACES_SECRET']
    endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://sfo2.digitaloceanspaces.com'
    region = ENV['DO_SPACES_REGION'] || ENV['DIGITAL_OCEAN_SPACES_REGION'] || 'sfo2'
    bucket_name = ENV['DO_SPACES_BUCKET'] || ENV['DIGITAL_OCEAN_SPACES_NAME']
    
    # Configure AWS SDK for DigitalOcean Spaces
    s3_client = Aws::S3::Client.new(
      access_key_id: access_key,
      secret_access_key: secret_key,
      endpoint: endpoint,
      region: region,
      force_path_style: false
    )
    
    # Path format: environment/user_id/watermarks/filename
    key = "#{Rails.env}/#{current_user.id}/watermarks/#{unique_filename}"
    
    # Upload the file
    s3_client.put_object(
      bucket: bucket_name,
      key: key,
      body: uploaded_file.read,
      acl: 'public-read',
      content_type: uploaded_file.content_type
    )
    
    # Return the path
    key
  end
  
  # Upload watermark logo locally (development/test)
  def upload_watermark_locally(uploaded_file, unique_filename)
    # Create directory if it doesn't exist
    upload_dir = Rails.root.join('public', 'storage', Rails.env.to_s, current_user.id.to_s, 'watermarks')
    FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
    
    # Save the file
    file_path = upload_dir.join(unique_filename)
    File.open(file_path, 'wb') do |file|
      file.write(uploaded_file.read)
    end
    
    # Return relative path for database (just the filename, path is handled by User model methods)
    unique_filename
  end

  # GET /api/v1/user_info/connected_accounts
  def connected_accounts
    render json: {
      connected_accounts: get_connected_accounts
    }
  end

  # GET /api/v1/user_info/support
  # Get support contact information
  def support
    support_email = ENV['SUPPORT_EMAIL'] || 'support@socialrotation.app'
    support_url = ENV['SUPPORT_URL'] || 'https://socialrotation.app/support'
    
    render json: {
      support_email: support_email,
      support_url: support_url,
      message: 'You can update your email address in your account settings. Your account and subscription will remain active.'
    }
  end

  # GET /api/v1/user_info/facebook_pages
  def facebook_pages
    unless current_user.fb_user_access_key.present?
      return render json: { error: 'Facebook not connected' }, status: :unauthorized
    end

    begin
      facebook_service = SocialMedia::FacebookService.new(current_user)
      pages = facebook_service.fetch_pages
      render json: { pages: pages }
    rescue => e
      Rails.logger.error "Facebook pages error: #{e.message}"
      render json: { error: 'Failed to fetch Facebook pages', message: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/user_info/linkedin_organizations
  def linkedin_organizations
    unless current_user.linkedin_access_token.present?
      return render json: { error: 'LinkedIn not connected' }, status: :unauthorized
    end

    begin
      linkedin_service = SocialMedia::LinkedinService.new(current_user)
      organizations = linkedin_service.fetch_organizations
      render json: { organizations: organizations }
    rescue => e
      Rails.logger.error "LinkedIn organizations error: #{e.message}"
      render json: { error: 'Failed to fetch LinkedIn organizations', message: e.message }, status: :internal_server_error
    end
  end

  # GET /api/v1/user_info/debug
  # Debug endpoint to check what account info is stored
  def debug
    user = current_user
    render json: {
      user_id: user.id,
      email: user.email,
      # Facebook
      fb_user_access_key: user.fb_user_access_key.present? ? 'present' : 'nil',
      facebook_name: user.respond_to?(:facebook_name) ? user.facebook_name : 'column_not_exists',
      # Twitter
      twitter_oauth_token: user.twitter_oauth_token.present? ? 'present' : 'nil',
      twitter_screen_name: user.respond_to?(:twitter_screen_name) ? user.twitter_screen_name : 'column_not_exists',
      # LinkedIn
      linkedin_access_token: user.linkedin_access_token.present? ? 'present' : 'nil',
      linkedin_profile_id: user.respond_to?(:linkedin_profile_id) ? user.linkedin_profile_id : 'column_not_exists',
      # Google
      google_refresh_token: user.google_refresh_token.present? ? 'present' : 'nil',
      google_account_name: user.respond_to?(:google_account_name) ? user.google_account_name : 'column_not_exists',
      # TikTok
      tiktok_access_token: user.tiktok_access_token.present? ? 'present' : 'nil',
      tiktok_username: user.respond_to?(:tiktok_username) ? user.tiktok_username : 'column_not_exists',
      # YouTube
      youtube_access_token: user.youtube_access_token.present? ? 'present' : 'nil',
      youtube_channel_id: user.respond_to?(:youtube_channel_id) ? user.youtube_channel_id : 'column_not_exists',
      # Pinterest
      pinterest_access_token: user.respond_to?(:pinterest_access_token) ? (user.pinterest_access_token.present? ? 'present' : 'nil') : 'column_not_exists',
      pinterest_username: user.respond_to?(:pinterest_username) ? user.pinterest_username : 'column_not_exists',
      # Instagram
      instagram_business_id: user.instagram_business_id,
      # All columns check
      has_facebook_name_column: user.respond_to?(:facebook_name),
      has_google_account_name_column: user.respond_to?(:google_account_name),
      has_pinterest_username_column: user.respond_to?(:pinterest_username)
    }
  end

  # POST /api/v1/user_info/disconnect_facebook
  def disconnect_facebook
    update_params = {
      fb_user_access_key: nil,
      instagram_business_id: nil
    }
    update_params[:facebook_name] = nil if current_user.respond_to?(:facebook_name=)
    current_user.update!(update_params)
    
    render json: { message: 'Facebook disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_twitter
  def disconnect_twitter
    current_user.update!(
      twitter_oauth_token: nil,
      twitter_oauth_token_secret: nil,
      twitter_user_id: nil,
      twitter_screen_name: nil,
      twitter_url_oauth_token: nil,
      twitter_url_oauth_token_secret: nil
    )
    
    render json: { message: 'Twitter disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_linkedin
  def disconnect_linkedin
    current_user.update!(
      linkedin_access_token: nil,
      linkedin_access_token_time: nil,
      linkedin_profile_id: nil
    )
    
    render json: { message: 'LinkedIn disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_instagram
  def disconnect_instagram
    current_user.update!(
      instagram_business_id: nil
    )
    
    render json: { message: 'Instagram disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_google
  def disconnect_google
    update_params = {
      google_refresh_token: nil,
      location_id: nil
    }
    update_params[:google_account_name] = nil if current_user.respond_to?(:google_account_name=)
    current_user.update!(update_params)
    
    render json: { message: 'Google My Business disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_tiktok
  def disconnect_tiktok
    current_user.update!(
      tiktok_access_token: nil,
      tiktok_refresh_token: nil,
      tiktok_user_id: nil,
      tiktok_username: nil
    )
    
    render json: { message: 'TikTok disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_youtube
  def disconnect_youtube
    update_params = {
      youtube_access_token: nil,
      youtube_refresh_token: nil,
      youtube_channel_id: nil
    }
    update_params[:youtube_channel_name] = nil if current_user.respond_to?(:youtube_channel_name=)
    
    current_user.update!(update_params)
    
    render json: { message: 'YouTube disconnected successfully' }
  end

  # POST /api/v1/user_info/disconnect_pinterest
  def disconnect_pinterest
    if current_user.respond_to?(:pinterest_access_token)
      update_params = {
        pinterest_access_token: nil,
        pinterest_refresh_token: nil
      }
      update_params[:pinterest_username] = nil if current_user.respond_to?(:pinterest_username=)
      current_user.update!(update_params)
      render json: { message: 'Pinterest disconnected successfully' }
    else
      render json: { message: 'Pinterest not connected' }, status: :bad_request
    end
  end

  # POST /api/v1/user_info/toggle_instagram
  def toggle_instagram
    current_user.update!(post_to_instagram: params[:post_to_instagram] == 'true')
    
    render json: {
      message: 'Instagram posting status updated',
      post_to_instagram: current_user.post_to_instagram
    }
  end

  # DELETE /api/v1/user_info/delete_test_account
  # Delete a test account by email (for testing purposes)
  # Requires: email parameter
  def delete_test_account
    email = params[:email]
    
    unless email.present?
      return render json: { error: 'Email is required' }, status: :bad_request
    end
    
    user = User.find_by(email: email)
    
    unless user
      return render json: { error: 'User not found' }, status: :not_found
    end
    
    # Prevent deleting your own account
    if user.id == current_user.id
      return render json: { error: 'Cannot delete your own account' }, status: :bad_request
    end
    
    begin
      # Delete associated account if user is account admin
      if user.account && user.is_account_admin
        account = user.account
        # Delete subscription if exists
        account.subscription&.destroy
        # Delete account (this will cascade delete the user)
        account.destroy
        message = "User and account deleted successfully"
      else
        # Just delete the user
        user.destroy
        message = "User deleted successfully"
      end
      
      render json: { message: message, deleted_email: email }
    rescue => e
      Rails.logger.error "Error deleting account: #{e.message}"
      render json: { error: "Failed to delete account: #{e.message}" }, status: :internal_server_error
    end
  end

  # POST /api/v1/user_info/convert_to_agency
  # Convert a personal account to an agency account
  def convert_to_agency
    # Only allow conversion if user is account admin or has account_id = 0 (personal/super admin)
    unless current_user.account_id == 0 || current_user.is_account_admin?
      return render json: { error: 'Only account admins can convert accounts' }, status: :forbidden
    end

    # Check if user is a super admin (account_id = 0)
    is_super_admin = current_user.super_admin?

    # If user has account_id = 0 (super admin), create a new agency account
    # Super admin access is preserved via email check in require_active_subscription!
    if current_user.account_id == 0
      # For super admins, create the agency account and assign it
      # This allows them to manage sub-accounts properly
      # Super admin access is preserved via email check in require_active_subscription!
      account = Account.create!(
        name: params[:company_name] || "#{current_user.name}'s Agency",
        is_reseller: true,
        status: true
      )
      
      # Update user to be part of the new agency account
      # Super admin access is preserved via email check in require_active_subscription!
      current_user.update!(
        account_id: account.id,
        is_account_admin: true,
        role: 'reseller'
      )
      
      Rails.logger.info "Super admin #{current_user.email} converted to agency (account_id set to #{account.id}, super admin access preserved via email check)"
      
      render json: {
        user: user_json(current_user),
        message: 'Account successfully converted to agency account. Super admin access preserved.'
      }
    else
      # User already has an account, just convert it to agency
      account = current_user.account
      account.update!(is_reseller: true)
      
      # Update user role
      current_user.update!(role: 'reseller') if current_user.is_account_admin?
      
      render json: {
        user: user_json(current_user),
        message: 'Account successfully converted to agency account'
      }
    end
  rescue => e
    Rails.logger.error "Convert to agency error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'Failed to convert account', details: e.message }, status: :internal_server_error
  end

  # GET /api/v1/user_info/watermark_preview
  def watermark_preview
    # This would generate a watermark preview image
    # For now, return a placeholder URL
    render json: {
      preview_url: current_user.get_watermark_preview
    }
  end

  # GET /api/v1/user_info/standard_preview
  def standard_preview
    # This would generate a standard watermark preview
    # For now, return a placeholder URL
    render json: {
      preview_url: '/user/standard_preview'
    }
  end

  private
  
  # Check if user can post to Instagram
  # Instagram requires: 1) Instagram Business ID, 2) Facebook connected (for page token), 3) A page with Instagram linked
  def can_post_to_instagram?(user)
    return false unless user.instagram_business_id.present?
    return false unless user.fb_user_access_key.present?
    
    # Check if there's a page with Instagram linked
    begin
      facebook_service = SocialMedia::FacebookService.new(user)
      page_token = facebook_service.get_page_token_for_instagram(user.instagram_business_id)
      page_token.present?
    rescue => e
      Rails.logger.warn "Instagram posting validation error: #{e.message}"
      false
    end
  end
  
  # Get Instagram account information (username, name, etc.)
  def get_instagram_account_info(user)
    return nil unless user.fb_user_access_key.present? && user.instagram_business_id.present?
    
    begin
      # Get page access token
      url = "https://graph.facebook.com/v18.0/me/accounts"
      params = {
        access_token: user.fb_user_access_key,
        fields: 'id,name,access_token,instagram_business_account',
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      data = JSON.parse(response.body)
      
      page_token = nil
      if data['data'] && data['data'].any?
        # Find the page that has the Instagram account
        data['data'].each do |page|
          if page['instagram_business_account'] && page['instagram_business_account']['id'] == user.instagram_business_id
            page_token = page['access_token']
            break
          end
        end
        # Fallback to first page if no match
        page_token ||= data['data'].first['access_token']
      end
      
      return nil unless page_token
      
      # Get Instagram account details
      instagram_url = "https://graph.facebook.com/v18.0/#{user.instagram_business_id}"
      instagram_params = {
        access_token: page_token,
        fields: 'id,username,name'
      }
      
      instagram_response = HTTParty.get(instagram_url, query: instagram_params)
      
      if instagram_response.success?
        JSON.parse(instagram_response.body)
      else
        nil
      end
    rescue => e
      Rails.logger.error "Error fetching Instagram account info: #{e.message}"
      nil
    end
  end

  def user_params
    params.require(:user).permit(
      :name, :email, :timezone, :watermark_opacity, :watermark_scale,
      :watermark_offset_x, :watermark_offset_y, :post_to_instagram
    )
  end

  def get_connected_accounts
    accounts = []
    
    accounts << 'google_business' if current_user.google_refresh_token.present?
    accounts << 'twitter' if current_user.twitter_oauth_token.present?
    accounts << 'facebook' if current_user.fb_user_access_key.present?
    accounts << 'instagram' if current_user.post_to_instagram?
    accounts << 'linked_in' if current_user.linkedin_access_token.present?
    
    accounts
  end

  def user_json(user)
    account = user.account
    account_type = if account&.is_reseller
      'agency'
    elsif user.account_id == 0
      'personal'
    else
      'personal' # Default fallback
    end
    
    {
      id: user.id,
      name: user.name,
      email: user.email,
      timezone: user.timezone,
      watermark_logo: user.watermark_logo,
      watermark_scale: user.watermark_scale,
      watermark_opacity: user.watermark_opacity,
      watermark_offset_x: user.watermark_offset_x,
      watermark_offset_y: user.watermark_offset_y,
      post_to_instagram: user.post_to_instagram,
      watermark_preview_url: user.get_watermark_preview,
      watermark_logo_url: user.get_watermark_logo,
      digital_ocean_watermark_path: user.get_digital_ocean_watermark_path,
      created_at: user.created_at,
      updated_at: user.updated_at,
      account_type: account_type,
      account_id: user.account_id,
      is_account_admin: user.is_account_admin,
      super_admin: user.super_admin?,
      role: user.role,
      reseller: user.reseller?,
      # Social media connection status
      facebook_connected: user.fb_user_access_key.present?,
      twitter_connected: user.twitter_oauth_token.present?,
      linkedin_connected: user.linkedin_access_token.present?,
      google_connected: user.google_refresh_token.present?,
      instagram_connected: user.instagram_business_id.present?,
      instagram_business_id: user.instagram_business_id,
      instagram_account: user.instagram_business_id.present? ? get_instagram_account_info(user) : nil,
      instagram_can_post: can_post_to_instagram?(user),
      tiktok_connected: user.tiktok_access_token.present?,
      youtube_connected: user.youtube_access_token.present?,
      pinterest_connected: (user.respond_to?(:pinterest_access_token) && user.pinterest_access_token.present?) || false,
      # Account information for connected platforms
      facebook_account: (user.fb_user_access_key.present? && user.respond_to?(:facebook_name) && user.facebook_name.present?) ? { name: user.facebook_name } : nil,
      twitter_account: (user.twitter_oauth_token.present? && user.respond_to?(:twitter_screen_name) && user.twitter_screen_name.present?) ? { username: user.twitter_screen_name, user_id: user.twitter_user_id } : nil,
      linkedin_account: (user.linkedin_access_token.present? && user.respond_to?(:linkedin_profile_id) && user.linkedin_profile_id.present?) ? { profile_id: user.linkedin_profile_id } : nil,
      google_account: (user.google_refresh_token.present? && user.respond_to?(:google_account_name) && user.google_account_name.present?) ? { name: user.google_account_name } : nil,
      tiktok_account: (user.tiktok_access_token.present? && user.respond_to?(:tiktok_username) && user.tiktok_username.present?) ? { username: user.tiktok_username, user_id: user.tiktok_user_id } : nil,
      youtube_account: (user.youtube_access_token.present? && user.respond_to?(:youtube_channel_id) && user.youtube_channel_id.present?) ? { 
        channel_id: user.youtube_channel_id,
        channel_name: (user.respond_to?(:youtube_channel_name) && user.youtube_channel_name.present?) ? user.youtube_channel_name : nil
      } : nil,
      pinterest_account: (user.respond_to?(:pinterest_access_token) && user.pinterest_access_token.present? && user.respond_to?(:pinterest_username) && user.pinterest_username.present?) ? { username: user.pinterest_username } : nil
    }
  end
  
  # Fetch YouTube channel name if missing (non-blocking)
  def fetch_youtube_channel_name_if_missing(user)
    return unless user.youtube_access_token.present?
    return if user.respond_to?(:youtube_channel_name) && user.youtube_channel_name.present?
    return unless user.respond_to?(:youtube_channel_name=) # Column must exist
    return if Rails.env.test? # Skip in tests to avoid API calls
    return unless user.youtube_access_token.present? # Need access token

    begin
      # Get channel information using YouTube Data API v3
      # Use the same URL pattern that matches test stubs
      youtube_info_url = "https://www.googleapis.com/youtube/v3/channels"
      youtube_info_response = HTTParty.get(youtube_info_url, {
        query: {
          part: 'snippet',
          mine: 'true'
        },
        headers: {
          'Authorization' => "Bearer #{user.youtube_access_token}"
        },
        timeout: 3
      })
      
      if youtube_info_response.success?
        youtube_info_data = JSON.parse(youtube_info_response.body)
        
        if youtube_info_data['items'] && youtube_info_data['items'].any?
          channel = youtube_info_data['items'].first
          channel_id = channel['id']
          channel_title = channel.dig('snippet', 'title')
          
          # Save channel ID if missing
          if channel_id && user.respond_to?(:youtube_channel_id=) && user.youtube_channel_id.blank?
            user.update!(youtube_channel_id: channel_id)
          end
          
          # Save channel name
          if channel_title
            user.update!(youtube_channel_name: channel_title)
            Rails.logger.info "YouTube channel name fetched and saved: #{channel_title}"
          end
        end
      end
    rescue => e
      Rails.logger.warn "Failed to fetch YouTube channel name (non-blocking): #{e.message}"
      # Don't fail the request if this fails
    end
  end
end
