require 'rails_helper'

RSpec.describe OauthService do
  describe '#store_state error handling' do
    let(:service) { OauthService.new(:facebook, 'http://localhost:3000') }
    
    context 'when OauthRequestToken.create raises exception' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(true)
        allow(OauthRequestToken).to receive(:create!).and_raise(StandardError.new('Database error'))
        allow(Rails.logger).to receive(:error)
      end
      
      it 'handles exception and logs error' do
        service.store_state('token', 'secret', 1)
        expect(Rails.logger).to have_received(:error).with(match(/Facebook OAuth - failed to store state/))
      end
    end
  end
  let(:user) { create(:user) }
  let(:request_base_url) { 'https://example.com' }

  describe '#initialize' do
    it 'initializes with valid platform' do
      service = OauthService.new(:facebook, request_base_url)
      expect(service).to be_a(OauthService)
    end

    it 'raises error for unknown platform' do
      expect { OauthService.new(:unknown_platform, request_base_url) }.to raise_error(/Unknown platform/)
    end
  end

  describe '#generate_state' do
    it 'generates state with user_id and random token' do
      service = OauthService.new(:facebook, request_base_url)
      state = service.generate_state(user.id)
      expect(state).to include(user.id.to_s)
      expect(state).to include(':')
    end
  end

  describe '#store_state' do
    it 'stores state in database when table exists' do
      service = OauthService.new(:facebook, request_base_url)
      expect {
        service.store_state('token123', 'secret123', user.id)
      }.to change(OauthRequestToken, :count).by(1)
    end

    it 'handles errors gracefully when table does not exist' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)
      service = OauthService.new(:facebook, request_base_url)
      expect { service.store_state('token123', 'secret123', user.id) }.not_to raise_error
    end
  end

  describe '#decode_state' do
    it 'returns user_id and random_state when state includes colon' do
      service = OauthService.new(:facebook, request_base_url)
      user_id, random_state = service.decode_state("123:abc")
      expect(user_id).to eq(123)
      expect(random_state).to eq('abc')
    end

    it 'returns nil, state when state does not include colon' do
      service = OauthService.new(:facebook, request_base_url)
      user_id, state = service.decode_state("nostate")
      expect(user_id).to be_nil
      expect(state).to eq('nostate')
    end

    it 'returns nil, nil when state is blank' do
      service = OauthService.new(:facebook, request_base_url)
      user_id, state = service.decode_state(nil)
      expect(user_id).to be_nil
      expect(state).to be_nil
    end
  end

  describe '#verify_state' do
    let(:service) { OauthService.new(:facebook, request_base_url) }

    it 'verifies state from database when available' do
      state = service.generate_state(user.id)
      # The state format is "user_id:random_state"
      # generate_state stores: oauth_token=random_state, request_secret=full_state
      # verify_state looks up by random_state and compares full state_param with stored request_secret
      user_id, verified_state = service.verify_state(state)
      expect(user_id).to eq(user.id)
      expect(verified_state).to eq(state)
    end

    it 'verifies state from session when database not available' do
      session_state = 'session_state_123'
      state_param = "#{user.id}:#{session_state}"
      # The method now compares full state_param with stored_state, so session_state should be the full state
      user_id, verified_state = service.verify_state(state_param, state_param)
      expect(user_id).to eq(user.id)
      expect(verified_state).to eq(state_param)
    end

    it 'returns nil, nil when state does not match' do
      state_param = "#{user.id}:wrong_state"
      session_state = 'correct_state'
      user_id, verified_state = service.verify_state(state_param, session_state)
      expect(user_id).to be_nil
      expect(verified_state).to be_nil
    end

    it 'handles state without colon' do
      session_state = 'simple_state'
      user_id, verified_state = service.verify_state(session_state, session_state)
      expect(user_id).to be_nil
      expect(verified_state).to eq(session_state)
    end
  end

  describe '#build_auth_url' do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it 'returns nil when client_id is not set' do
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return(nil)
      service = OauthService.new(:facebook, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to be_nil
    end

    it 'builds Facebook auth URL' do
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return('fb_app_id')
      service = OauthService.new(:facebook, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('facebook.com')
      expect(url).to include('fb_app_id')
    end

    it 'builds LinkedIn auth URL' do
      allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_ID').and_return('li_client_id')
      allow(ENV).to receive(:[]).with('LINKEDIN_CALLBACK').and_return(nil)
      service = OauthService.new(:linkedin, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('linkedin.com')
      expect(url).to include('li_client_id')
    end

    it 'builds Google auth URL' do
      allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('google_client_id')
      allow(ENV).to receive(:[]).with('GOOGLE_CALLBACK').and_return(nil)
      service = OauthService.new(:google, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('accounts.google.com')
      expect(url).to include('google_client_id')
    end

    it 'builds TikTok auth URL' do
      allow(ENV).to receive(:[]).with('TIKTOK_CLIENT_KEY').and_return('tiktok_key')
      allow(ENV).to receive(:[]).with('TIKTOK_CALLBACK').and_return(nil)
      service = OauthService.new(:tiktok, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('tiktok.com')
      expect(url).to include('tiktok_key')
    end

    it 'builds YouTube auth URL' do
      allow(ENV).to receive(:[]).with('YOUTUBE_CLIENT_ID').and_return('youtube_client_id')
      allow(ENV).to receive(:[]).with('YOUTUBE_CALLBACK').and_return(nil)
      service = OauthService.new(:youtube, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('accounts.google.com')
      expect(url).to include('youtube_client_id')
    end

    it 'builds Pinterest auth URL' do
      allow(ENV).to receive(:[]).with('PINTEREST_CLIENT_ID').and_return('pinterest_client_id')
      allow(ENV).to receive(:[]).with('PINTEREST_CALLBACK').and_return(nil)
      service = OauthService.new(:pinterest, request_base_url)
      url = service.build_auth_url(user.id, {})
      expect(url).to include('pinterest.com')
      expect(url).to include('pinterest_client_id')
    end

    it 'uses ENV callback URL when set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_ID').and_return('li_client_id')
      allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_SECRET').and_return('li_secret')
      allow(ENV).to receive(:[]).with('LINKEDIN_CALLBACK').and_return('https://custom.com/callback')
      service = OauthService.new(:linkedin, request_base_url)
      url = service.build_auth_url(user.id, {})
      # The URL should use the custom callback if ENV is set
      # The redirect_uri parameter is URL-encoded, so check for the encoded version
      expect(URI.decode_www_form_component(url)).to include('custom.com/callback')
    end
  end

  describe '#exchange_code_for_token' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      stub_request(:get, /graph\.facebook\.com/).to_return(status: 200, body: '{"access_token":"token123"}')
      stub_request(:post, /linkedin\.com/).to_return(status: 200, body: '{"access_token":"token123"}')
      stub_request(:post, /oauth2\.googleapis\.com/).to_return(status: 200, body: '{"access_token":"token123"}')
      stub_request(:post, /tiktokapis\.com/).to_return(status: 200, body: '{"access_token":"token123"}')
      stub_request(:post, /api\.pinterest\.com/).to_return(status: 200, body: '{"access_token":"token123"}')
    end

    it 'exchanges code for Facebook token' do
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return('fb_app_id')
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_SECRET').and_return('fb_secret')
      service = OauthService.new(:facebook, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_present
    end

    it 'exchanges code for LinkedIn token' do
      allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_ID').and_return('li_client_id')
      allow(ENV).to receive(:[]).with('LINKEDIN_CLIENT_SECRET').and_return('li_secret')
      service = OauthService.new(:linkedin, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_present
    end

    it 'exchanges code for Google token' do
      allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('google_client_id')
      allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return('google_secret')
      service = OauthService.new(:google, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_present
    end

    it 'exchanges code for TikTok token' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TIKTOK_CLIENT_KEY').and_return('tiktok_key')
      # TikTok doesn't use env_client_secret (it's nil in config), so don't stub it
      # The code checks @platform == :tiktok || client_secret, so TikTok works without secret
      stub_request(:post, /tiktokapis\.com/)
        .to_return(status: 200, body: '{"access_token":"token123","refresh_token":"refresh123"}')
      service = OauthService.new(:tiktok, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_present
    end

    it 'exchanges code for Pinterest token' do
      allow(ENV).to receive(:[]).with('PINTEREST_CLIENT_ID').and_return('pinterest_client_id')
      allow(ENV).to receive(:[]).with('PINTEREST_CLIENT_SECRET').and_return('pinterest_secret')
      service = OauthService.new(:pinterest, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_present
    end

    it 'returns nil when client_id is missing' do
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return(nil)
      service = OauthService.new(:facebook, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_nil
    end

    it 'returns nil when client_secret is missing (except TikTok)' do
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_ID').and_return('fb_app_id')
      allow(ENV).to receive(:[]).with('FACEBOOK_APP_SECRET').and_return(nil)
      service = OauthService.new(:facebook, request_base_url)
      response = service.exchange_code_for_token('code123')
      expect(response).to be_nil
    end
  end

  describe '#default_callback_url' do
    it 'returns localhost URL in development' do
      allow(Rails.env).to receive(:development?).and_return(true)
      service = OauthService.new(:facebook, request_base_url)
      url = service.default_callback_url
      expect(url).to include('localhost:3000')
      expect(url).to include('/api/v1/oauth/facebook/callback')
    end

    it 'uses request_base_url in production' do
      allow(Rails.env).to receive(:development?).and_return(false)
      service = OauthService.new(:facebook, request_base_url)
      url = service.default_callback_url
      expect(url).to eq("#{request_base_url}/api/v1/oauth/facebook/callback")
    end
  end
end
