require 'rails_helper'

RSpec.describe Api::V1::UserInfoController, type: :controller do
  let(:user) { create(:user, 
    name: 'Test User',
    email: 'test@example.com',
    timezone: 'America/New_York',
    watermark_scale: 50,
    watermark_opacity: 80,
    watermark_offset_x: 10,
    watermark_offset_y: 20,
    post_to_instagram: true,
    instagram_business_id: nil,  # Explicitly set to nil for test
    fb_user_access_key: 'fb_token',
    twitter_oauth_token: 'twitter_token',
    linkedin_access_token: 'linkedin_token',
    google_refresh_token: 'google_token'
  ) }

  before do
    # Mock authentication
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'GET #show' do
    it 'returns user information and connected accounts' do
      get :show

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      
      expect(json_response['user']['id']).to eq(user.id)
      expect(json_response['user']['name']).to eq('Test User')
      expect(json_response['user']['email']).to eq('test@example.com')
      expect(json_response['user']['timezone']).to eq('America/New_York')
      
      expect(json_response['connected_accounts']).to contain_exactly(
        'google_business', 'twitter', 'facebook', 'instagram', 'linked_in'
      )
    end

    it 'shows correct social media connection status' do
      get :show

      json_response = JSON.parse(response.body)
      user_data = json_response['user']
      
      expect(user_data['facebook_connected']).to be true
      expect(user_data['twitter_connected']).to be true
      expect(user_data['linkedin_connected']).to be true
      expect(user_data['google_connected']).to be true
      expect(user_data['instagram_connected']).to be false # No instagram_business_id
    end

    it 'handles errors gracefully' do
      allow(controller).to receive(:user_json).and_raise(StandardError.new('Database error'))
      
      get :show
      
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Failed to load user info')
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        user: {
          name: 'Updated Name',
          timezone: 'America/Los_Angeles',
          post_to_instagram: false
        }
      }
    end

    it 'updates user information' do
      patch :update, params: update_params

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.name).to eq('Updated Name')
      expect(user.timezone).to eq('America/Los_Angeles')
      expect(user.post_to_instagram).to be false
    end

    it 'returns errors for invalid updates' do
      invalid_params = { user: { email: 'invalid-email' } }
      
      patch :update, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe 'POST #update_watermark' do
    let(:watermark_params) do
      {
        watermark_opacity: 90,
        watermark_scale: 75,
        watermark_offset_x: 15,
        watermark_offset_y: 25
      }
    end

    it 'updates watermark settings' do
      post :update_watermark, params: watermark_params

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.watermark_opacity).to eq(90)
      expect(user.watermark_scale).to eq(75)
      expect(user.watermark_offset_x).to eq(15)
      expect(user.watermark_offset_y).to eq(25)
    end

    it 'handles watermark logo upload' do
      logo_params = watermark_params.merge(
        watermark_logo: fixture_file_upload('test_logo.png', 'image/png')
      )

      post :update_watermark, params: logo_params

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.watermark_logo).to be_present
    end

    it 'returns errors when update fails' do
      allow(user).to receive(:update).and_return(false)
      allow(user).to receive(:errors).and_return(double(full_messages: ['Validation failed']))
      
      post :update_watermark, params: watermark_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe 'GET #debug' do
    it 'returns debug information about user account connections' do
      get :debug

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['user_id']).to eq(user.id)
      expect(json_response['email']).to eq(user.email)
      expect(json_response).to have_key('fb_user_access_key')
      expect(json_response).to have_key('twitter_oauth_token')
      expect(json_response).to have_key('linkedin_access_token')
      expect(json_response).to have_key('google_refresh_token')
      expect(json_response).to have_key('tiktok_access_token')
      expect(json_response).to have_key('youtube_access_token')
      expect(json_response).to have_key('pinterest_access_token')
      expect(json_response).to have_key('instagram_business_id')
    end

    it 'shows present for connected accounts' do
      user.update!(
        fb_user_access_key: 'test_token',
        twitter_oauth_token: 'test_token',
        linkedin_access_token: 'test_token'
      )

      get :debug

      json_response = JSON.parse(response.body)
      expect(json_response['fb_user_access_key']).to eq('present')
      expect(json_response['twitter_oauth_token']).to eq('present')
    end

    it 'shows nil for unconnected accounts' do
      user.update!(
        fb_user_access_key: nil,
        twitter_oauth_token: nil
      )

      get :debug

      json_response = JSON.parse(response.body)
      expect(json_response['fb_user_access_key']).to eq('nil')
      expect(json_response['twitter_oauth_token']).to eq('nil')
    end
  end

  describe 'GET #connected_accounts' do
    it 'returns list of connected social media accounts' do
      get :connected_accounts

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['connected_accounts']).to contain_exactly(
        'google_business', 'twitter', 'facebook', 'instagram', 'linked_in'
      )
    end

    it 'returns empty array for user with no connections' do
      user.update!(
        fb_user_access_key: nil,
        twitter_oauth_token: nil,
        linkedin_access_token: nil,
        google_refresh_token: nil,
        post_to_instagram: false
      )

      get :connected_accounts

      json_response = JSON.parse(response.body)
      expect(json_response['connected_accounts']).to be_empty
    end
  end

  describe 'POST #disconnect_facebook' do
    it 'clears Facebook connection data' do
      post :disconnect_facebook

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.fb_user_access_key).to be_nil
      expect(user.instagram_business_id).to be_nil
    end
  end

  describe 'POST #disconnect_twitter' do
    it 'clears Twitter connection data' do
      post :disconnect_twitter

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.twitter_oauth_token).to be_nil
      expect(user.twitter_oauth_token_secret).to be_nil
      expect(user.twitter_user_id).to be_nil
      expect(user.twitter_screen_name).to be_nil
    end
  end

  describe 'POST #disconnect_linkedin' do
    it 'clears LinkedIn connection data' do
      post :disconnect_linkedin

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.linkedin_access_token).to be_nil
      expect(user.linkedin_access_token_time).to be_nil
      expect(user.linkedin_profile_id).to be_nil
    end
  end

  describe 'POST #disconnect_google' do
    it 'clears Google connection data' do
      post :disconnect_google

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.google_refresh_token).to be_nil
      expect(user.location_id).to be_nil
    end
  end

  describe 'POST #disconnect_instagram' do
    before do
      user.update!(instagram_business_id: 'ig_business_123')
    end

    it 'clears Instagram connection data' do
      post :disconnect_instagram

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Instagram disconnected successfully')
      
      user.reload
      expect(user.instagram_business_id).to be_nil
    end
  end


  describe 'GET #show' do
    context 'when user has Instagram business account' do
      before do
        user.update!(instagram_business_id: 'ig_business_123', fb_user_access_key: 'fb_token')
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, body: '{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"ig_business_123"}}]}'),
          double(success?: true, body: '{"id":"ig_business_123","username":"testuser","name":"Test User"}')
        )
        allow(JSON).to receive(:parse).and_call_original
        allow(JSON).to receive(:parse).with('{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"ig_business_123"}}]}').and_return({
          'data' => [{
            'id' => 'page123',
            'access_token' => 'page_token',
            'instagram_business_account' => { 'id' => 'ig_business_123' }
          }]
        })
        allow(JSON).to receive(:parse).with('{"id":"ig_business_123","username":"testuser","name":"Test User"}').and_return({
          'id' => 'ig_business_123',
          'username' => 'testuser',
          'name' => 'Test User'
        })
      end

      it 'fetches Instagram account info' do
        get :show
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['user']['instagram_account']).to be_present
      end
    end

    context 'when Instagram account info fetch fails' do
      before do
        user.update!(instagram_business_id: 'ig_business_123', fb_user_access_key: 'fb_token')
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('API error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles errors gracefully' do
        get :show
        
        expect(response).to have_http_status(:ok)
        expect(Rails.logger).to have_received(:error).with(match(/Error fetching Instagram account info/))
      end
    end

    context 'when Instagram response is not successful' do
      before do
        user.update!(instagram_business_id: 'ig_business_123', fb_user_access_key: 'fb_token')
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, body: '{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"ig_business_123"}}]}'),
          double(success?: false, body: '{"error":"Invalid token"}')
        )
        allow(JSON).to receive(:parse).and_call_original
        allow(JSON).to receive(:parse).with('{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"ig_business_123"}}]}').and_return({
          'data' => [{
            'id' => 'page123',
            'access_token' => 'page_token',
            'instagram_business_account' => { 'id' => 'ig_business_123' }
          }]
        })
      end

      it 'returns nil for Instagram account' do
        get :show
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['user']['instagram_account']).to be_nil
      end
    end

    context 'when no matching page found, uses fallback' do
      before do
        user.update!(instagram_business_id: 'ig_business_123', fb_user_access_key: 'fb_token')
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, body: '{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"other_id"}}]}'),
          double(success?: true, body: '{"id":"ig_business_123","username":"testuser"}')
        )
        allow(JSON).to receive(:parse).and_call_original
        allow(JSON).to receive(:parse).with('{"data":[{"id":"page123","access_token":"page_token","instagram_business_account":{"id":"other_id"}}]}').and_return({
          'data' => [{
            'id' => 'page123',
            'access_token' => 'page_token',
            'instagram_business_account' => { 'id' => 'other_id' }
          }]
        })
        allow(JSON).to receive(:parse).with('{"id":"ig_business_123","username":"testuser"}').and_return({
          'id' => 'ig_business_123',
          'username' => 'testuser'
        })
      end

      it 'uses first page token as fallback' do
        get :show
        
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with different account types' do
      context 'when user has agency account' do
        let(:account) { create(:account, is_reseller: true) }
        
        before do
          user.update!(account: account)
        end

        it 'returns agency account type' do
          get :show
          
          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['user']['account_type']).to eq('agency')
        end
      end

      context 'when user has personal account (account_id 0)' do
        before do
          user.update!(account_id: 0)
        end

        it 'returns personal account type' do
          get :show
          
          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['user']['account_type']).to eq('personal')
        end
      end

      context 'when user has regular account' do
        let(:account) { create(:account, is_reseller: false) }
        
        before do
          user.update!(account: account)
        end

        it 'returns personal account type as fallback' do
          get :show
          
          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['user']['account_type']).to eq('personal')
        end
      end
    end

    context 'with YouTube account info' do
      before do
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_id: 'channel123',
          youtube_channel_name: 'My Channel'
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
      end

      it 'includes YouTube account information' do
        get :show
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        youtube_account = json_response['user']['youtube_account']
        expect(youtube_account['channel_id']).to eq('channel123')
        expect(youtube_account['channel_name']).to eq('My Channel')
      end
    end

    context 'with Pinterest account info' do
      before do
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:pinterest_access_token).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_access_token=).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_username).and_return(true)
        allow(user).to receive(:pinterest_access_token).and_return('pinterest_token')
        allow(user).to receive(:pinterest_username).and_return('pinterest_user')
      end

      it 'includes Pinterest account information' do
        get :show
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['user']['pinterest_account']['username']).to eq('pinterest_user')
      end
    end

    context 'when fetch_youtube_channel_name_if_missing is called' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_id=).and_return(true)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_return(status: 200, body: {
            items: [{
              id: 'channel123',
              snippet: {
                title: 'My YouTube Channel'
              }
            }]
          }.to_json)
        allow(Rails.logger).to receive(:info)
      end

      it 'fetches and saves YouTube channel name' do
        get :show
        
        expect(response).to have_http_status(:ok)
        expect(user.reload.youtube_channel_name).to eq('My YouTube Channel')
        expect(user.youtube_channel_id).to eq('channel123')
        expect(Rails.logger).to have_received(:info).with(match(/YouTube channel name fetched and saved/))
      end
    end

    context 'when YouTube API call fails' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_raise(StandardError.new('API error'))
        allow(Rails.logger).to receive(:warn)
      end

      it 'handles errors gracefully' do
        get :show
        
        expect(response).to have_http_status(:ok)
        expect(Rails.logger).to have_received(:warn).with(match(/Failed to fetch YouTube channel name/))
      end
    end

    context 'when YouTube API returns no items' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_return(status: 200, body: { items: [] }.to_json)
      end

      it 'does not update channel name when no items returned' do
        get :show
        
        expect(response).to have_http_status(:ok)
        expect(user.reload.youtube_channel_name).to be_nil
      end
    end

    context 'when YouTube API succeeds with items and channel_id missing' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil,
          youtube_channel_id: nil
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_id=).and_return(true)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_return(status: 200, body: {
            items: [{
              id: 'channel123',
              snippet: {
                title: 'Test Channel'
              }
            }]
          }.to_json)
        allow(Rails.logger).to receive(:info)
      end

      it 'saves channel_id and channel_name' do
        get :show
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.youtube_channel_id).to eq('channel123')
        expect(user.youtube_channel_name).to eq('Test Channel')
        expect(Rails.logger).to have_received(:info).with(match(/YouTube channel name fetched and saved/))
      end
    end

    context 'when YouTube API succeeds with items but channel_id already exists' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil,
          youtube_channel_id: 'existing_id'
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_id=).and_return(true)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_return(status: 200, body: {
            items: [{
              id: 'channel123',
              snippet: {
                title: 'Test Channel'
              }
            }]
          }.to_json)
        allow(Rails.logger).to receive(:info)
      end

      it 'saves channel_name but not channel_id' do
        get :show
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.youtube_channel_id).to eq('existing_id')
        expect(user.youtube_channel_name).to eq('Test Channel')
        expect(Rails.logger).to have_received(:info).with(match(/YouTube channel name fetched and saved/))
      end
    end

    context 'when YouTube API succeeds but user does not respond to youtube_channel_id=' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        user.update!(
          youtube_access_token: 'yt_token',
          youtube_channel_name: nil
        )
        allow(user).to receive(:respond_to?).and_call_original
        allow(user).to receive(:respond_to?).with(:youtube_channel_name).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_name=).and_return(true)
        allow(user).to receive(:respond_to?).with(:youtube_channel_id=).and_return(false)
        stub_request(:get, 'https://www.googleapis.com/youtube/v3/channels')
          .with(query: hash_including(part: 'snippet', mine: 'true'))
          .to_return(status: 200, body: {
            items: [{
              id: 'channel123',
              snippet: {
                title: 'Test Channel'
              }
            }]
          }.to_json)
        allow(Rails.logger).to receive(:info)
      end

      it 'saves channel_name only' do
        get :show
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.youtube_channel_name).to eq('Test Channel')
        expect(Rails.logger).to have_received(:info).with(match(/YouTube channel name fetched and saved/))
      end
    end
  end

  describe 'POST #toggle_instagram' do
    it 'toggles Instagram posting status' do
      post :toggle_instagram, params: { post_to_instagram: 'false' }

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.post_to_instagram).to be false
    end

    it 'enables Instagram posting' do
      user.update!(post_to_instagram: false)
      
      post :toggle_instagram, params: { post_to_instagram: 'true' }

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.post_to_instagram).to be true
    end
  end

  describe 'GET #watermark_preview' do
    it 'returns watermark preview URL' do
      get :watermark_preview

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['preview_url']).to eq('/user/standard_preview')
    end
  end

  describe 'GET #standard_preview' do
    it 'returns standard preview URL' do
      get :standard_preview

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['preview_url']).to eq('/user/standard_preview')
    end
  end

  describe 'watermark path methods' do
    it 'includes watermark path methods in user JSON' do
      get :show

      json_response = JSON.parse(response.body)
      user_data = json_response['user']
      
      expect(user_data).to have_key('watermark_preview_url')
      expect(user_data).to have_key('watermark_logo_url')
      expect(user_data).to have_key('digital_ocean_watermark_path')
    end
  end

  # Test: Social media disconnect methods
  describe 'POST #disconnect_facebook' do
    before do
      user.update!(
        fb_user_access_key: 'fb_token_123',
        instagram_business_id: 'ig_business_123'
      )
    end

    it 'disconnects Facebook and Instagram' do
      post :disconnect_facebook

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Facebook disconnected successfully')
      
      user.reload
      expect(user.fb_user_access_key).to be_nil
      expect(user.instagram_business_id).to be_nil
    end
  end

  describe 'POST #disconnect_twitter' do
    before do
      user.update!(
        twitter_oauth_token: 'twitter_token_123',
        twitter_oauth_token_secret: 'twitter_secret_123',
        twitter_user_id: 'twitter_user_123',
        twitter_screen_name: 'testuser',
        twitter_url_oauth_token: 'twitter_url_token_123',
        twitter_url_oauth_token_secret: 'twitter_url_secret_123'
      )
    end

    it 'disconnects Twitter' do
      post :disconnect_twitter

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Twitter disconnected successfully')
      
      user.reload
      expect(user.twitter_oauth_token).to be_nil
      expect(user.twitter_oauth_token_secret).to be_nil
      expect(user.twitter_user_id).to be_nil
      expect(user.twitter_screen_name).to be_nil
      expect(user.twitter_url_oauth_token).to be_nil
      expect(user.twitter_url_oauth_token_secret).to be_nil
    end
  end

  describe 'POST #disconnect_linkedin' do
    before do
      user.update!(
        linkedin_access_token: 'linkedin_token_123',
        linkedin_access_token_time: 1.hour.ago,
        linkedin_profile_id: 'linkedin_profile_123'
      )
    end

    it 'disconnects LinkedIn' do
      post :disconnect_linkedin

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('LinkedIn disconnected successfully')
      
      user.reload
      expect(user.linkedin_access_token).to be_nil
      expect(user.linkedin_access_token_time).to be_nil
      expect(user.linkedin_profile_id).to be_nil
    end
  end

  describe 'POST #disconnect_google' do
    before do
      user.update!(
        google_refresh_token: 'google_refresh_123',
        location_id: 'location_123'
      )
    end

    it 'disconnects Google My Business' do
      post :disconnect_google

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Google My Business disconnected successfully')
      
      user.reload
      expect(user.google_refresh_token).to be_nil
      expect(user.location_id).to be_nil
    end
  end

  describe 'POST #disconnect_tiktok' do
    before do
      user.update!(
        tiktok_access_token: 'tiktok_token_123',
        tiktok_refresh_token: 'tiktok_refresh_123',
        tiktok_user_id: 'tiktok_user_123',
        tiktok_username: 'tiktokuser'
      )
    end

    it 'disconnects TikTok' do
      post :disconnect_tiktok

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('TikTok disconnected successfully')
      
      user.reload
      expect(user.tiktok_access_token).to be_nil
      expect(user.tiktok_refresh_token).to be_nil
      expect(user.tiktok_user_id).to be_nil
      expect(user.tiktok_username).to be_nil
    end
  end

  describe 'POST #disconnect_pinterest' do
    context 'when user has pinterest_access_token method' do
      before do
        allow(user).to receive(:respond_to?).with(:pinterest_access_token).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_access_token=).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_username=).and_return(true)
        user.update!(pinterest_access_token: 'token', pinterest_refresh_token: 'refresh', pinterest_username: 'username')
      end

      it 'disconnects Pinterest and clears username' do
        post :disconnect_pinterest

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Pinterest disconnected successfully')
      end
    end

    context 'when user does not have pinterest_access_token method' do
      before do
        allow(user).to receive(:respond_to?).with(:pinterest_access_token).and_return(false)
      end

      it 'returns bad request' do
        post :disconnect_pinterest

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Pinterest not connected')
      end
    end

    context 'when user does not have pinterest_username= method' do
      before do
        allow(user).to receive(:respond_to?).with(:pinterest_access_token).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_access_token=).and_return(true)
        allow(user).to receive(:respond_to?).with(:pinterest_username=).and_return(false)
        user.update!(pinterest_access_token: 'token', pinterest_refresh_token: 'refresh')
      end

      it 'disconnects Pinterest without clearing username' do
        post :disconnect_pinterest

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Pinterest disconnected successfully')
      end
    end
  end

  describe 'POST #disconnect_youtube' do
    before do
      user.update!(
        youtube_access_token: 'youtube_token_123',
        youtube_refresh_token: 'youtube_refresh_123',
        youtube_channel_id: 'youtube_channel_123'
      )
    end

    it 'disconnects YouTube' do
      post :disconnect_youtube

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('YouTube disconnected successfully')
      
      user.reload
      expect(user.youtube_access_token).to be_nil
      expect(user.youtube_refresh_token).to be_nil
      expect(user.youtube_channel_id).to be_nil
    end
  end

  # Test: Connected accounts status in user JSON
  describe 'connected accounts status' do
    it 'shows correct connection status for all platforms' do
      user.update!(
        fb_user_access_key: 'fb_token',
        twitter_oauth_token: 'twitter_token',
        linkedin_access_token: 'linkedin_token',
        google_refresh_token: 'google_token',
        instagram_business_id: 'ig_business',
        tiktok_access_token: 'tiktok_token',
        youtube_access_token: 'youtube_token'
      )

      # Mock HTTParty to prevent actual API calls (even though test env should skip)
      allow(HTTParty).to receive(:get).and_return(double(success?: true, body: '{}'))

      get :show

      json_response = JSON.parse(response.body)
      user_data = json_response['user']
      
      expect(user_data['facebook_connected']).to be true
      expect(user_data['twitter_connected']).to be true
      expect(user_data['linkedin_connected']).to be true
      expect(user_data['google_connected']).to be true
      expect(user_data['instagram_connected']).to be true
      expect(user_data['tiktok_connected']).to be true
      expect(user_data['youtube_connected']).to be true
    end

    it 'shows disconnected status when tokens are nil' do
      # Create a user without any tokens
      user_without_tokens = create(:user,
        fb_user_access_key: nil,
        twitter_oauth_token: nil,
        linkedin_access_token: nil,
        google_refresh_token: nil,
        instagram_business_id: nil,
        tiktok_access_token: nil,
        youtube_access_token: nil
      )
      allow(controller).to receive(:current_user).and_return(user_without_tokens)
      
      get :show

      json_response = JSON.parse(response.body)
      user_data = json_response['user']
      
      expect(user_data['facebook_connected']).to be false
      expect(user_data['twitter_connected']).to be false
      expect(user_data['linkedin_connected']).to be false
      expect(user_data['google_connected']).to be false
      expect(user_data['instagram_connected']).to be false
      expect(user_data['tiktok_connected']).to be false
      expect(user_data['youtube_connected']).to be false
    end
  end

  describe 'GET #facebook_pages' do
    let(:mock_facebook_service) { instance_double(SocialMedia::FacebookService) }

    before do
      allow(SocialMedia::FacebookService).to receive(:new).with(user).and_return(mock_facebook_service)
    end

    context 'when Facebook is connected' do
      it 'returns Facebook pages' do
        pages_data = [
          { id: 'page_1', name: 'Page 1', access_token: 'token_1' },
          { id: 'page_2', name: 'Page 2', access_token: 'token_2' }
        ]
        allow(mock_facebook_service).to receive(:fetch_pages).and_return(pages_data)

        get :facebook_pages

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['pages']).to be_an(Array)
        expect(json_response['pages'].length).to eq(2)
        expect(json_response['pages'].first['id']).to eq('page_1')
        expect(json_response['pages'].first['name']).to eq('Page 1')
      end

      it 'returns empty array when user has no pages' do
        allow(mock_facebook_service).to receive(:fetch_pages).and_return([])

        get :facebook_pages

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['pages']).to eq([])
      end
    end

    context 'when Facebook is not connected' do
      before do
        user.update!(fb_user_access_key: nil)
      end

      it 'returns unauthorized error' do
        get :facebook_pages

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Facebook not connected')
      end
    end

    context 'when Facebook API error occurs' do
      it 'handles errors gracefully' do
        allow(mock_facebook_service).to receive(:fetch_pages).and_raise(StandardError.new('API error'))

        get :facebook_pages

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to fetch Facebook pages')
        expect(json_response['message']).to eq('API error')
      end
    end
  end

  describe 'POST #convert_to_agency' do
    context 'when user has account_id = 0' do
      before do
        user.update!(account_id: 0, is_account_admin: false)
      end

      it 'creates new agency account' do
        expect {
          post :convert_to_agency, params: { company_name: 'Test Agency' }
        }.to change(Account, :count).by(1)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to include('converted to agency')
        expect(user.reload.account_id).not_to eq(0)
        expect(user.reload.is_account_admin).to be true
      end
    end

    context 'when user already has an account' do
      let(:account) { create(:account) }
      
      before do
        user.update!(account_id: account.id, is_account_admin: true)
      end

      it 'converts existing account to agency' do
        post :convert_to_agency
        
        expect(response).to have_http_status(:ok)
        expect(account.reload.is_reseller).to be true
      end
    end

    context 'when user is not account admin and account_id != 0' do
      let(:account) { create(:account) }
      
      before do
        user.update!(account_id: account.id, is_account_admin: false)
      end

      it 'returns forbidden' do
        post :convert_to_agency
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Only account admins')
      end
    end

    context 'when an error occurs' do
      before do
        user.update!(account_id: 0)
        allow(Account).to receive(:create!).and_raise(StandardError.new('Database error'))
      end

      it 'handles errors gracefully' do
        post :convert_to_agency
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to convert')
      end
    end
  end

  describe 'DELETE #delete_test_account' do
    let(:other_user) { create(:user, email: 'other@example.com') }

    context 'with valid email' do
      it 'deletes user successfully' do
        # Ensure user is not an account admin to avoid account deletion
        other_user.update!(is_account_admin: false, account_id: nil)
        
        expect {
          delete :delete_test_account, params: { email: other_user.email }
        }.to change(User, :count).by(-1)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to include('deleted successfully')
      end

      it 'deletes account when user is account admin' do
        account = create(:account)
        other_user.update!(account_id: account.id, is_account_admin: true)
        subscription = create(:subscription, account: account)
        
        expect {
          delete :delete_test_account, params: { email: other_user.email }
        }.to change(Account, :count).by(-1).and change(Subscription, :count).by(-1)
      end
    end

    context 'with missing email' do
      it 'returns bad_request' do
        delete :delete_test_account
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Email is required')
      end
    end

    context 'when user not found' do
      it 'returns not_found' do
        delete :delete_test_account, params: { email: 'nonexistent@example.com' }
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('User not found')
      end
    end

    context 'when trying to delete own account' do
      it 'returns bad_request' do
        delete :delete_test_account, params: { email: user.email }
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Cannot delete your own account')
      end
    end

    context 'when an error occurs' do
      before do
        allow(User).to receive(:find_by).and_return(other_user)
        allow(other_user).to receive(:destroy).and_raise(StandardError.new('Database error'))
      end

      it 'handles errors gracefully' do
        delete :delete_test_account, params: { email: other_user.email }
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to delete')
      end
    end
  end
end

