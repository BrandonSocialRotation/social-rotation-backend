class OauthService
  PLATFORMS = {
    facebook: {
      env_client_id: 'FACEBOOK_APP_ID',
      env_client_secret: 'FACEBOOK_APP_SECRET',
      env_callback: nil,
      auth_url: 'https://www.facebook.com/v18.0/dialog/oauth',
      token_url: 'https://graph.facebook.com/v18.0/oauth/access_token',
      scopes: 'email,pages_manage_posts,pages_read_engagement,instagram_basic,instagram_content_publish,publish_video',
      callback_path: '/api/v1/oauth/facebook/callback'
    },
    linkedin: {
      env_client_id: 'LINKEDIN_CLIENT_ID',
      env_client_secret: 'LINKEDIN_CLIENT_SECRET',
      env_callback: 'LINKEDIN_CALLBACK',
      auth_url: 'https://www.linkedin.com/oauth/v2/authorization',
      token_url: 'https://www.linkedin.com/oauth/v2/accessToken',
      scopes: 'w_member_social openid profile email',
      callback_path: '/api/v1/oauth/linkedin/callback'
    },
    google: {
      env_client_id: 'GOOGLE_CLIENT_ID',
      env_client_secret: 'GOOGLE_CLIENT_SECRET',
      env_callback: 'GOOGLE_CALLBACK',
      auth_url: 'https://accounts.google.com/o/oauth2/v2/auth',
      token_url: 'https://oauth2.googleapis.com/token',
      scopes: 'https://www.googleapis.com/auth/business.manage https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email',
      callback_path: '/api/v1/oauth/google/callback'
    },
    tiktok: {
      env_client_id: 'TIKTOK_CLIENT_KEY',
      env_client_secret: nil,
      env_callback: 'TIKTOK_CALLBACK',
      auth_url: 'https://www.tiktok.com/v2/auth/authorize',
      token_url: 'https://open.tiktokapis.com/v2/oauth/token/',
      scopes: 'user.info.basic,video.publish',
      callback_path: '/api/v1/oauth/tiktok/callback'
    },
    youtube: {
      env_client_id: 'YOUTUBE_CLIENT_ID',
      env_client_secret: 'YOUTUBE_CLIENT_SECRET',
      env_callback: 'YOUTUBE_CALLBACK',
      auth_url: 'https://accounts.google.com/o/oauth2/v2/auth',
      token_url: 'https://oauth2.googleapis.com/token',
      scopes: 'https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email',
      callback_path: '/api/v1/oauth/youtube/callback'
    },
    pinterest: {
      env_client_id: 'PINTEREST_CLIENT_ID',
      env_client_secret: 'PINTEREST_CLIENT_SECRET',
      env_callback: 'PINTEREST_CALLBACK',
      auth_url: 'https://www.pinterest.com/oauth/',
      token_url: 'https://api.pinterest.com/v5/oauth/token',
      scopes: 'boards:read,pins:read,pins:write',
      callback_path: '/api/v1/oauth/pinterest/callback'
    },
    instagram: {
      env_client_id: 'FACEBOOK_APP_ID', # Instagram Login uses Facebook App credentials
      env_client_secret: 'FACEBOOK_APP_SECRET',
      env_callback: nil,
      # Instagram Login API - allows direct Instagram connection without Facebook Page
      auth_url: 'https://www.facebook.com/v18.0/dialog/oauth',
      token_url: 'https://graph.facebook.com/v18.0/oauth/access_token',
      # Instagram Login scopes - allows direct Instagram account access
      scopes: 'instagram_basic,instagram_content_publish,instagram_manage_messages,pages_show_list',
      callback_path: '/api/v1/oauth/instagram/callback'
    }
  }.freeze

  def initialize(platform, request_base_url = nil)
    @platform = platform.to_sym
    @config = PLATFORMS[@platform]
    @request_base_url = request_base_url
    raise "Unknown platform: #{platform}" unless @config
  end

  def generate_state(user_id)
    random_state = SecureRandom.hex(16)
    state = "#{user_id}:#{random_state}"
    store_state(random_state, state, user_id)
    state
  end

  def store_state(token, secret, user_id)
    if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
      OauthRequestToken.create!(
        oauth_token: token,
        request_secret: secret,
        user_id: user_id,
        expires_at: 10.minutes.from_now
      )
    end
  rescue => e
    Rails.logger.error "#{@platform.capitalize} OAuth - failed to store state: #{e.message}"
  end

  def decode_state(state_param)
    return [nil, nil] unless state_param.present?
    return [nil, state_param] unless state_param.include?(':')
    parts = state_param.split(':', 2)
    [parts[0].to_i, parts[1]]
  end

  def verify_state(state_param, session_state = nil)
    user_id, random_state = decode_state(state_param)
    stored_state = nil
    
    if random_state && ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
      token_data = OauthRequestToken.find_and_delete(random_state)
      stored_state = token_data[:secret] if token_data
      user_id ||= token_data[:user_id] if token_data
    end
    
    stored_state ||= session_state
    return [nil, nil] unless stored_state
    
    # Compare full state_param with stored_state (which is the full state string)
    # stored_state is the full "user_id:random_state" string stored as request_secret
    return [nil, nil] unless state_param == stored_state
    
    [user_id, stored_state]
  end

  def build_auth_url(user_id, session = {})
    client_id = ENV[@config[:env_client_id]]
    return nil unless client_id
    
    state = generate_state(user_id)
    session["#{@platform}_state".to_sym] = state.split(':').last
    session[:oauth_state] = state.split(':').last
    session[:user_id] = user_id
    
    redirect_uri = @config[:env_callback] ? (ENV[@config[:env_callback]] || default_callback_url) : default_callback_url
    
    case @platform
    when :facebook, :instagram
      "#{@config[:auth_url]}?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&state=#{state}&scope=#{@config[:scopes]}"
    when :linkedin
      "#{@config[:auth_url]}?response_type=code&client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&state=#{CGI.escape(state)}&scope=#{CGI.escape(@config[:scopes])}"
    when :google, :youtube
      "#{@config[:auth_url]}?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&response_type=code&scope=#{CGI.escape(@config[:scopes])}&access_type=offline&prompt=consent&state=#{CGI.escape(state)}"
    when :tiktok
      "#{@config[:auth_url]}?client_key=#{client_id}&scope=#{@config[:scopes]}&response_type=code&redirect_uri=#{CGI.escape(redirect_uri)}&state=#{state}"
    when :pinterest
      "#{@config[:auth_url]}?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&response_type=code&scope=#{CGI.escape(@config[:scopes])}&state=#{CGI.escape(state)}"
    end
  end

  def exchange_code_for_token(code, redirect_uri = nil)
    redirect_uri ||= default_callback_url
    client_id = ENV[@config[:env_client_id]]
    client_secret = @config[:env_client_secret] ? ENV[@config[:env_client_secret]] : nil
    
    return nil unless client_id && (@platform == :tiktok || client_secret)
    
    case @platform
    when :facebook, :instagram
      HTTParty.get("#{@config[:token_url]}?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&client_secret=#{client_secret}&code=#{code}")
    when :linkedin
      HTTParty.post(@config[:token_url], {
        body: { grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri, client_id: client_id, client_secret: client_secret },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
      })
    when :google, :youtube
      HTTParty.post(@config[:token_url], {
        body: { code: code, client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri, grant_type: 'authorization_code' }
      })
    when :tiktok
      HTTParty.post(@config[:token_url], {
        body: { client_key: client_id, client_secret: ENV['TIKTOK_CLIENT_SECRET'], code: code, grant_type: 'authorization_code', redirect_uri: redirect_uri },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
      })
    when :pinterest
      HTTParty.post(@config[:token_url], {
        body: { grant_type: 'authorization_code', client_id: client_id, client_secret: client_secret, code: code, redirect_uri: redirect_uri },
        headers: { 'Authorization' => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}", 'Content-Type' => 'application/x-www-form-urlencoded' }
      })
    end
  end

  def default_callback_url
    if Rails.env.development?
      "http://localhost:3000#{@config[:callback_path]}"
    else
      "#{@request_base_url}#{@config[:callback_path]}"
    end
  end
end
