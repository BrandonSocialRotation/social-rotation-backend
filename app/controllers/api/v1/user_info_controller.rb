class Api::V1::UserInfoController < ApplicationController
  before_action :authenticate_user!
  
  # Deployment verification: Methods should exist at lines 628 and 689

  # GET /api/v1/user_info
  def show
    begin
      # Fetch YouTube channel name if missing (non-blocking)
      fetch_youtube_channel_name_if_missing(current_user)
      
      render json: {
        user: user_json(current_user),
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
    if params[:watermark_logo].present?
      # Handle watermark logo upload
      # This would integrate with your file storage system
      current_user.update!(watermark_logo: "watermark_#{SecureRandom.uuid}.png")
    end

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
  end

  # GET /api/v1/user_info/connected_accounts
  def connected_accounts
    render json: {
      connected_accounts: get_connected_accounts
    }
  end

  # GET /api/v1/user_info/test_pages_endpoint
  # Test endpoint to verify deployment
  def test_pages_endpoint
    render json: { 
      message: 'Pages endpoints are deployed!',
      timestamp: Time.current.iso8601,
      has_facebook_pages_method: respond_to?(:facebook_pages, true),
      has_linkedin_organizations_method: respond_to?(:linkedin_organizations, true)
    }
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

  # DELETE /api/v1/user_info/delete_account
  # Delete the current user's account
  # Cancels Stripe subscription, deletes account and all associated data
  def delete_account
    user = current_user
    account = user.account
    user_email = user.email # Store email before deletion for logging
    
    # Store user ID and account info before deletion for logging
    user_id = user.id
    account_id = account&.id
    is_admin = user.is_account_admin
    stripe_customer_id = account&.subscription&.stripe_customer_id
    stripe_subscription_id = account&.subscription&.stripe_subscription_id
    
    begin
      # Cancel and delete Stripe subscription and customer if they exist (do this BEFORE database deletion)
      if stripe_subscription_id.present? || stripe_customer_id.present?
        Stripe.api_key = ENV['STRIPE_SECRET_KEY']
        
        # Cancel subscription if it exists
        if stripe_subscription_id.present?
          begin
            stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)
            
            # Only try to cancel if it's not already canceled or incomplete_expired
            unless stripe_subscription.status == 'canceled' || stripe_subscription.status == 'incomplete_expired'
              stripe_subscription.cancel
              Rails.logger.info "Stripe subscription #{stripe_subscription_id} canceled for user #{user_email}"
            else
              Rails.logger.info "Stripe subscription #{stripe_subscription_id} already canceled for user #{user_email}"
            end
          rescue Stripe::InvalidRequestError => e
            Rails.logger.warn "Stripe subscription not found or already deleted for user #{user_email}: #{e.message}"
          rescue Stripe::StripeError => e
            Rails.logger.error "Failed to cancel Stripe subscription for user #{user_email}: #{e.message}"
          end
        end
        
        # Delete Stripe customer if it exists (this also deletes all subscriptions)
        if stripe_customer_id.present?
          begin
            Stripe::Customer.delete(stripe_customer_id)
            Rails.logger.info "Stripe customer #{stripe_customer_id} deleted for user #{user_email}"
          rescue Stripe::InvalidRequestError => e
            Rails.logger.warn "Stripe customer not found or already deleted for user #{user_email}: #{e.message}"
          rescue Stripe::StripeError => e
            Rails.logger.error "Failed to delete Stripe customer for user #{user_email}: #{e.message}"
          end
        end
      end
      
      # Use a transaction to ensure all database deletions happen atomically
      ActiveRecord::Base.transaction do
        # Delete subscription record from database if it exists
        if account&.subscription
          Rails.logger.info "Deleting subscription record for account #{account_id}"
          account.subscription.destroy
        end
      
      # Delete account if user is account admin (this will cascade delete all users in the account)
      if account && is_admin
        Rails.logger.info "Deleting account #{account_id} and all associated users for admin user #{user_email}"
        
        # Delete all users in the account first (to avoid foreign key issues)
        account.users.each do |acc_user|
          Rails.logger.info "Deleting user #{acc_user.id} (#{acc_user.email}) from account #{account_id}"
          acc_user.destroy!
        end
        
        # Then delete the account
        account.destroy!
        message = "Account and user deleted successfully"
      else
        # For personal accounts or sub-accounts
        Rails.logger.info "Deleting user #{user_id} (#{user_email})"
        
        # Delete the account if it exists and has no other users
        if account
          user_count = account.users.count
          Rails.logger.info "Account #{account_id} has #{user_count} user(s)"
          
          if user_count <= 1
            Rails.logger.info "Deleting account #{account_id} as it has no remaining users"
            # Delete the user first (which will be the only user)
            user.destroy!
            # Then delete account (user is already deleted, so this should work)
            account.destroy!
          else
            # Account has other users, just delete this user
            Rails.logger.info "Account #{account_id} has other users, only deleting user #{user_id}"
            user.destroy!
          end
        else
          # No account, just delete the user
          user.destroy!
        end
        
        message = "User account deleted successfully"
      end
      
      # Verify deletion by checking if user still exists
      if User.exists?(user_id)
        Rails.logger.error "User #{user_id} still exists after deletion attempt!"
        raise "Failed to delete user - user still exists in database"
      end
      
        Rails.logger.info "Verified: User #{user_id} (#{user_email}) has been completely deleted from database"
      end # end transaction
      
      Rails.logger.info "Successfully deleted user #{user_id} (#{user_email}) and all associated data"
      render json: { message: message }
    rescue ActiveRecord::RecordNotDestroyed => e
      Rails.logger.error "Failed to delete user #{user_id} (#{user_email}): #{e.message}"
      Rails.logger.error e.record.errors.full_messages.join(', ')
      render json: { error: "Failed to delete account: #{e.message}" }, status: :internal_server_error
    rescue => e
      Rails.logger.error "Error deleting account for user #{user_email}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Failed to delete account: #{e.message}" }, status: :internal_server_error
    end
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
    # Only allow conversion if user is account admin or has account_id = 0 (personal)
    unless current_user.account_id == 0 || current_user.is_account_admin?
      return render json: { error: 'Only account admins can convert accounts' }, status: :forbidden
    end

    # If user has account_id = 0, create a new agency account
    if current_user.account_id == 0
      account = Account.create!(
        name: params[:company_name] || "#{current_user.name}'s Agency",
        is_reseller: true,
        status: true
      )
      
      # Update user to be part of the new account and make them admin
      current_user.update!(
        account_id: account.id,
        is_account_admin: true,
        role: 'reseller'
      )
      
      render json: {
        user: user_json(current_user),
        message: 'Account successfully converted to agency account'
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
      # Social media connection status
      facebook_connected: user.fb_user_access_key.present?,
      twitter_connected: user.twitter_oauth_token.present?,
      linkedin_connected: user.linkedin_access_token.present?,
      google_connected: user.google_refresh_token.present?,
      instagram_connected: user.instagram_business_id.present?,
      instagram_business_id: user.instagram_business_id,
      instagram_account: user.instagram_business_id.present? ? get_instagram_account_info(user) : nil,
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
    
    begin
      # Get channel information using YouTube Data API v3
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
  
  # GET /api/v1/user_info/facebook_pages
  # Returns list of Facebook pages user has access to
  def facebook_pages
    begin
      unless current_user.fb_user_access_key.present?
        render json: { error: 'Facebook not connected' }, status: :bad_request
        return
      end
      
      service = SocialMedia::FacebookService.new(current_user)
      pages = service.fetch_pages
      
      if pages.empty?
        Rails.logger.warn "No Facebook pages found for user #{current_user.id}. This could mean: 1) User has no pages, 2) Missing pages_manage_posts permission, 3) Token expired."
      end
      
      render json: { pages: pages }
    rescue => e
      Rails.logger.error "Error fetching Facebook pages: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Provide more helpful error messages
      error_message = e.message
      status = :internal_server_error
      
      # Check for specific error types
      if error_message.include?('permission') || error_message.include?('scope') || error_message.include?('OAuthException')
        status = :forbidden
        error_message = "Facebook permission error. Please disconnect and reconnect your Facebook account to grant the 'pages_manage_posts' permission."
      elsif error_message.include?('expired') || error_message.include?('invalid')
        status = :unauthorized
        error_message = "Facebook access token expired or invalid. Please reconnect your Facebook account."
      end
      
      render json: { 
        error: "Failed to fetch Facebook pages: #{error_message}",
        suggestion: error_message.include?('permission') || error_message.include?('expired') || error_message.include?('invalid') ? 
          "Please go to your profile page and reconnect Facebook." : nil
      }, status: status
    end
  end
  
  # GET /api/v1/user_info/deployment_test
  # Simple endpoint to verify deployment is working
  def deployment_test
    # Check if methods actually exist
    has_facebook = respond_to?(:facebook_pages, true)
    has_linkedin = respond_to?(:linkedin_organizations, true)
    
    render json: { 
      message: 'Deployment test - commit 44c1c6c',
      timestamp: Time.current.iso8601,
      methods_available: ['facebook_pages', 'linkedin_organizations'],
      methods_exist: {
        facebook_pages: has_facebook,
        linkedin_organizations: has_linkedin
      },
      controller_methods: self.class.instance_methods(false).sort
    }
  end

  # GET /api/v1/user_info/linkedin_organizations
  # Returns list of LinkedIn organizations user manages
  def linkedin_organizations
    begin
      unless current_user.linkedin_access_token.present?
        render json: { error: 'LinkedIn not connected' }, status: :bad_request
        return
      end
      
      service = SocialMedia::LinkedinService.new(current_user)
      organizations = service.fetch_organizations
      
      # Also include personal profile as an option
      begin
        personal_urn = service.get_personal_profile_urn
        organizations.unshift({
          id: current_user.linkedin_profile_id,
          name: 'Personal Profile',
          urn: personal_urn
        })
      rescue => e
        Rails.logger.warn "Could not get personal profile URN: #{e.message}"
      end
      
      render json: { organizations: organizations }
    rescue => e
      Rails.logger.error "Error fetching LinkedIn organizations: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Failed to fetch LinkedIn organizations: #{e.message}" }, status: :internal_server_error
    end
  end
end





# Force rebuild 1765834704
