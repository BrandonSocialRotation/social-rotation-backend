require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  # Create a test controller to test ApplicationController methods
  controller do
    def index
      render json: { message: 'success' }
    end
  end

  describe 'authentication' do
    context 'with valid token' do
      let(:user) { create(:user) }
      let(:valid_token) { JsonWebToken.encode(user_id: user.id) }

      before do
        request.headers['Authorization'] = "Bearer #{valid_token}"
      end

      it 'allows access with valid token' do
        get :index
        expect(response).to have_http_status(:ok)
        expect(controller.send(:current_user)).to eq(user)
      end
    end

    context 'without token' do
      it 'denies access without token' do
        get :index
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Authentication token required')
      end
    end

    context 'with invalid token' do
      before do
        request.headers['Authorization'] = 'Bearer invalid_token_string'
      end

      it 'denies access with invalid token' do
        get :index
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Invalid or expired token')
      end
    end
  end

  describe 'error handling' do
    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(create(:user))
    end

    context 'ActiveRecord::RecordNotFound' do
      controller do
        def index
          User.find(99999)
        end
      end

      it 'handles record not found' do
        get :index
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Record not found')
      end
    end

    context 'ActiveRecord::RecordInvalid' do
      controller do
        def index
          User.create!(name: '') # This will fail validation
        end
      end

      it 'handles record invalid' do
        get :index
        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Validation failed')
        expect(json_response['details']).to be_present
      end
    end

    context 'ActionController::ParameterMissing' do
      controller do
        def index
          params.require(:missing_param)
        end
      end

      it 'handles parameter missing' do
        get :index
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Missing required parameter')
        expect(json_response['parameter']).to eq('missing_param')
      end
    end
  end

  describe '#auth_or_oauth_controller?' do
    controller do
      def index
        render json: { result: auth_or_oauth_controller? }
      end
    end

    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(create(:user))
    end

    it 'returns true for AuthController' do
      allow(controller).to receive(:class).and_return(Api::V1::AuthController)
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end

    it 'returns true for OAuthController callback actions' do
      allow(controller).to receive(:class).and_return(Api::V1::OauthController)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(action: 'facebook_callback'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end

    it 'returns false for OAuthController non-callback actions' do
      allow(controller).to receive(:class).and_return(Api::V1::OauthController)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(action: 'connect'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be false
    end

    it 'uses params fallback for route-based detection' do
      allow(controller).to receive(:class).and_return(Api::V1::BucketsController)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(controller: 'api/v1/auth', action: 'login'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end
  end

  describe '#skip_subscription_check?' do
    controller do
      def index
        render json: { result: skip_subscription_check? }
      end
    end

    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(create(:user))
    end

    it 'returns true for subscriptions controller' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(controller: 'api/v1/subscriptions', action: 'index'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end

    it 'returns true for user_info controller' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(controller: 'api/v1/user_info', action: 'show'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end

    it 'returns true for plans controller' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(controller: 'api/v1/plans', action: 'index'))
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be true
    end

    it 'returns false for other controllers' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(controller: 'api/v1/buckets', action: 'index'))
      allow(controller).to receive(:auth_or_oauth_controller?).and_return(false)
      get :index
      json_response = JSON.parse(response.body)
      expect(json_response['result']).to be false
    end
  end
end

