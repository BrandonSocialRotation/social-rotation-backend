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
        allow(::OAuth::Consumer).to receive(:new).and_return(consumer_double)
        allow(consumer_double).to receive(:get_request_token).and_return(request_token_double)
        allow(request_token_double).to receive(:token).and_return('req_token')
        allow(request_token_double).to receive(:secret).and_return('req_secret')
        allow(request_token_double).to receive(:authorize_url).and_return('https://api.twitter.com/oauth/authorize')
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
      before { session[:user_id] = user.id }

      it 'handles missing oauth_verifier' do
        get :twitter_callback, params: { oauth_token: 'test' }
        expect(response).to have_http_status(:redirect)
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
    end
  end
end
