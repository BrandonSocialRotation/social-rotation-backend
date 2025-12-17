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
end

