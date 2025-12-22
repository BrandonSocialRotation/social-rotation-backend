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

    context 'with token for non-existent user' do
      let(:non_existent_user_token) { JsonWebToken.encode(user_id: 99999) }

      before do
        request.headers['Authorization'] = "Bearer #{non_existent_user_token}"
      end

      it 'denies access when user not found' do
        get :index
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('User not found')
      end
    end

    context 'when authentication raises an exception' do
      before do
        request.headers['Authorization'] = 'Bearer test_token'
        allow(JsonWebToken).to receive(:decode).and_raise(StandardError.new('Decode error'))
      end

      it 'handles authentication errors gracefully' do
        get :index
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Authentication failed')
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
      stub_const('Api::V1::AuthController', Class.new)
      allow(controller).to receive(:class).and_return(Api::V1::AuthController)
      result = controller.send(:auth_or_oauth_controller?)
      expect(result).to be true
    end

    it 'returns true for OAuthController callback actions' do
      stub_const('Api::V1::OauthController', Class.new)
      allow(controller).to receive(:class).and_return(Api::V1::OauthController)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(action: 'facebook_callback'))
      result = controller.send(:auth_or_oauth_controller?)
      expect(result).to be true
    end

    it 'returns false for OAuthController non-callback actions' do
      stub_const('Api::V1::OauthController', Class.new)
      allow(controller).to receive(:class).and_return(Api::V1::OauthController)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(action: 'connect'))
      result = controller.send(:auth_or_oauth_controller?)
      expect(result).to be false
    end

    it 'uses params fallback for route-based detection' do
      # Test the params-based fallback logic - method checks params[:controller] and params[:action]
      allow(controller).to receive(:class).and_return(ApplicationController)
      # The method uses params[:controller] and params[:action] directly
      # Use ActionController::Parameters which supports [] access
      mock_params = ActionController::Parameters.new(controller: 'api/v1/auth', action: 'login')
      allow(controller).to receive(:params).and_return(mock_params)
      # Call the method directly instead of through a route
      result = controller.send(:auth_or_oauth_controller?)
      expect(result).to be true
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

  describe '#require_active_subscription!' do
    controller do
      def index
        require_active_subscription!
        render json: { message: 'success' }
      end
    end

    let(:user) { create(:user) }
    let(:account) { create(:account) }
    let(:token) { JsonWebToken.encode(user_id: user.id) }

    before do
      request.headers['Authorization'] = "Bearer #{token}"
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:skip_subscription_check?).and_return(false)
    end

    context 'when user account_id is 0 (super admin)' do
      before do
        user.update!(account_id: 0)
      end

      it 'allows access without subscription check' do
        get :index
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user account_id is nil (no account)' do
      before do
        user.update!(account_id: nil)
      end

      it 'blocks access and returns account not activated error' do
        get :index
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Account not activated')
        expect(json_response['subscription_required']).to be true
      end
    end

    context 'when account does not exist' do
      before do
        user.update!(account_id: 99999)
        allow(user).to receive(:account).and_return(nil)
      end

      it 'blocks access and returns account not found error' do
        get :index
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Account not found')
        expect(json_response['subscription_required']).to be true
      end
    end

    context 'when subscription exists but is not active' do
      let(:plan) { create(:plan) }
      let(:subscription) { create(:subscription, account: account, plan: plan, status: Subscription::STATUS_CANCELED) }

      before do
        user.update!(account: account)
        account.update!(subscription: subscription)
        allow(account).to receive(:has_active_subscription?).and_return(false)
      end

      it 'blocks access and returns subscription suspended error' do
        get :index
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Subscription suspended')
        expect(json_response['subscription_suspended']).to be true
      end
    end

    context 'when no subscription exists' do
      before do
        user.update!(account: account)
        account.update!(subscription: nil)
      end

      it 'blocks access and returns subscription required error' do
        get :index
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Subscription required')
        expect(json_response['subscription_required']).to be true
      end
    end

    context 'when subscription check raises an exception' do
      before do
        user.update!(account: account)
      end

      it 'handles errors gracefully and blocks access' do
        # Ensure user has the account
        user.update!(account: account)
        # Make account.subscription raise an error when accessed
        allow_any_instance_of(Account).to receive(:subscription).and_raise(StandardError.new('Database error'))
        
        get :index
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Subscription verification failed')
      end
    end

    context 'when current_user is nil' do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:authenticate_user!).and_return(true)
      end

      it 'skips subscription check' do
        get :index
        expect(response).to have_http_status(:ok)
      end
    end
  end
end

