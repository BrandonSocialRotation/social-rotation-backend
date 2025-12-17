require 'rails_helper'

RSpec.describe Api::V1::ImagesController, type: :controller do
  let(:user) { create(:user) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  
  before do
    request.headers['Authorization'] = "Bearer #{token}"
    allow(controller).to receive(:current_user).and_return(user)
  end
  
  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new image' do
        expect {
          post :create, params: {
            file_path: 'test/image.jpg',
            friendly_name: 'Test Image'
          }
        }.to change(Image, :count).by(1)
        
        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response['file_path']).to eq('test/image.jpg')
        expect(json_response['friendly_name']).to eq('Test Image')
      end
    end
    
    context 'with invalid parameters' do
      it 'returns validation errors' do
        post :create, params: {
          file_path: nil,
          friendly_name: 'Test Image'
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end
  end
end
