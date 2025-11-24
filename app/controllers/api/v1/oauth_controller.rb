class Api::V1::OauthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:facebook_callback, :twitter_callback, :linkedin_callback, :google_callback, :tiktok_callback, :youtube_callback]
  
  private
  
  # Helper method to get the correct frontend URL for redirects
  def frontend_url
    if Rails.env.development?
      "http://localhost:3002"  # Use the port your frontend is running on
    else
      ENV['FRONTEND_URL'] || 'https://social-rotation-frontend-f4mwb.ondigitalocean.app'
    end
  end
  
  # GET /api/v1/oauth/facebook/login
  # Initiates Facebook OAuth flow
  def facebook_login
    begin
      # Generate state token for CSRF protection
      state = SecureRandom.hex(16)
      session[:oauth_state] = state
      session[:user_id] = current_user.id
      
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
    
    # Verify state to prevent CSRF
    if state != session[:oauth_state]
      return redirect_to "#{frontend_url}/profile?error=invalid_state"
    end
    
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
    end
    
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
        
        # Redirect back to frontend with success
        redirect_to "#{frontend_url}/profile?success=facebook_connected"
      else
        redirect_to "#{frontend_url}/profile?error=facebook_auth_failed"
      end
    rescue => e
      Rails.logger.error "Facebook OAuth error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=facebook_auth_failed"
    end
  end
  
  # GET /api/v1/oauth/twitter/login
  # Initiates Twitter OAuth 1.0a flow
  def twitter_login
    consumer_key = ENV['TWITTER_API_KEY'] || '5PIs17xez9qVUKft2qYOec6uR'
    consumer_secret = ENV['TWITTER_API_SECRET_KEY'] || 'wa4aaGQBK3AU75ji1eUBmNfCLO0IhotZD36faf3ZuX91WOnrqz'
      callback_url = ENV['TWITTER_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/twitter/callback' : "#{request.base_url}/api/v1/oauth/twitter/callback")
    
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
      # Get request token
      request_token = consumer.get_request_token(oauth_callback: callback_url)
      
      # Store request token in session
      session[:twitter_request_token] = request_token.token
      session[:twitter_request_secret] = request_token.secret
      session[:user_id] = current_user.id
      
      # Return authorize URL
      oauth_url = request_token.authorize_url
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "Twitter OAuth error: #{e.message}"
      render json: { error: 'Twitter authentication failed', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/twitter/callback
  def twitter_callback
    consumer_key = ENV['TWITTER_API_KEY'] || '5PIs17xez9qVUKft2qYOec6uR'
    consumer_secret = ENV['TWITTER_API_SECRET_KEY'] || 'wa4aaGQBK3AU75ji1eUBmNfCLO0IhotZD36faf3ZuX91WOnrqz'
    
    oauth_token = params[:oauth_token]
    oauth_verifier = params[:oauth_verifier]
    
    # Get user from session
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
    end
    
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
      # Recreate request token from session
      request_token = ::OAuth::RequestToken.new(
        consumer,
        session[:twitter_request_token],
        session[:twitter_request_secret]
      )
      
      # Exchange for access token
      access_token = request_token.get_access_token(oauth_verifier: oauth_verifier)
      
      # Save to user
      user.update!(
        twitter_oauth_token: access_token.token,
        twitter_oauth_token_secret: access_token.secret,
        twitter_user_id: access_token.params['user_id'],
        twitter_screen_name: access_token.params['screen_name']
      )
      
      # Clear session
      session.delete(:twitter_request_token)
      session.delete(:twitter_request_secret)
      
      redirect_to "#{frontend_url}/profile?success=twitter_connected"
    rescue => e
      Rails.logger.error "Twitter OAuth callback error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=twitter_auth_failed"
    end
  end
  
  # GET /api/v1/oauth/linkedin/login
  # Initiates LinkedIn OAuth flow
  def linkedin_login
    begin
      state = SecureRandom.hex(16)
      session[:oauth_state] = state
      session[:user_id] = current_user.id
      
      client_id = ENV['LINKEDIN_CLIENT_ID']
      unless client_id
        return render json: { error: 'LinkedIn Client ID not configured' }, status: :internal_server_error
      end
      # Use production callback URL for LinkedIn OAuth
      redirect_uri = ENV['LINKEDIN_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3000/api/v1/oauth/linkedin/callback' : "#{request.base_url}/api/v1/oauth/linkedin/callback")
      
      oauth_url = "https://www.linkedin.com/oauth/v2/authorization?" \
                  "response_type=code" \
                  "&client_id=#{client_id}" \
                  "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                  "&state=#{state}" \
                  "&scope=w_member_social"
      
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
    
    if state != session[:oauth_state]
      return redirect_to "#{frontend_url}/profile?error=invalid_state"
    end
    
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
    end
    
    # Exchange code for access token
    client_id = ENV['LINKEDIN_CLIENT_ID']
    raise 'LinkedIn Client ID not configured' unless client_id
    client_secret = ENV['LINKEDIN_CLIENT_SECRET']
    raise 'LinkedIn Client Secret not configured' unless client_secret
    redirect_uri = ENV['LINKEDIN_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3001/linkedin/callback' : 'https://social-rotation-frontend.onrender.com/linkedin/callback')
    
    token_url = "https://www.linkedin.com/oauth/v2/accessToken"
    
    begin
      response = HTTParty.post(token_url, {
        body: {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          client_secret: client_secret
        }
      })
      
      data = JSON.parse(response.body)
      
      if data['access_token']
        user.update!(
          linkedin_access_token: data['access_token'],
          linkedin_access_token_time: Time.current
        )
        
        redirect_to "#{frontend_url}/profile?success=linkedin_connected"
      else
        redirect_to "#{frontend_url}/profile?error=linkedin_auth_failed"
      end
    rescue => e
      Rails.logger.error "LinkedIn OAuth error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=linkedin_auth_failed"
    end
  end
  
  # GET /api/v1/oauth/google/login
  # Initiates Google OAuth flow
  def google_login
    begin
      state = SecureRandom.hex(16)
      session[:oauth_state] = state
      session[:user_id] = current_user.id
      
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
                  "&state=#{state}"
      
      render json: { oauth_url: oauth_url }
    rescue => e
      Rails.logger.error "Google OAuth login error: #{e.message}"
      render json: { error: 'Failed to initiate Google OAuth', details: e.message }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/oauth/google/callback
  def google_callback
    code = params[:code]
    state = params[:state]
    
    if state != session[:oauth_state]
      return redirect_to "#{frontend_url}/profile?error=invalid_state"
    end
    
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
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
        redirect_to "#{frontend_url}/profile?success=google_connected"
      else
        redirect_to "#{frontend_url}/profile?error=google_auth_failed"
      end
    rescue => e
      Rails.logger.error "Google OAuth error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=google_auth_failed"
    end
  end
  
  # GET /api/v1/oauth/tiktok/login
  # Initiates TikTok OAuth flow
  def tiktok_login
    state = SecureRandom.hex(16)
    session[:oauth_state] = state
    session[:user_id] = current_user.id
    
    client_key = ENV['TIKTOK_CLIENT_KEY']
    raise 'TikTok Client Key not configured' unless client_key
    redirect_uri = ENV['TIKTOK_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3001/tiktok/callback' : 'https://social-rotation-frontend.onrender.com/tiktok/callback')
    
    oauth_url = "https://www.tiktok.com/v2/auth/authorize?" \
                "client_key=#{client_key}" \
                "&scope=user.info.basic,video.publish" \
                "&response_type=code" \
                "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                "&state=#{state}"
    
    render json: { oauth_url: oauth_url }
  end
  
  # GET /api/v1/oauth/tiktok/callback
  def tiktok_callback
    code = params[:code]
    state = params[:state]
    
    if state != session[:oauth_state]
      return redirect_to "#{frontend_url}/profile?error=invalid_state"
    end
    
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
    end
    
    # Exchange code for access token
    client_key = ENV['TIKTOK_CLIENT_KEY']
    raise 'TikTok Client Key not configured' unless client_key
    client_secret = ENV['TIKTOK_CLIENT_SECRET']
    raise 'TikTok Client Secret not configured' unless client_secret
    redirect_uri = ENV['TIKTOK_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3001/tiktok/callback' : 'https://social-rotation-frontend.onrender.com/tiktok/callback')
    
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
      
      data = JSON.parse(response.body)
      
      if data['access_token']
        user.update!(
          tiktok_access_token: data['access_token'],
          tiktok_refresh_token: data['refresh_token']
        )
        
        redirect_to "#{frontend_url}/profile?success=tiktok_connected"
      else
        redirect_to "#{frontend_url}/profile?error=tiktok_auth_failed"
      end
    rescue => e
      Rails.logger.error "TikTok OAuth error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=tiktok_auth_failed"
    end
  end
  
  # GET /api/v1/oauth/youtube/login
  # Initiates YouTube OAuth flow
  def youtube_login
    state = SecureRandom.hex(16)
    session[:oauth_state] = state
    session[:user_id] = current_user.id
    
    client_id = ENV['YOUTUBE_CLIENT_ID']
    raise 'YouTube Client ID not configured' unless client_id
    redirect_uri = ENV['YOUTUBE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3001/youtube/callback' : 'https://social-rotation-frontend.onrender.com/youtube/callback')
    
    oauth_url = "https://accounts.google.com/o/oauth2/v2/auth?" \
                "client_id=#{client_id}" \
                "&redirect_uri=#{CGI.escape(redirect_uri)}" \
                "&response_type=code" \
                "&scope=#{CGI.escape('https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube')}" \
                "&access_type=offline" \
                "&state=#{state}"
    
    render json: { oauth_url: oauth_url }
  end
  
  # GET /api/v1/oauth/youtube/callback
  def youtube_callback
    code = params[:code]
    state = params[:state]
    
    if state != session[:oauth_state]
      return redirect_to "#{frontend_url}/profile?error=invalid_state"
    end
    
    user_id = session[:user_id]
    user = User.find_by(id: user_id)
    
    unless user
      return redirect_to "#{frontend_url}/profile?error=user_not_found"
    end
    
    # Exchange code for access token
    client_id = ENV['YOUTUBE_CLIENT_ID']
    raise 'YouTube Client ID not configured' unless client_id
    client_secret = ENV['YOUTUBE_CLIENT_SECRET']
    raise 'YouTube Client Secret not configured' unless client_secret
    redirect_uri = ENV['YOUTUBE_CALLBACK'] || (Rails.env.development? ? 'http://localhost:3001/youtube/callback' : 'https://social-rotation-frontend.onrender.com/youtube/callback')
    
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
        
        redirect_to "#{frontend_url}/profile?success=youtube_connected"
      else
        redirect_to "#{frontend_url}/profile?error=youtube_auth_failed"
      end
    rescue => e
      Rails.logger.error "YouTube OAuth error: #{e.message}"
      redirect_to "#{frontend_url}/profile?error=youtube_auth_failed"
    end
  end
end

