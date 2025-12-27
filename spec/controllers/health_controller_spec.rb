require 'rails_helper'

RSpec.describe HealthController, type: :controller do
  describe 'GET #show' do
    it 'returns API health status' do
      get :show
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('online')
      expect(json_response['message']).to eq('Social Rotation API')
      expect(json_response['version']).to eq('1.0')
    end

    it 'does not require authentication' do
      # Don't stub authenticate_user! - it should be skipped
      get :show
      expect(response).to have_http_status(:ok)
    end
  end
end

