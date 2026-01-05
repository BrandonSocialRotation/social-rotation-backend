class Api::V1::OauthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:facebook_callback, :twitter_callback, :linkedin_callback, :google_callback, :tiktok_callback, :youtube_callback, :pinterest_callback, :twitter_login, :instagram_callback]
  skip_before_action :require_active_subscription!, only: [:facebook_callback, :twitter_callback, :linkedin_callback, :google_callback, :tiktok_callback, :youtube_callback, :pinterest_callback, :twitter_login, :instagram_callback]
  
  def frontend_url
    (Rails.env.development? ? "http://localhost:3001" : (ENV['FRONTEND_URL'] || 'https://my.socialrotation.app')).chomp('/')
  end
  
  def oauth_callback_url(success: nil, error: nil, platform:)
    params = []
    params << "success=#{CGI.escape(success)}" if success
    params << "error=#{CGI.escape(error)}" if error
    params << "platform=#{CGI.escape(platform)}"
    "#{frontend_url}/oauth/callback?#{params.join('&')}"
  end
  
  def facebook_login
    handle_oauth_login(:facebook, 'Facebook')
  end
  
  def facebook_callback
    handle_oauth_callback(:facebook, 'Facebook') do |user, data|
      user.update!(fb_user_access_key: data['access_token'])
      fetch_facebook_user_info(user, data['access_token'])
      fetch_instagram_account(user)
    end
  end
  
  def linkedin_login
    handle_oauth_login(:linkedin, 'LinkedIn')
  end
  
  def linkedin_callback
    handle_oauth_callback(:linkedin, 'LinkedIn') do |user, data|
      user.update!(linkedin_access_token: data['access_token'], linkedin_access_token_time: Time.current)
      extract_linkedin_profile_id(user, data)
    end
  end
  
  def google_login
    handle_oauth_login(:google, 'Google My Business')
  end
  
  def google_callback
    handle_oauth_callback(:google, 'Google My Business') do |user, data|
      user.update!(google_refresh_token: data['refresh_token']) if data['refresh_token']
      fetch_google_user_info(user, data['access_token'])
    end
  end
  
  def tiktok_login
    handle_oauth_login(:tiktok, 'TikTok')
  end
  
  def tiktok_callback
    handle_oauth_callback(:tiktok, 'TikTok') do |user, data|
      user.update!(tiktok_access_token: data['access_token']) if user.respond_to?(:tiktok_access_token=)
    end
  end
  
  def youtube_login
    handle_oauth_login(:youtube, 'YouTube')
  end
  
  def youtube_callback
    handle_oauth_callback(:youtube, 'YouTube') do |user, data|
      if data['refresh_token']
        user.update!(youtube_refresh_token: data['refresh_token'], youtube_access_token: data['access_token'])
      else
        user.update!(youtube_access_token: data['access_token'])
      end
      fetch_youtube_channel_info(user, data['access_token'])
    end
  end
  
  def pinterest_login
    handle_oauth_login(:pinterest, 'Pinterest')
  end
  
  def pinterest_callback
    handle_oauth_callback(:pinterest, 'Pinterest') do |user, data|
      return unless user.respond_to?(:pinterest_access_token=)
      user.update!(pinterest_access_token: data['access_token'], pinterest_refresh_token: data['refresh_token'])
      fetch_pinterest_user_info(user, data['access_token'])
    end
  end
  
  def twitter_login
    # Skip authenticate_user! for this action to handle auth manually
    token = request.headers['Authorization']&.split(' ')&.last
    if token.blank?
      return render json: { error: 'Authentication required' }, status: :unauthorized
    end
    
    decoded = JsonWebToken.decode(token)
    if decoded
      @current_user = User.find_by(id: decoded[:user_id])
      unless @current_user
        return render json: { error: 'Authentication required' }, status: :unauthorized
      end
    else
      return render json: { error: 'Authentication required' }, status: :unauthorized
    end
    
    unless current_user
      return render json: { error: 'Authentication required' }, status: :unauthorized
    end
    require 'oauth'
    consumer_key = ENV['TWITTER_API_KEY']
    consumer_secret = ENV['TWITTER_API_SECRET_KEY']
    unless consumer_key.present? && consumer_secret.present?
      return render json: { error: 'Twitter API credentials not configured' }, status: :internal_server_error
    end
    # Twitter OAuth callback must go to backend, then redirect to frontend
    # Note: Twitter OAuth 1.0a requires callback URL to match EXACTLY what's registered in Twitter Developer Portal
    # The callback URL cannot have query parameters
    # So we store user_id in the OauthRequestToken record instead
    backend_callback_url = if ENV['TWITTER_CALLBACK'].present?
      ENV['TWITTER_CALLBACK']
    elsif Rails.env.development?
      'http://127.0.0.1:3000/api/v1/oauth/twitter/callback'  # Use 127.0.0.1 instead of localhost per Twitter recommendations
    else
      "#{request.base_url}/api/v1/oauth/twitter/callback"
    end
    
    Rails.logger.info "Twitter OAuth - Using callback URL: #{backend_callback_url}"
    Rails.logger.info "Twitter OAuth - Make sure this EXACT URL is registered in Twitter Developer Portal (Settings > App settings > Callback URLs)"
    
    consumer = ::OAuth::Consumer.new(consumer_key, consumer_secret, site: 'https://api.twitter.com', request_token_path: '/oauth/request_token', authorize_path: '/oauth/authorize', access_token_path: '/oauth/access_token')
    
    begin
      request_token = consumer.get_request_token(oauth_callback: backend_callback_url)
    rescue => e
      Rails.logger.error "Twitter OAuth request token error: #{e.class} - #{e.message}"
      Rails.logger.error "Callback URL used: #{backend_callback_url}"
      raise e
    end
    if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
      OauthRequestToken.create!(oauth_token: request_token.token, request_secret: request_token.secret, user_id: current_user.id, expires_at: 10.minutes.from_now)
    end
    session[:twitter_request_token] = request_token.token
    session[:twitter_request_secret] = request_token.secret
    session[:user_id] = current_user.id
    
    oauth_url = request_token.authorize_url
    
    # Always return JSON for API endpoints (frontend will handle redirect)
    # Check if it's a direct browser request (no Accept header or HTML request)
    if request.headers['Accept']&.include?('text/html') && !request.xhr? && !request.headers['Accept']&.include?('application/json')
      redirect_to oauth_url, allow_other_host: true
    else
      render json: { oauth_url: oauth_url, platform: 'X' }
    end
  rescue LoadError
    render json: { error: 'OAuth gem not installed' }, status: :internal_server_error
  rescue => e
    Rails.logger.error "Twitter OAuth error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
    
    error_message = if e.message.include?('403') || e.message.include?('Forbidden')
      callback_url = ENV['TWITTER_CALLBACK'] || (Rails.env.development? ? 'http://127.0.0.1:3000/api/v1/oauth/twitter/callback' : "#{request.base_url}/api/v1/oauth/twitter/callback")
      "Twitter rejected the request (403 Forbidden). This usually means the callback URL doesn't match what's registered in your Twitter app. " +
      "Please go to https://developer.twitter.com/en/portal/dashboard, select your app, go to 'Settings' > 'App settings' > 'Callback URLs', " +
      "and make sure this EXACT URL is listed: #{callback_url} (no trailing slash, no query parameters)"
    else
      e.message
    end
    render json: { error: 'Twitter authentication failed', message: error_message, details: e.message }, status: :bad_request
  end
  
  def twitter_callback
    consumer_key = ENV['TWITTER_API_KEY']
    consumer_secret = ENV['TWITTER_API_SECRET_KEY']
    unless consumer_key.present? && consumer_secret.present?
      return redirect_to oauth_callback_url(error: 'twitter_config_error', platform: 'X'), allow_other_host: true
    end
    
    # Get token record (don't delete yet - we need it for the access token exchange)
    token_record = nil
    if params[:oauth_token].present? && ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
      token_record = OauthRequestToken.find_by(oauth_token: params[:oauth_token])
      if token_record && token_record.expires_at < Time.current
        Rails.logger.warn "Twitter OAuth token expired: #{params[:oauth_token]}"
        token_record.destroy
        token_record = nil
      end
    end
    
    # Get user_id from token record or fallback to session
    user_id = token_record&.user_id || session[:user_id] || params[:user_id]
    
    unless user_id
      Rails.logger.error "Twitter callback - No user_id found. oauth_token: #{params[:oauth_token].present? ? 'present' : 'missing'}, session user_id: #{session[:user_id]}, token_record: #{token_record.present? ? 'found' : 'not found'}"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'X'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    unless user
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'X'), allow_other_host: true
    end
    
    # Get request token and secret from token record or session
    request_token_value = token_record ? token_record.oauth_token : session[:twitter_request_token]
    request_secret_value = token_record ? token_record.request_secret : session[:twitter_request_secret]
    
    unless request_token_value.present? && request_secret_value.present?
      Rails.logger.error "Twitter callback - Missing request token/secret. token_record: #{token_record.present? ? 'found' : 'not found'}, session token: #{session[:twitter_request_token].present? ? 'present' : 'missing'}"
      return redirect_to oauth_callback_url(error: 'twitter_session_expired', platform: 'X'), allow_other_host: true
    end
    
    consumer = ::OAuth::Consumer.new(consumer_key, consumer_secret, site: 'https://api.twitter.com', request_token_path: '/oauth/request_token', authorize_path: '/oauth/authorize', access_token_path: '/oauth/access_token')
    request_token = ::OAuth::RequestToken.new(consumer, request_token_value, request_secret_value)
    access_token = request_token.get_access_token(oauth_verifier: params[:oauth_verifier])
    
    # Update user with Twitter credentials
    user.update!(
      twitter_oauth_token: access_token.token,
      twitter_oauth_token_secret: access_token.secret,
      twitter_user_id: access_token.params['user_id'],
      twitter_screen_name: access_token.params['screen_name']
    )
    
    # Clean up: delete token record and session data
    token_record&.destroy
    session.delete(:twitter_request_token)
    session.delete(:twitter_request_secret)
    session.delete(:user_id)
    
    redirect_to oauth_callback_url(success: 'twitter_connected', platform: 'X'), allow_other_host: true
  rescue => e
    Rails.logger.error "Twitter callback error: #{e.message}"
    redirect_to oauth_callback_url(error: 'twitter_auth_failed', platform: 'X'), allow_other_host: true
  end
  
  def instagram_login
    handle_oauth_login(:instagram, 'Instagram')
  end
  
  def instagram_callback
    handle_oauth_callback(:instagram, 'Instagram') do |user, data|
      access_token = data['access_token']
      
      # Try to get Instagram account directly (Instagram Login API)
      instagram_account = fetch_instagram_account_direct(access_token)
      
      if instagram_account
        # Direct Instagram account found - store it
        user.update!(
          instagram_business_id: instagram_account[:id],
          fb_user_access_key: access_token # Store access token for API calls
        )
      else
        # Fallback: Try to find Instagram account through Facebook pages
        user.update!(fb_user_access_key: access_token)
        fetch_and_store_instagram_account(user, access_token)
      end
    end
  end
  
  def instagram_connect
    unless current_user.fb_user_access_key.present?
      return render json: { error: 'Facebook not connected', message: 'Please connect Facebook first' }, status: :bad_request
    end
    instagram_info = fetch_instagram_account(current_user)
    if current_user.instagram_business_id.present?
      render json: { success: true, message: 'Instagram connected successfully', instagram_business_id: current_user.instagram_business_id, instagram_account: instagram_info }
    else
      render json: { error: 'Instagram account not found', message: 'No Instagram Business account found' }, status: :not_found
    end
  rescue => e
    Rails.logger.error "Instagram connect error: #{e.message}"
    render json: { error: 'Failed to connect Instagram', message: e.message }, status: :internal_server_error
  end
  
  private
  
  def handle_oauth_login(platform, platform_name)
    unless current_user&.id
      return render json: { error: 'User not authenticated' }, status: :unauthorized
    end
    service = OauthService.new(platform, request.base_url)
    oauth_url = service.build_auth_url(current_user.id, session)
    unless oauth_url
      return render json: { error: "#{platform_name} not configured" }, status: :internal_server_error
    end
    
    # Always return JSON for API endpoints (frontend will handle redirect)
    # Check if it's a direct browser request (no Accept header or HTML request)
    if request.headers['Accept']&.include?('text/html') && !request.xhr? && !request.headers['Accept']&.include?('application/json')
      redirect_to oauth_url, allow_other_host: true
    else
      render json: { oauth_url: oauth_url, platform: platform_name }
    end
  rescue => e
    Rails.logger.error "#{platform_name} OAuth login error: #{e.message}"
    render json: { error: "Failed to initiate #{platform_name} OAuth", details: e.message }, status: :internal_server_error
  end
  
  def handle_oauth_callback(platform, platform_name)
    code = params[:code]
    state = params[:state]
    error_param = params[:error]
    
    if error_param.present?
      error_msg = case error_param
      when 'access_denied' then "#{platform}_access_denied"
      else "#{platform}_auth_failed"
      end
      return redirect_to oauth_callback_url(error: error_msg, platform: platform_name), allow_other_host: true
    end
    
    unless code.present?
      return redirect_to oauth_callback_url(error: "#{platform}_auth_failed", platform: platform_name), allow_other_host: true
    end
    
    service = OauthService.new(platform, request.base_url)
    user_id, stored_state = service.verify_state(state, session["#{platform}_state".to_sym] || session[:oauth_state])
    
    unless stored_state && user_id && user_id > 0
      return redirect_to oauth_callback_url(error: 'invalid_state', platform: platform_name), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    unless user
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: platform_name), allow_other_host: true
    end
    
    redirect_uri = service.send(:default_callback_url)
    response = service.exchange_code_for_token(code, redirect_uri)
    
    unless response&.success?
      return redirect_to oauth_callback_url(error: "#{platform}_auth_failed", platform: platform_name), allow_other_host: true
    end
    
    data = JSON.parse(response.body)
    
    unless data['access_token']
      return redirect_to oauth_callback_url(error: "#{platform}_auth_failed", platform: platform_name), allow_other_host: true
    end
    
    yield(user, data) if block_given?
    redirect_to oauth_callback_url(success: "#{platform}_connected", platform: platform_name), allow_other_host: true
  rescue => e
    Rails.logger.error "#{platform_name} OAuth error: #{e.message}"
    redirect_to oauth_callback_url(error: "#{platform}_auth_failed", platform: platform_name), allow_other_host: true
  end
  
  def fetch_facebook_user_info(user, access_token)
    response = HTTParty.get("https://graph.facebook.com/v18.0/me?fields=name,email&access_token=#{access_token}", timeout: 5)
    return unless response.success?
    data = JSON.parse(response.body)
    user.update!(facebook_name: data['name']) if data['name'] && user.respond_to?(:facebook_name=)
  rescue => e
    Rails.logger.warn "Failed to fetch Facebook user info: #{e.message}"
  end
  
  def extract_linkedin_profile_id(user, data)
    if data['id_token']
      token_parts = data['id_token'].split('.')
      if token_parts.length == 3
        require 'base64'
        payload = Base64.urlsafe_decode64(token_parts[1])
        id_data = JSON.parse(payload)
        profile_id = id_data['sub'].to_s.split(':').last if id_data['sub']
        user.update!(linkedin_profile_id: profile_id) if profile_id
      end
    end
    fetch_linkedin_profile_id(user, data['access_token']) unless user.linkedin_profile_id.present?
  rescue => e
    Rails.logger.warn "Failed to extract LinkedIn profile ID: #{e.message}"
  end
  
  def fetch_linkedin_profile_id(user, access_token)
    response = HTTParty.get('https://api.linkedin.com/v2/me', headers: { 'Authorization' => "Bearer #{access_token}", 'X-Restli-Protocol-Version' => '2.0.0' })
    if response.success?
      data = JSON.parse(response.body)
      user.update!(linkedin_profile_id: data['id']) if data['id']
      return data['id']
    end
    response = HTTParty.get('https://api.linkedin.com/v2/userinfo', headers: { 'Authorization' => "Bearer #{access_token}" })
    if response.success?
      data = JSON.parse(response.body)
      profile_id = data['sub'].to_s.split(':').last if data['sub']
      user.update!(linkedin_profile_id: profile_id) if profile_id
      return profile_id
    end
    nil
  rescue => e
    Rails.logger.warn "Failed to fetch LinkedIn profile ID: #{e.message}"
    nil
  end
  
  def fetch_google_user_info(user, access_token)
    response = HTTParty.get('https://www.googleapis.com/oauth2/v2/userinfo', headers: { 'Authorization' => "Bearer #{access_token}" }, timeout: 5)
    return unless response.success?
    data = JSON.parse(response.body)
    name = data['name'] || data['email']
    user.update!(google_account_name: name) if name && user.respond_to?(:google_account_name=)
  rescue => e
    Rails.logger.warn "Failed to fetch Google user info: #{e.message}"
  end
  
  def fetch_youtube_channel_info(user, access_token)
    response = HTTParty.get('https://www.googleapis.com/youtube/v3/channels', query: { part: 'snippet', mine: 'true' }, headers: { 'Authorization' => "Bearer #{access_token}" }, timeout: 5)
    return unless response.success?
    data = JSON.parse(response.body)
    return unless data['items']&.any?
    channel = data['items'].first
    user.update!(youtube_channel_id: channel['id']) if channel['id'] && user.respond_to?(:youtube_channel_id=)
    channel_title = channel.dig('snippet', 'title')
    user.update!(youtube_channel_name: channel_title) if channel_title && user.respond_to?(:youtube_channel_name=)
    user.update!(youtube_account_name: channel_title) if channel_title && user.respond_to?(:youtube_account_name=)
  rescue => e
    Rails.logger.warn "Failed to fetch YouTube channel info: #{e.message}"
  end
  
  def fetch_pinterest_user_info(user, access_token)
    return unless user.respond_to?(:pinterest_access_token=) # Only fetch if user model supports Pinterest
    return if Rails.env.test? # Skip in tests to avoid API calls
    
    response = HTTParty.get('https://api.pinterest.com/v5/user_account', headers: { 'Authorization' => "Bearer #{access_token}" }, timeout: 5)
    return unless response.success?
    data = JSON.parse(response.body)
    username = data['username'] || data.dig('profile', 'username')
    user.update!(pinterest_username: username) if username && user.respond_to?(:pinterest_username=)
  rescue => e
    Rails.logger.warn "Failed to fetch Pinterest user info: #{e.message}"
  end
  
  # Try to get Instagram account directly using Instagram Login API
  def fetch_instagram_account_direct(access_token)
    # First, try to get user's Instagram accounts directly
    # This works if the Instagram account is connected to the Facebook App
    response = HTTParty.get('https://graph.facebook.com/v18.0/me/accounts', query: { 
      access_token: access_token, 
      fields: 'instagram_business_account{id,username}',
      limit: 1000 
    })
    
    data = JSON.parse(response.body)
    
    # Check if we got Instagram accounts directly
    if data['data']&.any?
      data['data'].each do |page|
        if page['instagram_business_account']
          instagram_account = page['instagram_business_account']
          return {
            id: instagram_account['id'],
            username: instagram_account['username']
          }
        end
      end
    end
    
    # Alternative: Try to get Instagram account from user's profile
    # Some Instagram accounts can be accessed directly
    response = HTTParty.get('https://graph.facebook.com/v18.0/me', query: {
      access_token: access_token,
      fields: 'instagram_business_account{id,username}'
    })
    
    data = JSON.parse(response.body)
    if data['instagram_business_account']
      instagram_account = data['instagram_business_account']
      return {
        id: instagram_account['id'],
        username: instagram_account['username']
      }
    end
    
    nil
  rescue => e
    Rails.logger.warn "Failed to fetch Instagram account directly: #{e.message}"
    nil
  end
  
  def fetch_and_store_instagram_account(user, access_token)
    return nil unless access_token.present?
    
    # Fetch user's Facebook pages with Instagram accounts
    response = HTTParty.get('https://graph.facebook.com/v18.0/me/accounts', query: { 
      access_token: access_token, 
      fields: 'id,name,access_token,instagram_business_account{id,username}', 
      limit: 1000 
    })
    
    data = JSON.parse(response.body)
    return nil unless data['data']&.any?
    
    # Find first page with Instagram Business account
    data['data'].each do |page|
      if page['instagram_business_account']
        instagram_account = page['instagram_business_account']
        instagram_id = instagram_account['id']
        page_token = page['access_token']
        
        # Store Instagram Business ID and page access token
        user.update!(
          instagram_business_id: instagram_id,
          fb_user_access_key: page_token # Use page token for Instagram API
        )
        
        return { 
          id: instagram_id, 
          username: instagram_account['username'],
          page_id: page['id'], 
          page_name: page['name'] 
        }
      end
    end
    
    nil
  rescue => e
    Rails.logger.error "Failed to fetch and store Instagram account: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
  
  def fetch_instagram_account(user)
    return nil unless user.fb_user_access_key.present?
    response = HTTParty.get('https://graph.facebook.com/v18.0/me/accounts', query: { access_token: user.fb_user_access_key, fields: 'id,name,access_token,instagram_business_account', limit: 1000 })
    data = JSON.parse(response.body)
    return nil unless data['data']&.any?
    data['data'].each do |page|
      if page['instagram_business_account']
        instagram_id = page['instagram_business_account']['id']
        user.update!(instagram_business_id: instagram_id)
        return { id: instagram_id, page_id: page['id'], page_name: page['name'] }
      end
    end
    nil
  rescue => e
    Rails.logger.warn "Failed to fetch Instagram account: #{e.message}"
    # Re-raise the error so it can be caught by the calling method's rescue block
    raise e
  end
end
