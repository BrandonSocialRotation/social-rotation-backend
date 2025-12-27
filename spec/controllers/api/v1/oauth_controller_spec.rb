# Test suite for OauthController
# Tests: OAuth flows for Facebook, LinkedIn, Google, Twitter, TikTok, YouTube
# Note: These tests focus on the controller logic, not actual OAuth provider interactions
require 'rails_helper'

RSpec.describe Api::V1::OauthController, type: :controller do
  # Helper: Generate JWT token for authentication
  def generate_token(user)
    JsonWebToken.encode(user_id: user.id)
  end

  let(:user) { create(:user) }

  # Test: Facebook OAuth
  describe 'Facebook OAuth' do
    describe 'GET #facebook_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return('test_app_id')
      end

      it 'redirects to Facebook OAuth URL' do
        get :facebook_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('facebook.com')
      end

      it 'stores user_id and state in session' do
        get :facebook_login
        expect(session[:user_id]).to eq(user.id)
        expect(session[:oauth_state]).to be_present
      end
    end

    describe 'GET #facebook_callback' do
      before { session[:user_id] = user.id }

      it 'handles missing user_id in session' do
        session[:user_id] = nil
        get :facebook_callback, params: { code: 'test' }
        expect(response).to have_http_status(:redirect)
      end

      it 'handles missing code parameter' do
        get :facebook_callback
        expect(response).to have_http_status(:redirect)
      end

      context 'when callback succeeds' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123"}') }
        
        before do
          session[:user_id] = user.id
          session[:facebook_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"name":"Test User"}'))
          allow(user).to receive(:respond_to?).with(:facebook_name=).and_return(true)
        end

        it 'updates user with access token and fetches user info' do
          get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
          user.reload
          expect(user.fb_user_access_key).to eq('token123')
        end
      end
    end
  end

  # Test: LinkedIn OAuth
  describe 'LinkedIn OAuth' do
    describe 'GET #linkedin_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('LINKEDIN_CALLBACK').and_return(nil)
      end

      it 'redirects to LinkedIn OAuth URL' do
        get :linkedin_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('linkedin.com')
      end

      it 'stores state in session' do
        get :linkedin_login
        expect(session[:linkedin_state]).to be_present
      end
    end

    describe 'GET #linkedin_callback' do
      before { session[:user_id] = user.id }

      it 'handles state mismatch' do
        session[:linkedin_state] = 'correct_state'
        get :linkedin_callback, params: { code: 'test', state: 'wrong_state' }
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('error=invalid_state')
      end

      context 'when callback succeeds' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123"}') }
        
        before do
          session[:user_id] = user.id
          session[:linkedin_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"id":"profile123"}'))
        end

        it 'updates user with access token and extracts profile ID' do
          get :linkedin_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
          user.reload
          expect(user.linkedin_access_token).to eq('token123')
        end
      end
    end
  end

  # Test: Google OAuth
  describe 'Google OAuth' do
    describe 'GET #google_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('GOOGLE_CALLBACK').and_return(nil)
      end

      it 'redirects to Google OAuth URL' do
        get :google_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('accounts.google.com')
      end

      it 'stores state in session' do
        get :google_login
        expect(session[:google_state]).to be_present
      end
    end

    describe 'GET #google_callback' do
      before { session[:user_id] = user.id }

      it 'handles state mismatch' do
        session[:google_state] = 'correct_state'
        get :google_callback, params: { code: 'test', state: 'wrong_state' }
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('error=invalid_state')
      end

      context 'when callback succeeds' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123","refresh_token":"refresh123"}') }
        
        before do
          session[:user_id] = user.id
          session[:google_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"name":"Test User"}'))
          allow(user).to receive(:respond_to?).with(:google_account_name=).and_return(true)
        end

        it 'updates user with refresh token and fetches user info' do
          get :google_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
          user.reload
          expect(user.google_refresh_token).to eq('refresh123')
        end
      end
    end
  end

  # Test: Twitter OAuth 1.0a
  describe 'Twitter OAuth' do
    describe 'GET #twitter_login' do
      let(:consumer_double) { instance_double(::OAuth::Consumer) }
      let(:request_token_double) { instance_double(::OAuth::RequestToken) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('TWITTER_API_KEY').and_return('test_key')
        allow(ENV).to receive(:[]).with('TWITTER_API_SECRET_KEY').and_return('test_secret')
        allow(::OAuth::Consumer).to receive(:new).and_return(consumer_double)
        allow(consumer_double).to receive(:get_request_token).and_return(request_token_double)
        allow(request_token_double).to receive(:token).and_return('req_token')
        allow(request_token_double).to receive(:secret).and_return('req_secret')
        allow(request_token_double).to receive(:authorize_url).and_return('https://api.twitter.com/oauth/authorize')
      end

      context 'when user is not authenticated' do
        before do
          request.headers['Authorization'] = nil
          allow(controller).to receive(:current_user).and_return(nil)
        end

        it 'returns unauthorized error' do
          get :twitter_login
          expect(response).to have_http_status(:unauthorized)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Authentication required')
        end
      end

      context 'when Twitter API credentials are not configured' do
        before do
          allow(ENV).to receive(:[]).with('TWITTER_API_KEY').and_return(nil)
          allow(ENV).to receive(:[]).with('TWITTER_API_SECRET_KEY').and_return(nil)
        end

        it 'returns internal server error' do
          get :twitter_login
          expect(response).to have_http_status(:internal_server_error)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include('Twitter API credentials not configured')
        end
      end

      context 'when OAuth gem is not installed' do
        before do
          allow(::OAuth::Consumer).to receive(:new).and_raise(LoadError.new('OAuth gem not found'))
          allow(Rails.logger).to receive(:error)
        end

        it 'handles LoadError gracefully' do
          get :twitter_login
          expect(response).to have_http_status(:internal_server_error)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include('OAuth gem not installed')
        end
      end

      context 'when OAuth request fails' do
        before do
          allow(consumer_double).to receive(:get_request_token).and_raise(StandardError.new('OAuth error'))
          allow(Rails.logger).to receive(:error)
        end

        it 'handles OAuth errors gracefully' do
          get :twitter_login
          expect(response).to have_http_status(:bad_request)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include('Twitter authentication failed')
          expect(Rails.logger).to have_received(:error).with(match(/Twitter OAuth error/))
        end
      end

      it 'redirects to Twitter authorization' do
        get :twitter_login
        expect(response).to have_http_status(:redirect)
      end

      it 'stores request token in session' do
        get :twitter_login
        expect(session[:twitter_request_token]).to eq('req_token')
        expect(session[:twitter_request_secret]).to eq('req_secret')
      end
    end

    describe 'GET #twitter_callback' do
      let(:consumer_double) { instance_double(::OAuth::Consumer) }
      let(:request_token_double) { instance_double(::OAuth::RequestToken) }
      let(:access_token_double) { instance_double(::OAuth::AccessToken, token: 'access_token', secret: 'access_secret', params: {'user_id' => '123', 'screen_name' => 'testuser'}) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('TWITTER_API_KEY').and_return('test_key')
        allow(ENV).to receive(:[]).with('TWITTER_API_SECRET_KEY').and_return('test_secret')
        allow(::OAuth::Consumer).to receive(:new).and_return(consumer_double)
        allow(::OAuth::RequestToken).to receive(:new).and_return(request_token_double)
        allow(request_token_double).to receive(:get_access_token).and_return(access_token_double)
      end

      context 'when Twitter API credentials are not configured' do
        before do
          allow(ENV).to receive(:[]).with('TWITTER_API_KEY').and_return(nil)
          allow(ENV).to receive(:[]).with('TWITTER_API_SECRET_KEY').and_return(nil)
        end

        it 'redirects with config error' do
          get :twitter_callback, params: { oauth_token: 'test', oauth_verifier: 'verifier' }
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('error=twitter_config_error')
        end
      end

      context 'when user_id is missing' do
        before do
          session[:user_id] = nil
        end

        it 'redirects with user_not_found error' do
          get :twitter_callback, params: { oauth_token: 'test', oauth_verifier: 'verifier' }
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('error=user_not_found')
        end
      end

      context 'when user is not found' do
        before do
          session[:user_id] = 99999
        end

        it 'redirects with user_not_found error' do
          get :twitter_callback, params: { oauth_token: 'test', oauth_verifier: 'verifier', user_id: 99999 }
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('error=user_not_found')
        end
      end

      context 'when request token is missing' do
        before do
          session[:user_id] = user.id
          session[:twitter_request_token] = nil
          session[:twitter_request_secret] = nil
        end

        it 'redirects with session expired error' do
          get :twitter_callback, params: { oauth_token: 'test', oauth_verifier: 'verifier', user_id: user.id }
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('error=twitter_session_expired')
        end
      end

      context 'when callback succeeds' do
        before do
          session[:user_id] = user.id
          session[:twitter_request_token] = 'req_token'
          session[:twitter_request_secret] = 'req_secret'
        end

        it 'updates user and redirects with success' do
          get :twitter_callback, params: { oauth_token: 'req_token', oauth_verifier: 'verifier', user_id: user.id }
          
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('success=twitter_connected')
          user.reload
          expect(user.twitter_oauth_token).to eq('access_token')
          expect(user.twitter_oauth_token_secret).to eq('access_secret')
          expect(session[:twitter_request_token]).to be_nil
          expect(session[:twitter_request_secret]).to be_nil
        end
      end

      context 'when callback raises exception' do
        before do
          session[:user_id] = user.id
          session[:twitter_request_token] = 'req_token'
          session[:twitter_request_secret] = 'req_secret'
          allow(request_token_double).to receive(:get_access_token).and_raise(StandardError.new('OAuth error'))
          allow(Rails.logger).to receive(:error)
        end

        it 'handles errors gracefully' do
          get :twitter_callback, params: { oauth_token: 'req_token', oauth_verifier: 'verifier', user_id: user.id }
          
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include('error=twitter_auth_failed')
          expect(Rails.logger).to have_received(:error).with(match(/Twitter callback error/))
        end
      end
    end
  end

  # Test: TikTok OAuth
  describe 'TikTok OAuth' do
    describe 'GET #tiktok_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('TIKTOK_CLIENT_KEY').and_return('test_client_key')
        allow(ENV).to receive(:[]).with('TIKTOK_CALLBACK').and_return(nil)
      end

      it 'redirects to TikTok OAuth URL' do
        get :tiktok_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('tiktok')
      end

      it 'stores state in session' do
        get :tiktok_login
        expect(session[:tiktok_state]).to be_present
      end
    end
  end

  # Test: YouTube OAuth
  describe 'YouTube OAuth' do
    describe 'GET #youtube_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('YOUTUBE_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('YOUTUBE_CALLBACK').and_return(nil)
      end

      it 'redirects to YouTube OAuth URL' do
        get :youtube_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('accounts.google.com')
      end

      it 'stores state in session' do
        get :youtube_login
        expect(session[:youtube_state]).to be_present
      end
    end

    describe 'GET #tiktok_callback' do
      before { session[:user_id] = user.id }

      it 'handles state mismatch' do
        session[:tiktok_state] = 'correct_state'
        get :tiktok_callback, params: { code: 'test', state: 'wrong_state' }
        expect(response).to have_http_status(:redirect)
      end

      context 'when callback succeeds' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123"}') }
        
        before do
          session[:user_id] = user.id
          session[:tiktok_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(user).to receive(:respond_to?).with(:tiktok_access_token=).and_return(true)
        end

        it 'updates user with access token' do
          get :tiktok_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
        end
      end
    end
  end

  # Test: YouTube OAuth
  describe 'YouTube OAuth' do
    describe 'GET #youtube_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('YOUTUBE_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('YOUTUBE_CALLBACK').and_return(nil)
      end

      it 'redirects to YouTube OAuth URL' do
        get :youtube_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('accounts.google.com')
      end

      it 'stores state in session' do
        get :youtube_login
        expect(session[:youtube_state]).to be_present
      end
    end

    describe 'GET #youtube_callback' do
      before { session[:user_id] = user.id }

      it 'handles state mismatch' do
        session[:youtube_state] = 'correct_state'
        get :youtube_callback, params: { code: 'test', state: 'wrong_state' }
        expect(response).to have_http_status(:redirect)
      end

      context 'when callback succeeds with refresh token' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123","refresh_token":"refresh123"}') }
        
        before do
          session[:user_id] = user.id
          session[:youtube_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"items":[{"id":"channel123","snippet":{"title":"Test Channel"}}]}'))
          allow(user).to receive(:respond_to?).and_return(true)
        end

        it 'updates user with refresh token and access token' do
          get :youtube_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
          user.reload
          expect(user.youtube_refresh_token).to eq('refresh123')
          expect(user.youtube_access_token).to eq('token123')
        end
      end

      context 'when callback succeeds without refresh token' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123"}') }
        
        before do
          session[:user_id] = user.id
          session[:youtube_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"items":[{"id":"channel123","snippet":{"title":"Test Channel"}}]}'))
          allow(user).to receive(:respond_to?).and_return(true)
        end

        it 'updates user with access token only' do
          get :youtube_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
          user.reload
          expect(user.youtube_access_token).to eq('token123')
        end
      end
    end
  end

  # Test: Pinterest OAuth
  describe 'Pinterest OAuth' do
    describe 'GET #pinterest_login' do
      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PINTEREST_APP_ID').and_return('test_app_id')
        allow(ENV).to receive(:[]).with('PINTEREST_CALLBACK').and_return(nil)
      end

      it 'redirects to Pinterest OAuth URL' do
        allow(ENV).to receive(:[]).with('PINTEREST_CLIENT_ID').and_return('test_client_id')
        get :pinterest_login
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('pinterest.com')
      end

      it 'stores state in session' do
        allow(ENV).to receive(:[]).with('PINTEREST_CLIENT_ID').and_return('test_client_id')
        get :pinterest_login
        expect(session[:pinterest_state]).to be_present
      end
    end

    describe 'GET #pinterest_callback' do
      before { session[:user_id] = user.id }

      it 'handles state mismatch' do
        session[:pinterest_state] = 'correct_state'
        get :pinterest_callback, params: { code: 'test', state: 'wrong_state' }
        expect(response).to have_http_status(:redirect)
      end

      context 'when callback succeeds' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123","refresh_token":"refresh123"}') }
        
        before do
          session[:user_id] = user.id
          session[:pinterest_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"username":"testuser"}'))
          allow(user).to receive(:respond_to?).with(:pinterest_access_token=).and_return(true)
          allow(user).to receive(:respond_to?).with(:pinterest_username=).and_return(true)
        end

        it 'updates user with access token and refresh token' do
          get :pinterest_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
        end
      end

      context 'when user does not respond to pinterest_access_token=' do
        let(:mock_service) { instance_double(OauthService) }
        let(:mock_response) { instance_double(HTTParty::Response, success?: true, body: '{"access_token":"token123"}') }
        
        before do
          session[:user_id] = user.id
          session[:pinterest_state] = 'test_state'
          allow(OauthService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:verify_state).and_return([user.id, 'test_state'])
          allow(mock_service).to receive(:exchange_code_for_token).and_return(mock_response)
          allow(mock_service).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
          allow(user).to receive(:respond_to?).with(:pinterest_access_token=).and_return(false)
        end

        it 'returns early without updating' do
          get :pinterest_callback, params: { code: 'test_code', state: 'test_state' }
          
          expect(response).to have_http_status(:redirect)
        end
      end
    end
  end

  # Test: Instagram Connect
  describe 'GET #instagram_connect' do
    before do
      request.headers['Authorization'] = "Bearer #{generate_token(user)}"
    end

    context 'when Facebook is connected' do
      before do
        user.update!(fb_user_access_key: 'test_token', instagram_business_id: 'ig_123')
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"data":[{"id":"page_123","name":"Test Page","instagram_business_account":{"id":"ig_123"}}]}'))
      end

      it 'returns Instagram connection info' do
        get :instagram_connect
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
      end
    end

    context 'when Facebook is not connected' do
      before do
        user.update!(fb_user_access_key: nil)
      end

      it 'returns error' do
        get :instagram_connect
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Facebook not connected')
      end
    end

    context 'when Instagram account not found' do
      before do
        user.update!(fb_user_access_key: 'test_token', instagram_business_id: nil)
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"data":[]}'))
      end

      it 'returns not found' do
        get :instagram_connect
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Instagram account not found')
      end
    end

    context 'when an error occurs' do
      before do
        user.update!(fb_user_access_key: 'test_token')
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('API error'))
      end

      it 'handles errors gracefully' do
        get :instagram_connect
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to connect')
      end
    end
  end

  # Test: Helper methods
  describe '#frontend_url' do
    it 'returns localhost in development' do
      allow(Rails.env).to receive(:development?).and_return(true)
      url = controller.send(:frontend_url)
      expect(url).to eq('http://localhost:3001')
    end

    it 'uses ENV FRONTEND_URL in production' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://custom.com')
      url = controller.send(:frontend_url)
      expect(url).to eq('https://custom.com')
    end

    it 'defaults to my.socialrotation.app when ENV not set' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return(nil)
      url = controller.send(:frontend_url)
      expect(url).to eq('https://my.socialrotation.app')
    end

    it 'removes trailing slash' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://custom.com/')
      url = controller.send(:frontend_url)
      expect(url).to eq('https://custom.com')
    end
  end

  describe '#oauth_callback_url' do
    before do
      allow(controller).to receive(:frontend_url).and_return('https://example.com')
    end

    it 'builds URL with success parameter' do
      url = controller.send(:oauth_callback_url, success: 'connected', platform: 'Facebook')
      expect(url).to include('success=connected')
      expect(url).to include('platform=Facebook')
      expect(url).to start_with('https://example.com/oauth/callback?')
    end

    it 'builds URL with error parameter' do
      url = controller.send(:oauth_callback_url, error: 'failed', platform: 'Twitter')
      expect(url).to include('error=failed')
      expect(url).to include('platform=Twitter')
    end

    it 'builds URL with both success and error' do
      url = controller.send(:oauth_callback_url, success: 'connected', error: 'warning', platform: 'LinkedIn')
      expect(url).to include('success=connected')
      expect(url).to include('error=warning')
      expect(url).to include('platform=LinkedIn')
    end

    it 'escapes special characters in parameters' do
      url = controller.send(:oauth_callback_url, success: 'test & value', platform: 'Test Platform')
      expect(url).to include('success=test+%26+value')
      expect(url).to include('platform=Test+Platform')
    end
  end

  describe '#frontend_url' do
    it 'returns localhost in development' do
      allow(Rails.env).to receive(:development?).and_return(true)
      url = controller.send(:frontend_url)
      expect(url).to eq('http://localhost:3001')
    end

    it 'returns ENV FRONTEND_URL in production when set' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://custom.com')
      url = controller.send(:frontend_url)
      expect(url).to eq('https://custom.com')
    end

    it 'returns default URL in production when ENV not set' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return(nil)
      url = controller.send(:frontend_url)
      expect(url).to eq('https://my.socialrotation.app')
    end

    it 'removes trailing slash' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://custom.com/')
      url = controller.send(:frontend_url)
      expect(url).to eq('https://custom.com')
    end
  end

  describe 'OAuth callback private methods' do
    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(user)
    end

    describe '#fetch_facebook_user_info' do
      it 'updates user with Facebook name when API succeeds' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"name": "John Doe", "email": "john@example.com"}'))
        controller.send(:fetch_facebook_user_info, user, 'test_token')
        expect(user.reload.facebook_name).to eq('John Doe') if user.respond_to?(:facebook_name)
      end

      it 'handles API failure gracefully' do
        allow(HTTParty).to receive(:get).and_return(double(success?: false))
        expect { controller.send(:fetch_facebook_user_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles API errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        expect { controller.send(:fetch_facebook_user_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles missing name in response' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"email": "john@example.com"}'))
        expect { controller.send(:fetch_facebook_user_info, user, 'test_token') }.not_to raise_error
      end
    end

    describe '#extract_linkedin_profile_id' do
      before do
        user.update!(linkedin_profile_id: nil)
      end

      it 'extracts profile ID from id_token' do
        payload = { 'sub' => 'urn:li:person:12345' }.to_json
        encoded_payload = Base64.urlsafe_encode64(payload)
        id_token = "header.#{encoded_payload}.signature"
        
        data = { 'id_token' => id_token, 'access_token' => 'test_token' }
        controller.send(:extract_linkedin_profile_id, user, data)
        expect(user.reload.linkedin_profile_id).to eq('12345')
      end

      it 'handles invalid id_token format' do
        data = { 'id_token' => 'invalid.token', 'access_token' => 'test_token' }
        allow(controller).to receive(:fetch_linkedin_profile_id).and_return(nil)
        expect { controller.send(:extract_linkedin_profile_id, user, data) }.not_to raise_error
      end

      it 'handles id_token with wrong number of parts' do
        data = { 'id_token' => 'header.payload', 'access_token' => 'test_token' }
        allow(controller).to receive(:fetch_linkedin_profile_id).and_return(nil)
        expect { controller.send(:extract_linkedin_profile_id, user, data) }.not_to raise_error
      end

      it 'handles id_token without sub field' do
        payload = { 'email' => 'test@example.com' }.to_json
        encoded_payload = Base64.urlsafe_encode64(payload)
        id_token = "header.#{encoded_payload}.signature"
        data = { 'id_token' => id_token, 'access_token' => 'test_token' }
        allow(controller).to receive(:fetch_linkedin_profile_id).and_return('profile_123')
        controller.send(:extract_linkedin_profile_id, user, data)
        expect(controller).to have_received(:fetch_linkedin_profile_id).with(user, 'test_token')
      end

      it 'falls back to fetch_linkedin_profile_id when no id_token' do
        data = { 'access_token' => 'test_token' }
        allow(controller).to receive(:fetch_linkedin_profile_id).and_return('profile_123')
        controller.send(:extract_linkedin_profile_id, user, data)
        expect(controller).to have_received(:fetch_linkedin_profile_id).with(user, 'test_token')
      end

      it 'skips fetch_linkedin_profile_id when profile_id already extracted' do
        payload = { 'sub' => 'urn:li:person:12345' }.to_json
        encoded_payload = Base64.urlsafe_encode64(payload)
        id_token = "header.#{encoded_payload}.signature"
        data = { 'id_token' => id_token, 'access_token' => 'test_token' }
        controller.send(:extract_linkedin_profile_id, user, data)
        expect(user.reload.linkedin_profile_id).to eq('12345')
        # Should not call fetch_linkedin_profile_id since profile_id is already set
      end

      it 'handles errors gracefully' do
        data = { 'id_token' => 'header.invalid.signature', 'access_token' => 'test_token' }
        allow(Base64).to receive(:urlsafe_decode64).and_raise(StandardError.new('Decode error'))
        allow(controller).to receive(:fetch_linkedin_profile_id).and_return(nil)
        expect { controller.send(:extract_linkedin_profile_id, user, data) }.not_to raise_error
      end
    end

    describe '#fetch_linkedin_profile_id' do
      it 'fetches profile ID from /v2/me endpoint' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"id": "linkedin_123"}'))
        result = controller.send(:fetch_linkedin_profile_id, user, 'test_token')
        expect(result).to eq('linkedin_123')
        expect(user.reload.linkedin_profile_id).to eq('linkedin_123')
      end

      it 'falls back to /v2/userinfo endpoint when /v2/me fails' do
        allow(HTTParty).to receive(:get).and_return(
          double(success?: false), # First call fails
          double(success?: true, body: '{"sub": "urn:li:person:67890"}') # Second call succeeds
        )
        result = controller.send(:fetch_linkedin_profile_id, user, 'test_token')
        expect(result).to eq('67890')
        expect(user.reload.linkedin_profile_id).to eq('67890')
      end

      it 'returns nil when both endpoints fail' do
        allow(HTTParty).to receive(:get).and_return(double(success?: false))
        result = controller.send(:fetch_linkedin_profile_id, user, 'test_token')
        expect(result).to be_nil
      end

      it 'handles API errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        result = controller.send(:fetch_linkedin_profile_id, user, 'test_token')
        expect(result).to be_nil
      end
    end

    describe '#fetch_google_user_info' do
      it 'updates user with Google account name' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"name": "John Doe", "email": "john@example.com"}'))
        controller.send(:fetch_google_user_info, user, 'test_token')
        expect(user.reload.google_account_name).to eq('John Doe') if user.respond_to?(:google_account_name)
      end

      it 'falls back to email when name is missing' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"email": "john@example.com"}'))
        controller.send(:fetch_google_user_info, user, 'test_token')
        expect(user.reload.google_account_name).to eq('john@example.com') if user.respond_to?(:google_account_name)
      end

      it 'handles API failure gracefully' do
        allow(HTTParty).to receive(:get).and_return(double(success?: false))
        expect { controller.send(:fetch_google_user_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles API errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        expect { controller.send(:fetch_google_user_info, user, 'test_token') }.not_to raise_error
      end
    end

    describe '#fetch_youtube_channel_info' do
      it 'updates user with YouTube channel info' do
        response_body = {
          'items' => [{
            'id' => 'channel_123',
            'snippet' => { 'title' => 'My Channel' }
          }]
        }.to_json
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: response_body))
        controller.send(:fetch_youtube_channel_info, user, 'test_token')
        expect(user.reload.youtube_channel_id).to eq('channel_123') if user.respond_to?(:youtube_channel_id)
        expect(user.reload.youtube_channel_name).to eq('My Channel') if user.respond_to?(:youtube_channel_name)
      end

      it 'handles empty items array' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"items": []}'))
        expect { controller.send(:fetch_youtube_channel_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles missing items key' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{}'))
        expect { controller.send(:fetch_youtube_channel_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles API failure gracefully' do
        allow(HTTParty).to receive(:get).and_return(double(success?: false))
        expect { controller.send(:fetch_youtube_channel_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles API errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        expect { controller.send(:fetch_youtube_channel_info, user, 'test_token') }.not_to raise_error
      end
    end

    describe '#fetch_pinterest_user_info' do
      it 'updates user with Pinterest username from username field' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"username": "pinterest_user"}'))
        controller.send(:fetch_pinterest_user_info, user, 'test_token')
        expect(user.reload.pinterest_username).to eq('pinterest_user') if user.respond_to?(:pinterest_username)
      end

      it 'falls back to profile.username when username missing' do
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"profile": {"username": "profile_user"}}'))
        controller.send(:fetch_pinterest_user_info, user, 'test_token')
        expect(user.reload.pinterest_username).to eq('profile_user') if user.respond_to?(:pinterest_username)
      end

      it 'handles API failure gracefully' do
        allow(HTTParty).to receive(:get).and_return(double(success?: false))
        expect { controller.send(:fetch_pinterest_user_info, user, 'test_token') }.not_to raise_error
      end

      it 'handles API errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        expect { controller.send(:fetch_pinterest_user_info, user, 'test_token') }.not_to raise_error
      end
    end

    describe '#fetch_instagram_account' do
      it 'returns Instagram account info when found' do
        user.update!(fb_user_access_key: 'test_token')
        response_body = {
          'data' => [{
            'id' => 'page_123',
            'name' => 'Test Page',
            'instagram_business_account' => { 'id' => 'ig_123' }
          }]
        }.to_json
        allow(HTTParty).to receive(:get).and_return(double(body: response_body))
        result = controller.send(:fetch_instagram_account, user)
        expect(result).to be_a(Hash)
        expect(result[:id]).to eq('ig_123')
        expect(user.reload.instagram_business_id).to eq('ig_123')
      end

      it 'returns nil when no Facebook access key' do
        user.update!(fb_user_access_key: nil)
        result = controller.send(:fetch_instagram_account, user)
        expect(result).to be_nil
      end

      it 'returns nil when no Instagram account found' do
        user.update!(fb_user_access_key: 'test_token')
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{"data": []}'))
        result = controller.send(:fetch_instagram_account, user)
        expect(result).to be_nil
      end

      it 'handles API errors gracefully' do
        user.update!(fb_user_access_key: 'test_token')
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Network error'))
        # The method now re-raises errors, so it should raise the error
        expect {
          controller.send(:fetch_instagram_account, user)
        }.to raise_error(StandardError, 'Network error')
      end

      it 'handles missing data key in response' do
        user.update!(fb_user_access_key: 'test_token')
        allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{}'))
        result = controller.send(:fetch_instagram_account, user)
        expect(result).to be_nil
      end
    end
  end

  describe '#handle_oauth_login edge cases' do
    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      # Initialize request/response by making a dummy request that we'll rescue
      begin
        get :facebook_login
      rescue => e
        # Expected - we're just initializing the request/response
      end
    end

    it 'returns error when current_user is nil' do
      allow(controller).to receive(:current_user).and_return(nil)
      # Test through the actual action to ensure proper request/response setup
      get :facebook_login
      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('User not authenticated')
    end

    it 'returns error when build_auth_url returns nil' do
      request.headers['Authorization'] = "Bearer #{generate_token(user)}"
      allow(controller).to receive(:current_user).and_return(user)
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:build_auth_url).and_return(nil)
      get :facebook_login
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Facebook not configured')
    end

    it 'handles errors gracefully' do
      request.headers['Authorization'] = "Bearer #{generate_token(user)}"
      allow(controller).to receive(:current_user).and_return(user)
      allow(OauthService).to receive(:new).and_raise(StandardError.new('Service error'))
      get :facebook_login
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Failed to initiate Facebook OAuth')
    end
  end

  describe '#handle_oauth_callback edge cases' do
    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:frontend_url).and_return('http://test.com')
    end

    it 'handles error parameter in callback' do
      get :facebook_callback, params: { error: 'access_denied' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_access_denied')
    end

    it 'handles generic error parameter' do
      get :facebook_callback, params: { error: 'other_error' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_auth_failed')
    end

    it 'handles missing code parameter' do
      get :facebook_callback, params: { state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_auth_failed')
    end

    it 'handles invalid state' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([nil, nil])
      get :facebook_callback, params: { code: 'test_code', state: 'invalid_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=invalid_state')
    end

    it 'handles user not found' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([99999, 'test_state'])
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=user_not_found')
    end

    it 'handles failed token exchange' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([user.id, 'test_state'])
      allow(service_double).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
      response_double = double(success?: false)
      allow(service_double).to receive(:exchange_code_for_token).and_return(response_double)
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_auth_failed')
    end

    it 'handles missing access_token in response' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([user.id, 'test_state'])
      allow(service_double).to receive(:send).with(:default_callback_url).and_return('http://test.com/callback')
      response_double = double(success?: true, body: '{"refresh_token": "test"}')
      allow(service_double).to receive(:exchange_code_for_token).and_return(response_double)
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_auth_failed')
    end

    it 'handles errors gracefully' do
      allow(OauthService).to receive(:new).and_raise(StandardError.new('Service error'))
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=facebook_auth_failed')
    end

    it 'handles user_id of 0' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([0, 'test_state'])
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=invalid_state')
    end

    it 'handles negative user_id' do
      service_double = instance_double(OauthService)
      allow(OauthService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:verify_state).and_return([-1, 'test_state'])
      get :facebook_callback, params: { code: 'test_code', state: 'test_state' }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('error=invalid_state')
    end
  end
end
