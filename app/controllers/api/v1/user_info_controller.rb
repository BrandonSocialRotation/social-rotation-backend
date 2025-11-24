class Api::V1::UserInfoController < ApplicationController
  before_action :authenticate_user!

  # GET /api/v1/user_info
  def show
    render json: {
      user: user_json(current_user),
      connected_accounts: get_connected_accounts
    }
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

  # POST /api/v1/user_info/disconnect_facebook
  def disconnect_facebook
    current_user.update!(
      fb_user_access_key: nil,
      instagram_business_id: nil
    )
    
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

  # POST /api/v1/user_info/disconnect_google
  def disconnect_google
    current_user.update!(
      google_refresh_token: nil,
      location_id: nil
    )
    
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
    current_user.update!(
      youtube_access_token: nil,
      youtube_refresh_token: nil,
      youtube_channel_id: nil
    )
    
    render json: { message: 'YouTube disconnected successfully' }
  end

  # POST /api/v1/user_info/toggle_instagram
  def toggle_instagram
    current_user.update!(post_to_instagram: params[:post_to_instagram] == 'true')
    
    render json: {
      message: 'Instagram posting status updated',
      post_to_instagram: current_user.post_to_instagram
    }
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
      tiktok_connected: user.tiktok_access_token.present?,
      youtube_connected: user.youtube_access_token.present?
    }
  end
end





