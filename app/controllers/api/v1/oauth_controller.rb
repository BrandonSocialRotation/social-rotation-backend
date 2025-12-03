class Api::V1::OauthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:facebook_callback, :twitter_callback, :linkedin_callback, :google_callback, :tiktok_callback, :youtube_callback, :pinterest_callback]
  
  # Helper method to get the correct frontend URL for redirects
  def frontend_url
    url = if Rails.env.development?
      "http://localhost:3001"  # Use the port your frontend is running on
    else
      ENV['FRONTEND_URL'] || 'https://my.socialrotation.app'
    end
    # Remove trailing slash to avoid double slashes
    url.chomp('/')
  end
  
  # Helper method to build OAuth callback URL with platform info
  def oauth_callback_url(success: nil, error: nil, platform:)
    params = []
    params << "success=#{CGI.escape(success)}" if success
    params << "error=#{CGI.escape(error)}" if error
    params << "platform=#{CGI.escape(platform)}"
    # Ensure no double slashes by removing trailing slash from frontend_url and adding single slash
    base_url = frontend_url.chomp('/')
    callback_url = "#{base_url}/oauth/callback?#{params.join('&')}"
    Rails.logger.info "OAuth callback URL: #{callback_url}"
    callback_url
  end
  
  # GET /api/v1/oauth/facebook/login
  # Initiates Facebook OAuth flow
  def facebook_login
    begin
      # Generate state token for CSRF protection
      # Encode user_id in state to persist across popup (sessions don't work in popups)
      random_state = SecureRandom.hex(16)
      user_id = current_user.id
      state = "#{user_id}:#{random_state}"
      
      # Store state in database (sessions don't persist in popups)
      begin
        if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
          OauthRequestToken.create!(
            oauth_token: random_state, # Use random_state as the token key
            request_secret: state, # Store full state as secret
            user_id: user_id,
            expires_at: 10.minutes.from_now
          )
          Rails.logger.info "Facebook OAuth - stored state in database"
        end
      rescue => e
        Rails.logger.error "Facebook OAuth - failed to store state in database: #{e.message}, falling back to session"
      end
      
      # Also store in session as fallback
      session[:oauth_state] = random_state
      session[:user_id] = user_id
      
      # Facebook OAuth URL
      app_id = ENV['FACEBOOK_APP_ID']
      unless app_id
        return render json: { error: 'Facebook App ID not configured' }, status: :internal_server_error
      end
      redirect_uri = "#{request.base_url}/api/v1/oauth/facebook/callback"
      
      permissions = [
        'email',
        'pages_manage_posts',
        'pages_read_engagement',
        'instagram_basic',
        'instagram_content_publish',
        'publish_video'
      ].join(',')
      
      oauth_url = "https://www.facebook.com/v18.0/dialog/oauth?" \
                  "client_id=#{app_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&state=#{state}" \
                  "&scope=#{permissions}"
      
      Rails.logger.info "Facebook OAuth - generated URL with state: #{state[0..20]}..., user_id: #{user_id}"
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "Facebook OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate Facebook OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/facebook/callback
  # Handles Facebook OAuth callback
  def facebook_callback
    code = params[:code]
    state = params[:state]
    
    Rails.logger.info "Facebook callback - code: #{code.present? ? 'present' : 'missing'}, state: #{state.present? ? 'present' : 'missing'}"
    
    # Decode user_id from state (format: "user_id:random_state")
    user_id = nil
    expected_state = nil
    
    if state.present?
      parts = state.split(':')
      if parts.length == 2
        user_id = parts[0].to_i
        random_state = parts[1]
        expected_state = random_state
        
        # Try to verify state from database
        begin
          if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
            token_data = OauthRequestToken.find_and_delete(random_state)
            if token_data && token_data[:user_id] == user_id
              Rails.logger.info "Facebook callback - verified state from database"
              # State verified from database
            else
              Rails.logger.warn "Facebook callback - state not found in database, using decoded user_id"
            end
          end
        rescue => e
          Rails.logger.error "Facebook callback - error checking database: #{e.message}"
        end
      end
    end
    
    # Fallback to session if state decoding failed
    unless user_id && user_id > 0
      user_id = session[:user_id]
      expected_state = session[:oauth_state]
      Rails.logger.info "Facebook callback - using user_id and state from session"
    end
    
    # Verify state matches (either from database or session)
    if expected_state && state.present?
      state_parts = state.split(':')
      if state_parts.length == 2
        # State includes user_id, so we already decoded it above
        # Just verify the random part matches
        if state_parts[1] != expected_state
          Rails.logger.error "Facebook callback - state mismatch: expected #{expected_state[0..10]}..., got #{state_parts[1][0..10]}..."
          return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'Facebook'), allow_other_host: true
        end
      elsif state != expected_state
        Rails.logger.error "Facebook callback - state mismatch (session): expected #{expected_state}, got #{state}"
        return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'Facebook'), allow_other_host: true
      end
    end
    
    unless user_id && user_id > 0
      Rails.logger.error "Facebook callback - no user_id found"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'Facebook'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      Rails.logger.error "Facebook callback - user not found with id: #{user_id}"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'Facebook'), allow_other_host: true
    end
    
    Rails.logger.info "Facebook callback - found user: #{user.id} (#{user.email})"
    
    # Exchange code for access token
    app_id = ENV['FACEBOOK_APP_ID']
    app_secret = ENV['FACEBOOK_APP_SECRET']
    redirect_uri = "#{request.base_url}/api/v1/oauth/facebook/callback"
    
    token_url = "https://graph.facebook.com/v18.0/oauth/access_token?" \
                "client_id=#{app_id}" \
                "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                "&client_secret=#{app_secret}" \
                "&code=#{code}"
    
    begin
      response = HTTParty.get(token_url)
      data = JSON.parse(response.body)
      
      if data['access_token']
        # Store the access token
        user.update!(fb_user_access_key: data['access_token'])
        
        # Fetch Facebook user info (name/email)
        begin
          fb_info_url = "https://graph.facebook.com/v18.0/me?fields=name,email&access_token=#{data['access_token']}"
          fb_info_response = HTTParty.get(fb_info_url)
          fb_info_data = JSON.parse(fb_info_response.body)
          
          if fb_info_data['name'] && user.respond_to?(:facebook_name=)
            user.update!(facebook_name: fb_info_data['name'])
          end
        rescue => e
          Rails.logger.warn "Failed to fetch Facebook user info: #{e.message}"
        end
        
        # Try to fetch Instagram Business account ID
        fetch_instagram_account(user)
        
        # Redirect back to frontend OAuth callback
        redirect_to oauth_callback_url(success: 'facebook_connected', platform: 'Facebook'), allow_other_host: true
      else
        redirect_to oauth_callback_url(error: 'facebook_auth_failed', platform: 'Facebook'), allow_other_host: true
      end
    rescue => e
      Rails.logger.error "Facebook OAuth error: #{e.message}"
      redirect_to oauth_callback_url(error: 'facebook_auth_failed', platform: 'Facebook'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/twitter/login
  # Initiates Twitter OAuth 1.0a flow
  def twitter_login
    begin
      # Check if user is authenticated
      unless current_user
        Rails.logger.error "Twitter OAuth - user not authenticated"
        return render json: { error: 'Authentication required' }, status: :unauthorized
      end
      
      # Check if OAuth gem is available
      require 'oauth'
      require 'oauth/consumer'
    rescue LoadError => e
      Rails.logger.error "OAuth gem not available: #{e.message}"
      return render json: { error: 'OAuth gem not installed. Please add gem "oauth" to Gemfile and run bundle install.' }, status: :internal_server_error
    rescue => e
      Rails.logger.error "Twitter OAuth - unexpected error in setup: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      return render json: { error: 'Failed to initialize Twitter OAuth', message: e.message }, status: :internal_server_error
    end
    
    consumer_key = ENV['TWITTER_API_KEY']
    consumer_secret = ENV['TWITTER_API_SECRET_KEY']
    
    unless consumer_key.present? && consumer_secret.present?
      Rails.logger.error "Twitter credentials missing - API_KEY: #{consumer_key.present? ? 'present' : 'missing'}, SECRET: #{consumer_secret.present? ? 'present' : 'missing'}"
      return render json: { error: 'Twitter API credentials not configured. Please set TWITTER_API_KEY and TWITTER_API_SECRET_KEY environment variables.' }, status: :internal_server_error
    end
    
    base_callback_url = ENV['TWITTER_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/twitter/callback' : "#{request.base_url}/api/v1/oauth/twitter/callback")
    
    # Encode user_id in callback URL to persist across popup (sessions don't work in popups)
    user_id = current_user.id
    callback_url = "#{base_callback_url}?user_id=#{user_id}"
    
    Rails.logger.info "Twitter OAuth login - consumer_key: #{consumer_key[0..10]}..., callback_url: #{callback_url}, user_id: #{user_id}"
    
    begin
      # Create OAuth consumer
      consumer = ::OAuth::Consumer.new(
        consumer_key,
        consumer_secret,
        site: 'https://api.twitter.com',
        request_token_path: '/oauth/request_token',
        authorize_path: '/oauth/authorize',
        access_token_path: '/oauth/access_token'
      )
      
      # Get request token
      Rails.logger.info "Requesting Twitter request token with callback: #{callback_url}"
      begin
        request_token = consumer.get_request_token(oauth_callback: callback_url)
      rescue OAuth::Unauthorized => e
        # Try to get more details from the exception
        error_details = {
          message: e.message,
          class: e.class.to_s
        }
        
        # Try to access the response if available
        if e.respond_to?(:response)
          error_details[:response_code] = e.response.code if e.response.respond_to?(:code)
          error_details[:response_body] = e.response.body if e.response.respond_to?(:body)
          error_details[:response_headers] = e.response.to_hash if e.response.respond_to?(:to_hash)
        end
        
        Rails.logger.error "Twitter OAuth detailed error: #{error_details.inspect}"
        raise e
      end
      
      # Store request token in database (cache doesn't persist across processes in production)
      # Key by oauth_token so we can retrieve it in callback
      # Fall back to session if database table doesn't exist yet (migration not run)
      begin
        table_exists = false
        begin
          table_exists = ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
        rescue => table_check_error
          Rails.logger.warn "Twitter OAuth - could not check if table exists: #{table_check_error.message}"
        end
        
        if table_exists
          begin
            OauthRequestToken.create!(
              oauth_token: request_token.token,
              request_secret: request_token.secret,
              user_id: user_id,
              expires_at: 10.minutes.from_now
            )
            Rails.logger.info "Twitter OAuth - stored request token in database with oauth_token: #{request_token.token[0..10]}..."
          rescue ActiveRecord::StatementInvalid => db_error
            Rails.logger.error "Twitter OAuth - database error (table may not exist or migration not run): #{db_error.message}"
            Rails.logger.warn "Twitter OAuth - falling back to session storage"
          end
        else
          Rails.logger.warn "Twitter OAuth - oauth_request_tokens table not found, using session storage only"
        end
      rescue => e
        Rails.logger.error "Twitter OAuth - unexpected error storing in database: #{e.class} - #{e.message}, falling back to session"
        Rails.logger.error e.backtrace.join("\n")
      end
      
      # Always store in session as fallback
      session[:twitter_request_token] = request_token.token
      session[:twitter_request_secret] = request_token.secret
      session[:user_id] = user_id
      
      # Return authorize URL
      oauth_url = request_token.authorize_url
      Rails.logger.info "Twitter OAuth URL generated successfully: #{oauth_url[0..50]}..."
      render json: { oauth_url: oauth_url }
    rescue OAuth::Unauthorized => e
      error_body = ''
      if e.respond_to?(:response) && e.response.respond_to?(:body)
        error_body = e.response.body
      end
      
      Rails.logger.error "Twitter OAuth unauthorized error: #{e.message}"
      Rails.logger.error "Twitter OAuth response body: #{error_body}"
      Rails.logger.error "Twitter OAuth response code: #{e.response.code if e.respond_to?(:response) && e.response.respond_to?(:code)}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Parse Twitter error message if available
      twitter_error = error_body
      begin
        if error_body.present?
          parsed = JSON.parse(error_body) rescue nil
          twitter_error = parsed['errors'].first['message'] if parsed && parsed['errors'] && parsed['errors'].first
        end
      rescue => parse_error
        Rails.logger.warn "Could not parse Twitter error: #{parse_error.message}"
      end
      
      # Return 400 Bad Request instead of 401 to avoid frontend treating it as auth failure
      render json: { 
        error: 'Twitter authentication failed', 
        message: twitter_error.presence || 'Invalid API credentials or callback URL mismatch. Please check your Twitter app settings.',
        details: e.message,
        twitter_response: error_body,
        troubleshooting: [
          'Verify TWITTER_API_KEY and TWITTER_API_SECRET_KEY are correct in DigitalOcean',
          'Ensure callback URL matches exactly in Twitter app settings: https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback',
          'Check that app permissions are set to "Read and write"',
          'Make sure you saved the OAuth settings in Twitter Developer Portal'
        ]
      }, status: :bad_request
    rescue => e
      Rails.logger.error "Twitter OAuth error: #{e.class} - #{e.message}"
      Rails.logger.error "Twitter OAuth response: #{e.response.body if e.respond_to?(:response)}"
      Rails.logger.error e.backtrace.join("\n")
      # Return 400 instead of 500 to avoid frontend treating it as server error
      render json: { 
        error: 'Twitter authentication failed', 
        message: e.message,
        details: e.class.to_s,
        troubleshooting: [
          'Check Twitter API credentials in environment variables',
          'Verify callback URL is configured in Twitter app',
          'Ensure OAuth app settings are saved in Twitter Developer Portal'
        ]
      }, status: :bad_request
    end
  end
  
  # GET /api/v1/oauth/twitter/callback
  def twitter_callback
    consumer_key = ENV['TWITTER_API_KEY']
    consumer_secret = ENV['TWITTER_API_SECRET_KEY']
    
    unless consumer_key.present? && consumer_secret.present?
      Rails.logger.error "Twitter credentials missing in callback"
      return redirect_to oauth_callback_url(error: 'twitter_config_error', platform: 'X'), allow_other_host: true
    end
    
    oauth_token = params[:oauth_token]
    oauth_verifier = params[:oauth_verifier]
    
    # Get user_id from callback URL parameter (encoded in login) or session (fallback)
    user_id = params[:user_id] || session[:user_id]
    
    Rails.logger.info "Twitter callback - oauth_token: #{oauth_token.present? ? 'present' : 'missing'}, oauth_verifier: #{oauth_verifier.present? ? 'present' : 'missing'}, user_id from params: #{params[:user_id]}, user_id from session: #{session[:user_id]}"
    
    unless user_id
      Rails.logger.error "Twitter callback - no user_id found in params or session"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'X'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      Rails.logger.error "Twitter callback - user not found with id: #{user_id}"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'X'), allow_other_host: true
    end
    
    Rails.logger.info "Twitter callback - found user: #{user.id} (#{user.email})"
    
    # Create OAuth consumer
    consumer = ::OAuth::Consumer.new(
      consumer_key,
      consumer_secret,
      site: 'https://api.twitter.com',
      request_token_path: '/oauth/request_token',
      authorize_path: '/oauth/authorize',
      access_token_path: '/oauth/access_token'
    )
    
    begin
      # Try to get request token/secret from database first (using oauth_token from Twitter)
      # If not in database, fall back to session
      request_token_value = nil
      request_secret_value = nil
      
      if oauth_token.present? && ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
        begin
          token_data = OauthRequestToken.find_and_delete(oauth_token)
          
          if token_data
            request_token_value = token_data[:token]
            request_secret_value = token_data[:secret]
            # Also update user_id from database if not in params
            user_id = params[:user_id] || token_data[:user_id] || session[:user_id]
            Rails.logger.info "Twitter callback - retrieved request token from database"
          end
        rescue => e
          Rails.logger.error "Twitter callback - error retrieving from database: #{e.message}, falling back to session"
        end
      end
      
      # Fallback to session if not in database
      unless request_token_value.present? && request_secret_value.present?
        request_token_value = session[:twitter_request_token]
        request_secret_value = session[:twitter_request_secret]
        Rails.logger.info "Twitter callback - using request token from session"
      end
      
      unless request_token_value.present? && request_secret_value.present?
        Rails.logger.error "Twitter callback - missing request token in database and session. oauth_token: #{oauth_token.present? ? 'present' : 'missing'}"
        return redirect_to oauth_callback_url(error: 'twitter_session_expired', platform: 'X'), allow_other_host: true
      end
      
      # Recreate request token
      request_token = ::OAuth::RequestToken.new(
        consumer,
        request_token_value,
        request_secret_value
      )
      
      Rails.logger.info "Twitter callback - exchanging token for access token"
      
      # Exchange for access token
      access_token = request_token.get_access_token(oauth_verifier: oauth_verifier)
      
      Rails.logger.info "Twitter callback - access token obtained, user_id: #{access_token.params['user_id']}, screen_name: #{access_token.params['screen_name']}"
      
      # Save to user
      user.update!(
        twitter_oauth_token: access_token.token,
        twitter_oauth_token_secret: access_token.secret,
        twitter_user_id: access_token.params['user_id'],
        twitter_screen_name: access_token.params['screen_name']
      )
      
      Rails.logger.info "Twitter callback - user updated successfully"
      
      # Token already deleted from database in find_and_delete, just clear session
      session.delete(:twitter_request_token)
      session.delete(:twitter_request_secret)
      
      redirect_to oauth_callback_url(success: 'twitter_connected', platform: 'X'), allow_other_host: true
    rescue OAuth::Unauthorized => e
      Rails.logger.error "Twitter OAuth callback unauthorized error: #{e.message}"
      Rails.logger.error "Twitter OAuth callback response: #{e.response.body if e.respond_to?(:response) && e.response.respond_to?(:body)}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to oauth_callback_url(error: 'twitter_auth_failed', platform: 'X'), allow_other_host: true
    rescue => e
      Rails.logger.error "Twitter OAuth callback error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to oauth_callback_url(error: 'twitter_auth_failed', platform: 'X'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/linkedin/login
  # Initiates LinkedIn OAuth flow
  def linkedin_login
    begin
      # Encode user_id in state parameter since sessions don't persist in popups
      user_id = current_user.id
      random_state = SecureRandom.hex(16)
      # Format: user_id:random_state (we'll decode this in callback)
      state = "#{user_id}:#{random_state}"
      
      # Still store in session as backup
      session[:oauth_state] = random_state
      session[:user_id] = user_id
      
      client_id = ENV['LINKEDIN_CLIENT_ID']
      unless client_id
        return render json: { error: 'LinkedIn Client ID not configured' }, status: :internal_server_error
      end
      # Use production callback URL for LinkedIn OAuth
      redirect_uri = ENV['LINKEDIN_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/linkedin/callback' : "#{request.base_url}/api/v1/oauth/linkedin/callback")
      
      # Request scopes: w_member_social (for posting) + openid profile email (for profile info)
      # Note: OpenID Connect must be enabled in LinkedIn app Products settings
      # Note: LinkedIn requires users to re-authorize if scopes change
      scopes = "w_member_social openid profile email"
      oauth_url = "https://www.linkedin.com/oauth/v2/authorization?" \
                  "response_type=code" \
                  "&client_id=#{client_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&state=#{CGI.escape(state)}" \
                  "&scope=#{CGI.escape(scopes)}"
      
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "LinkedIn OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate LinkedIn OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/linkedin/callback
  def linkedin_callback
    code = params[:code]
    state = params[:state]
    error_param = params[:error]
    error_description = params[:error_description]
    
    Rails.logger.info "LinkedIn callback - received code: #{code.present? ? 'present' : 'missing'}, state: #{state}, error: #{error_param}, error_description: #{error_description}"
    
    # Check if LinkedIn returned an error (user denied, etc.)
    if error_param.present?
      Rails.logger.error "LinkedIn OAuth error from provider: #{error_param} - #{error_description}"
      error_message = case error_param
      when 'access_denied'
        'linkedin_access_denied'
      when 'invalid_request'
        'linkedin_invalid_request'
      when 'unauthorized_scope_error'
        'linkedin_scope_error'
      else
        'linkedin_auth_failed'
      end
      return redirect_to oauth_callback_url(error: error_message, platform: 'LinkedIn'), allow_other_host: true
    end
    
    # Check if code is missing
    unless code.present?
      Rails.logger.error "LinkedIn callback - missing authorization code"
      return redirect_to oauth_callback_url(error: 'linkedin_auth_failed', platform: 'LinkedIn'), allow_other_host: true
    end
    
    # Decode user_id from state parameter (format: user_id:random_state)
    user_id = nil
    if state&.include?(':')
      parts = state.split(':', 2)
      user_id = parts[0].to_i if parts[0].present? && parts[0].match?(/^\d+$/)
      random_state = parts[1]
      
      # Verify state matches session if available (optional check)
      if session[:oauth_state].present? && random_state != session[:oauth_state]
        Rails.logger.warn "LinkedIn OAuth state random part mismatch - received: #{random_state}, expected: #{session[:oauth_state]}"
      end
    else
      # Fallback: try to get from session
      user_id = session[:user_id]
      Rails.logger.info "LinkedIn callback - using session user_id: #{user_id}"
    end
    
    unless user_id
      Rails.logger.error "LinkedIn callback - no user_id found in state or session"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'LinkedIn'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.error "LinkedIn callback - user not found with id: #{user_id}"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'LinkedIn'), allow_other_host: true
    end
    
    Rails.logger.info "LinkedIn callback - found user: #{user.id} (#{user.email})"
    
    # Exchange code for access token
    client_id = ENV['LINKEDIN_CLIENT_ID']
    unless client_id
      Rails.logger.error "LinkedIn Client ID not configured"
      return redirect_to oauth_callback_url(error: 'linkedin_config_error', platform: 'LinkedIn'), allow_other_host: true
    end
    
    client_secret = ENV['LINKEDIN_CLIENT_SECRET']
    unless client_secret
      Rails.logger.error "LinkedIn Client Secret not configured"
      return redirect_to oauth_callback_url(error: 'linkedin_config_error', platform: 'LinkedIn'), allow_other_host: true
    end
    
    redirect_uri = ENV['LINKEDIN_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/linkedin/callback' : "#{request.base_url}/api/v1/oauth/linkedin/callback")
    
    token_url = "https://www.linkedin.com/oauth/v2/accessToken"
    
    begin
      # Request id_token in addition to access_token for OpenID Connect
      response = HTTParty.post(token_url, {
        body: {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          client_secret: client_secret
        },
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
      })
      
      Rails.logger.info "LinkedIn token exchange response status: #{response.code}, body: #{response.body[0..500]}"
      
      unless response.success?
        Rails.logger.error "LinkedIn token exchange failed: #{response.code} - #{response.body}"
        return redirect_to oauth_callback_url(error: 'linkedin_auth_failed', platform: 'LinkedIn'), allow_other_host: true
      end
      
      data = JSON.parse(response.body)
      Rails.logger.info "LinkedIn token exchange data keys: #{data.keys.inspect}, has id_token: #{data['id_token'].present?}"
      
      if data['access_token']
        user.update!(
          linkedin_access_token: data['access_token'],
          linkedin_access_token_time: Time.current
        )
        
        # Try to extract profile ID from id_token first (OpenID Connect)
        profile_id = nil
        if data['id_token']
          begin
            require 'base64'
            require 'json'
            # Decode JWT id_token (format: header.payload.signature)
            token_parts = data['id_token'].split('.')
            if token_parts.length == 3
              # Decode the payload (second part)
              payload = Base64.urlsafe_decode64(token_parts[1])
              id_token_data = JSON.parse(payload)
              Rails.logger.info "LinkedIn id_token payload: #{id_token_data.inspect}"
              
              # Extract profile ID from 'sub' claim (format: urn:li:person:XXXXX or just XXXXX)
              if id_token_data['sub']
                profile_id = id_token_data['sub'].to_s.split(':').last
                user.update!(linkedin_profile_id: profile_id)
                Rails.logger.info "LinkedIn profile ID extracted from id_token: #{profile_id}"
              end
            end
          rescue => e
            Rails.logger.warn "Failed to decode LinkedIn id_token: #{e.message}"
          end
        end
        
        # If we didn't get it from id_token, try API endpoints
        unless profile_id
          begin
            profile_id = fetch_linkedin_profile_id(user, data['access_token'])
            unless profile_id
              Rails.logger.info "LinkedIn profile ID not available immediately - will be extracted during first post"
            end
          rescue => e
            Rails.logger.warn "Failed to fetch LinkedIn profile ID during OAuth callback: #{e.message}. Will try to extract during first post."
            # Don't fail the OAuth flow if profile ID fetch fails - it can be extracted during posting
          end
        end
        
        redirect_to oauth_callback_url(success: 'linkedin_connected', platform: 'LinkedIn'), allow_other_host: true
      else
        error_msg = data['error_description'] || data['error'] || 'Unknown error'
        Rails.logger.error "LinkedIn token exchange failed - no access_token in response: #{error_msg}"
        redirect_to oauth_callback_url(error: 'linkedin_auth_failed', platform: 'LinkedIn'), allow_other_host: true
      end
    rescue JSON::ParserError => e
      Rails.logger.error "LinkedIn OAuth JSON parse error: #{e.message}, response body: #{response.body[0..200]}"
      redirect_to oauth_callback_url(error: 'linkedin_auth_failed', platform: 'LinkedIn'), allow_other_host: true
    rescue => e
      Rails.logger.error "LinkedIn OAuth error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to oauth_callback_url(error: 'linkedin_auth_failed', platform: 'LinkedIn'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/google/login
  # Initiates Google OAuth flow
  def google_login
    begin
      state = SecureRandom.hex(16)
      user_id = current_user.id
      
      # Encode user_id in state parameter for cross-origin popup support
      encoded_state = "#{user_id}:#{state}"
      
      # Store state in database for popup support (with fallback to session)
      if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
        OauthRequestToken.create!(
          oauth_token: encoded_state,
          request_secret: state,
          user_id: user_id,
          expires_at: 10.minutes.from_now
        )
      else
        session[:oauth_state] = state
        session[:user_id] = user_id
      end
      
      client_id = ENV['GOOGLE_CLIENT_ID']
      unless client_id
        return render json: { error: 'Google Client ID not configured' }, status: :internal_server_error
      end
      # Use production callback URL for Google OAuth
      redirect_uri = ENV['GOOGLE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/google/callback' : "#{request.base_url}/api/v1/oauth/google/callback")
      
      oauth_url = "https://accounts.google.com/o/oauth2/v2/auth?" \
                  "client_id=#{client_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&response_type=code" \
                  "&scope=#{CGI.escape('https://www.googleapis.com/auth/business.manage')}" \
                  "&access_type=offline" \
                  "&state=#{CGI.escape(encoded_state)}"
      
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "Google OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate Google OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/google/callback
  def google_callback
    code = params[:code]
    state_param = params[:state]
    
    # Decode user_id from state parameter
    user_id = nil
    state = nil
    
    if state_param&.include?(':')
      parts = state_param.split(':', 2)
      user_id = parts[0].to_i
      state = parts[1]
    else
      state = state_param
    end
    
    # Retrieve state from database (with fallback to session)
    stored_state = nil
    if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens') && state_param
      token_record = OauthRequestToken.find_and_delete(state_param)
      if token_record
        # find_and_delete returns a Hash, not an object
        stored_state = token_record[:secret] || token_record['secret']
        user_id ||= (token_record[:user_id] || token_record['user_id'])
      end
    end
    
    # Fallback to session if database lookup failed
    unless stored_state
      stored_state = session[:oauth_state]
      user_id ||= session[:user_id]
    end
    
    # Compare the decoded state (part after colon) with stored secret
    if state != stored_state
      Rails.logger.error "Google OAuth state mismatch: expected #{stored_state}, got #{state}"
      return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'Google My Business'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'Google My Business'), allow_other_host: true
    end
    
    # Exchange code for access token
    client_id = ENV['GOOGLE_CLIENT_ID']
    raise 'Google Client ID not configured' unless client_id
    client_secret = ENV['GOOGLE_CLIENT_SECRET']
    raise 'Google Client Secret not configured' unless client_secret
    redirect_uri = ENV['GOOGLE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/google/callback' : "#{request.base_url}/api/v1/oauth/google/callback")
    
    token_url = "https://oauth2.googleapis.com/token"
    
    begin
      response = HTTParty.post(token_url, {
        body: {
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: 'authorization_code'
        }
      })
      
      data = JSON.parse(response.body)
      
      if data['refresh_token']
        user.update!(google_refresh_token: data['refresh_token'])
        
        # Fetch Google account info
        begin
          if data['access_token']
            google_info_url = "https://www.googleapis.com/oauth2/v2/userinfo?access_token=#{data['access_token']}"
            google_info_response = HTTParty.get(google_info_url)
            google_info_data = JSON.parse(google_info_response.body)
            
            if google_info_data['name'] && user.respond_to?(:google_account_name=)
              user.update!(google_account_name: google_info_data['name'] || google_info_data['email'])
            end
          end
        rescue => e
          Rails.logger.warn "Failed to fetch Google account info: #{e.message}"
        end
        
        redirect_to oauth_callback_url(success: 'google_connected', platform: 'Google My Business'), allow_other_host: true
        else
        redirect_to oauth_callback_url(error: 'google_auth_failed', platform: 'Google My Business'), allow_other_host: true
      end
    rescue => e
      Rails.logger.error "Google OAuth error: #{e.message}"
      redirect_to oauth_callback_url(error: 'google_auth_failed', platform: 'Google My Business'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/tiktok/login
  # Initiates TikTok OAuth flow
  def tiktok_login
    begin
      # Encode user_id in state parameter since sessions don't persist in popups
      user_id = current_user.id
      random_state = SecureRandom.hex(16)
      # Format: user_id:random_state (we'll decode this in callback)
      state = "#{user_id}:#{random_state}"
      
      # Store state in database (sessions don't persist in popups)
      begin
        if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
          OauthRequestToken.create!(
            oauth_token: random_state, # Use random_state as the token key
            request_secret: state, # Store full state as secret
            user_id: user_id,
            expires_at: 10.minutes.from_now
          )
          Rails.logger.info "TikTok OAuth - stored state in database"
        end
      rescue => e
        Rails.logger.error "TikTok OAuth - failed to store state in database: #{e.message}, falling back to session"
      end
      
      # Still store in session as backup
      session[:oauth_state] = random_state
      session[:user_id] = user_id
      
      client_key = ENV['TIKTOK_CLIENT_KEY']
      unless client_key
        return render json: { error: 'TikTok Client Key not configured' }, status: :internal_server_error
      end
      
      # Use production callback URL for TikTok OAuth (backend callback)
      redirect_uri = ENV['TIKTOK_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/tiktok/callback' : "#{request.base_url}/api/v1/oauth/tiktok/callback")
      
      oauth_url = "https://www.tiktok.com/v2/auth/authorize?" \
                  "client_key=#{client_key}" \
                  "&scope=user.info.basic,video.publish" \
                  "&response_type=code" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&state=#{state}"
      
      Rails.logger.info "TikTok OAuth - generated URL with state: #{state[0..20]}..., user_id: #{user_id}"
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "TikTok OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate TikTok OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/tiktok/callback
  def tiktok_callback
    code = params[:code]
    state = params[:state]
    
    # Decode user_id from state parameter (format: user_id:random_state)
    user_id = nil
    random_state = nil
    if state.present? && state.include?(':')
      parts = state.split(':', 2)
      user_id = parts[0].to_i if parts[0].present?
      random_state = parts[1] if parts[1].present?
    end
    
    # Try to retrieve state from database first
    if random_state.present? && ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
      begin
        token_data = OauthRequestToken.find_and_delete(random_state)
        if token_data && token_data[:request_secret] == state
          user_id = token_data[:user_id] if user_id.nil?
          Rails.logger.info "TikTok callback - retrieved state from database"
        end
      rescue => e
        Rails.logger.error "TikTok callback - error retrieving from database: #{e.message}, falling back to session"
      end
    end
    
    # Fallback to session if not in database
    unless user_id
      user_id = session[:user_id]
      if state != session[:oauth_state] && random_state != session[:oauth_state]
        Rails.logger.error "TikTok callback - state mismatch. Expected: #{session[:oauth_state]}, Got: #{state}"
        return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'TikTok'), allow_other_host: true
      end
    end
    
    unless user_id
      Rails.logger.error "TikTok callback - no user_id found"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'TikTok'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      Rails.logger.error "TikTok callback - user not found with id: #{user_id}"
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'TikTok'), allow_other_host: true
    end
    
    Rails.logger.info "TikTok callback - found user: #{user.id} (#{user.email})"
    
    # Exchange code for access token
    client_key = ENV['TIKTOK_CLIENT_KEY']
    unless client_key
      Rails.logger.error "TikTok Client Key not configured"
      return redirect_to oauth_callback_url(error: 'tiktok_config_error', platform: 'TikTok'), allow_other_host: true
    end
    
    client_secret = ENV['TIKTOK_CLIENT_SECRET']
    unless client_secret
      Rails.logger.error "TikTok Client Secret not configured"
      return redirect_to oauth_callback_url(error: 'tiktok_config_error', platform: 'TikTok'), allow_other_host: true
    end
    
    # Use backend callback URL (must match what's in TikTok app settings)
    redirect_uri = ENV['TIKTOK_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/tiktok/callback' : "#{request.base_url}/api/v1/oauth/tiktok/callback")
    
    token_url = "https://open.tiktokapis.com/v2/oauth/token/"
    
    begin
      response = HTTParty.post(token_url, {
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded'
        },
        body: {
          client_key: client_key,
          client_secret: client_secret,
          code: code,
          grant_type: 'authorization_code',
          redirect_uri: redirect_uri
        }
      })
      
      Rails.logger.info "TikTok token exchange response status: #{response.code}, body: #{response.body[0..500]}"
      
      unless response.success?
        Rails.logger.error "TikTok token exchange failed: #{response.code} - #{response.body}"
        return redirect_to oauth_callback_url(error: 'tiktok_auth_failed', platform: 'TikTok'), allow_other_host: true
      end
      
      data = JSON.parse(response.body)
      
      if data['access_token']
        user.update!(
          tiktok_access_token: data['access_token'],
          tiktok_refresh_token: data['refresh_token']
        )
        
        Rails.logger.info "TikTok callback - user updated successfully"
        
        # Clear session
        session.delete(:oauth_state)
        session.delete(:user_id)
        
        redirect_to oauth_callback_url(success: 'tiktok_connected', platform: 'TikTok'), allow_other_host: true
      else
        error_msg = data['error_description'] || data['error'] || 'Unknown error'
        Rails.logger.error "TikTok token exchange failed - no access_token in response: #{error_msg}"
        redirect_to oauth_callback_url(error: 'tiktok_auth_failed', platform: 'TikTok'), allow_other_host: true
      end
    rescue JSON::ParserError => e
      Rails.logger.error "TikTok OAuth JSON parse error: #{e.message}, response body: #{response.body[0..200]}"
      redirect_to oauth_callback_url(error: 'tiktok_auth_failed', platform: 'TikTok'), allow_other_host: true
    rescue => e
      Rails.logger.error "TikTok OAuth error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to oauth_callback_url(error: 'tiktok_auth_failed', platform: 'TikTok'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/youtube/login
  # Initiates YouTube OAuth flow
  def youtube_login
    begin
      state = SecureRandom.hex(16)
      user_id = current_user.id
      
      # Encode user_id in state parameter for cross-origin popup support
      encoded_state = "#{user_id}:#{state}"
      
      # Store state in database for popup support (with fallback to session)
      if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
        OauthRequestToken.create!(
          oauth_token: encoded_state,
          request_secret: state,
          user_id: user_id,
          expires_at: 10.minutes.from_now
        )
      else
        session[:oauth_state] = state
        session[:user_id] = user_id
      end
      
      client_id = ENV['YOUTUBE_CLIENT_ID']
      unless client_id
        return render json: { error: 'YouTube Client ID not configured' }, status: :internal_server_error
      end
      # Use backend callback URL for YouTube OAuth
      redirect_uri = ENV['YOUTUBE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/youtube/callback' : "#{request.base_url}/api/v1/oauth/youtube/callback")
      
      oauth_url = "https://accounts.google.com/o/oauth2/v2/auth?" \
                  "client_id=#{client_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&response_type=code" \
                  "&scope=#{CGI.escape('https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube')}" \
                  "&access_type=offline" \
                  "&state=#{CGI.escape(encoded_state)}"
      
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "YouTube OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate YouTube OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/youtube/callback
  def youtube_callback
    code = params[:code]
    state_param = params[:state]
    
    # Decode user_id from state parameter
    user_id = nil
    state = nil
    
    if state_param&.include?(':')
      parts = state_param.split(':', 2)
      user_id = parts[0].to_i
      state = parts[1]
    else
      state = state_param
    end
    
    # Retrieve state from database (with fallback to session)
    stored_state = nil
    if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens') && state_param
      token_record = OauthRequestToken.find_and_delete(state_param)
      if token_record
        # find_and_delete returns a Hash, not an object
        stored_state = token_record[:secret] || token_record['secret']
        user_id ||= (token_record[:user_id] || token_record['user_id'])
      end
    end
    
    # Fallback to session if database lookup failed
    unless stored_state
      stored_state = session[:oauth_state]
      user_id ||= session[:user_id]
    end
    
    # Compare the decoded state (part after colon) with stored secret
    if state != stored_state
      Rails.logger.error "YouTube OAuth state mismatch: expected #{stored_state}, got #{state}"
      return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'YouTube'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'YouTube'), allow_other_host: true
    end
    
    # Exchange code for access token
    client_id = ENV['YOUTUBE_CLIENT_ID']
    raise 'YouTube Client ID not configured' unless client_id
    client_secret = ENV['YOUTUBE_CLIENT_SECRET']
    raise 'YouTube Client Secret not configured' unless client_secret
    redirect_uri = ENV['YOUTUBE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/youtube/callback' : "#{request.base_url}/api/v1/oauth/youtube/callback")
    
    token_url = "https://oauth2.googleapis.com/token"
    
    begin
      response = HTTParty.post(token_url, {
        body: {
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: 'authorization_code'
        }
      })
      
      data = JSON.parse(response.body)
      
      if data['refresh_token']
        user.update!(
          youtube_refresh_token: data['refresh_token'],
          youtube_access_token: data['access_token']
        )
        
        redirect_to oauth_callback_url(success: 'youtube_connected', platform: 'YouTube'), allow_other_host: true
        else
        redirect_to oauth_callback_url(error: 'youtube_auth_failed', platform: 'YouTube'), allow_other_host: true
      end
    rescue => e
      Rails.logger.error "YouTube OAuth error: #{e.message}"
      redirect_to oauth_callback_url(error: 'youtube_auth_failed', platform: 'YouTube'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/pinterest/login
  # Initiates Pinterest OAuth flow
  def pinterest_login
    begin
      state = SecureRandom.hex(16)
      user_id = current_user.id
      
      # Encode user_id in state parameter for cross-origin popup support
      encoded_state = "#{user_id}:#{state}"
      
      # Store state in database for popup support (with fallback to session)
      if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens')
        OauthRequestToken.create!(
          oauth_token: encoded_state,
          request_secret: state,
          user_id: user_id,
          expires_at: 10.minutes.from_now
        )
      else
        session[:oauth_state] = state
        session[:user_id] = user_id
      end
      
      client_id = ENV['PINTEREST_CLIENT_ID']
      unless client_id
        return render json: { error: 'Pinterest Client ID not configured' }, status: :internal_server_error
      end
      
      redirect_uri = ENV['PINTEREST_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/pinterest/callback' : "#{request.base_url}/api/v1/oauth/pinterest/callback")
      
      # Pinterest OAuth 2.0 authorization URL
      # Pinterest requires scopes to be URL-encoded
      scopes = "boards:read,boards:write,pins:read,pins:write"
      oauth_url = "https://www.pinterest.com/oauth/?" \
                  "client_id=#{client_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&response_type=code" \
                  "&scope=#{CGI.escape(scopes)}" \
                  "&state=#{CGI.escape(encoded_state)}"
      
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "Pinterest OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate Pinterest OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/pinterest/callback
  def pinterest_callback
    code = params[:code]
    state_param = params[:state]
    
    # Decode user_id from state parameter
    user_id = nil
    state = nil
    
    if state_param&.include?(':')
      parts = state_param.split(':', 2)
      user_id = parts[0].to_i
      state = parts[1]
    else
      state = state_param
    end
    
    # Retrieve state from database (with fallback to session)
    stored_state = nil
    if ActiveRecord::Base.connection.table_exists?('oauth_request_tokens') && state_param
      token_record = OauthRequestToken.find_and_delete(state_param)
      if token_record
        # find_and_delete returns a Hash, not an object
        stored_state = token_record[:secret] || token_record['secret']
        user_id ||= (token_record[:user_id] || token_record['user_id'])
      end
    end
    
    # Fallback to session if database lookup failed
    unless stored_state
      stored_state = session[:oauth_state]
      user_id ||= session[:user_id]
    end
    
    if state != stored_state
      Rails.logger.error "Pinterest OAuth state mismatch: expected #{stored_state}, got #{state}"
      return redirect_to oauth_callback_url(error: 'invalid_state', platform: 'Pinterest'), allow_other_host: true
    end
    
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to oauth_callback_url(error: 'user_not_found', platform: 'Pinterest'), allow_other_host: true
    end
    
    # Exchange code for access token
    client_id = ENV['PINTEREST_CLIENT_ID']
    raise 'Pinterest Client ID not configured' unless client_id
    client_secret = ENV['PINTEREST_CLIENT_SECRET']
    raise 'Pinterest Client Secret not configured' unless client_secret
    redirect_uri = ENV['PINTEREST_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/pinterest/callback' : "#{request.base_url}/api/v1/oauth/pinterest/callback")
    
    token_url = "https://api.pinterest.com/v5/oauth/token"
    
    begin
      response = HTTParty.post(token_url, {
        body: {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri
        },
        headers: {
          'Authorization' => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}",
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
      })
      
      data = JSON.parse(response.body)
      
      if data['access_token']
        if user.respond_to?(:pinterest_access_token=)
          user.update!(
            pinterest_access_token: data['access_token'],
            pinterest_refresh_token: data['refresh_token']
          )
          
          # Fetch Pinterest user info
          begin
            pinterest_info_url = "https://api.pinterest.com/v5/user_account"
            pinterest_info_response = HTTParty.get(pinterest_info_url, {
              headers: {
                'Authorization' => "Bearer #{data['access_token']}"
              }
            })
            pinterest_info_data = JSON.parse(pinterest_info_response.body)
            
            if pinterest_info_data['username'] && user.respond_to?(:pinterest_username=)
              user.update!(pinterest_username: pinterest_info_data['username'])
            end
          rescue => e
            Rails.logger.warn "Failed to fetch Pinterest user info: #{e.message}"
          end
          
          redirect_to oauth_callback_url(success: 'pinterest_connected', platform: 'Pinterest'), allow_other_host: true
        else
          Rails.logger.error "Pinterest columns not found in users table. Migration may not have been run."
          redirect_to oauth_callback_url(error: 'pinterest_migration_required', platform: 'Pinterest'), allow_other_host: true
        end
      else
        Rails.logger.error "Pinterest OAuth token exchange failed: #{data}"
        redirect_to oauth_callback_url(error: 'pinterest_auth_failed', platform: 'Pinterest'), allow_other_host: true
      end
    rescue => e
      Rails.logger.error "Pinterest OAuth error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to oauth_callback_url(error: 'pinterest_auth_failed', platform: 'Pinterest'), allow_other_host: true
    end
  end
  
  # GET /api/v1/oauth/instagram/connect
  # Connects Instagram account (requires Facebook to be connected first)
  def instagram_connect
    unless current_user.fb_user_access_key.present?
      return render json: { 
        error: 'Facebook not connected', 
        message: 'Please connect Facebook first. Instagram uses Facebook\'s API and requires a connected Facebook account.' 
      }, status: :bad_request
    end
    
    begin
      instagram_info = fetch_instagram_account(current_user)
      
      if current_user.instagram_business_id.present?
        render json: { 
          success: true, 
          message: 'Instagram connected successfully',
          instagram_business_id: current_user.instagram_business_id,
          instagram_account: instagram_info
        }
      else
        render json: { 
          error: 'Instagram account not found', 
          message: 'No Instagram Business account found connected to your Facebook Page. Please make sure your Facebook Page is connected to an Instagram Business account.' 
        }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Instagram connect error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { 
        error: 'Failed to connect Instagram', 
        message: e.message 
      }, status: :internal_server_error
    end
  end
  
  
  private
  
  # Fetch LinkedIn profile ID after OAuth connection
  # Returns profile ID if found, nil otherwise (will be extracted during posting)
  def fetch_linkedin_profile_id(user, access_token)
    # Try /me endpoint first (requires r_liteprofile scope - may not be available)
    url = "https://api.linkedin.com/v2/me"
    headers = {
      'Authorization' => "Bearer #{access_token}",
      'X-Restli-Protocol-Version' => '2.0.0'
    }
    
    response = HTTParty.get(url, headers: headers)
    
    if response.success?
      data = JSON.parse(response.body)
      Rails.logger.info "LinkedIn /me response: #{data.inspect}"
      if data['id']
        user.update!(linkedin_profile_id: data['id'])
        Rails.logger.info "LinkedIn profile ID fetched from /me and saved: #{data['id']}"
        return data['id']
      end
    else
      Rails.logger.warn "LinkedIn /me endpoint failed: #{response.code} - #{response.body}"
    end
    
    # Fallback: try userInfo endpoint (OpenID Connect - requires openid scope, may not be available)
    url = "https://api.linkedin.com/v2/userinfo"
    headers = {
      'Authorization' => "Bearer #{access_token}"
    }
    
    response = HTTParty.get(url, headers: headers)
    
    if response.success?
      data = JSON.parse(response.body)
      Rails.logger.info "LinkedIn userInfo response: #{data.inspect}"
      # userInfo endpoint returns 'sub' as the user ID (format: urn:li:person:xxxxx or just xxxxx)
      if data['sub']
        # Extract just the ID part if it's a URN
        profile_id = data['sub'].to_s.split(':').last
        user.update!(linkedin_profile_id: profile_id)
        Rails.logger.info "LinkedIn profile ID fetched and saved from userInfo: #{profile_id}"
        return profile_id
      end
    else
      Rails.logger.warn "LinkedIn userInfo endpoint failed: #{response.code} - #{response.body}"
    end
    
    Rails.logger.info "Could not fetch LinkedIn profile ID from API - will be extracted during first post attempt"
    nil
  end
  
  # Fetch Instagram Business account ID from connected Facebook Page
  def fetch_instagram_account(user)
    return nil unless user.fb_user_access_key.present?
    
    Rails.logger.info "Fetching Instagram account for user: #{user.id}"
    
    # Get user's Facebook pages
    url = "https://graph.facebook.com/v18.0/me/accounts"
    params = {
      access_token: user.fb_user_access_key,
      fields: 'id,name,access_token,instagram_business_account',
      limit: 1000
    }
    
    response = HTTParty.get(url, query: params)
    data = JSON.parse(response.body)
    
    if data['data'] && data['data'].any?
      # Look for a page with an Instagram Business account
      data['data'].each do |page|
        if page['instagram_business_account']
          instagram_id = page['instagram_business_account']['id']
          user.update!(instagram_business_id: instagram_id)
          Rails.logger.info "Instagram Business account found and saved: #{instagram_id}"
          
          # Return Instagram account info
          return {
            id: instagram_id,
            page_id: page['id'],
            page_name: page['name']
          }
        end
      end
      
      Rails.logger.warn "No Instagram Business account found in any connected Facebook Page"
    else
      Rails.logger.warn "No Facebook Pages found for user"
    end
    
    nil
  end
  
  # Get Instagram account information
  def get_instagram_account_info(user)
    return nil unless user.fb_user_access_key.present? && user.instagram_business_id.present?
    
    # Get page access token
    page_token = get_page_access_token_for_instagram(user)
    return nil unless page_token
    
    # Get Instagram account details
    url = "https://graph.facebook.com/v18.0/#{user.instagram_business_id}"
    params = {
      access_token: page_token,
      fields: 'id,username,name,profile_picture_url,website'
    }
    
    response = HTTParty.get(url, query: params)
    
    if response.success?
      data = JSON.parse(response.body)
      Rails.logger.info "Instagram account info: #{data.inspect}"
      return data
    else
      Rails.logger.error "Failed to get Instagram account info: #{response.code} - #{response.body}"
      raise "Failed to get Instagram account info: #{response.body}"
    end
  end
  
  # Get page access token for Instagram (helper method)
  def get_page_access_token_for_instagram(user)
    return nil unless user.fb_user_access_key.present?
    
    url = "https://graph.facebook.com/v18.0/me/accounts"
    params = {
      access_token: user.fb_user_access_key,
      fields: 'id,name,access_token,instagram_business_account',
      limit: 1000
    }
    
    response = HTTParty.get(url, query: params)
    data = JSON.parse(response.body)
    
    if data['data'] && data['data'].any?
      # Find the page that has the Instagram account
      data['data'].each do |page|
        if page['instagram_business_account']
          instagram_id = page['instagram_business_account']['id']
          if instagram_id == user.instagram_business_id
            Rails.logger.info "Found matching page for Instagram account: #{page['id']} (#{page['name']})"
            return page['access_token']
          end
        end
      end
      
      # Fallback: return first page's token
      Rails.logger.warn "No matching page found for Instagram account, using first page"
      return data['data'].first['access_token']
    end
    
    nil
  end
end

