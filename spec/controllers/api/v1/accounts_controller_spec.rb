# Test suite for AccountsController
# Tests: features, update_features actions with authorization
require 'rails_helper'

RSpec.describe Api::V1::AccountsController, type: :controller do
  # Helper: Generate JWT token for authentication
  def generate_token(user)
    JsonWebToken.encode(user_id: user.id)
  end

  # Test: GET #features - Get account features
  describe 'GET #features' do
    context 'when user is a reseller' do
      let(:account) { create(:account, is_reseller: true) }
      let(:reseller) { create(:user, account: account, is_account_admin: true) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
      end

      it 'returns http success' do
        get :features
        expect(response).to have_http_status(:success)
      end

      it 'returns account features' do
        get :features
        json = JSON.parse(response.body)
        expect(json['features']).to be_present
        expect(json['features']['max_users']).to eq(50)
        expect(json['features']['allow_marketplace']).to be true
      end
    end

    context 'when user is not an account admin' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account, is_account_admin: false) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
      end

      it 'returns forbidden' do
        get :features
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when user is account admin but not reseller' do
      let(:account) { create(:account, is_reseller: false) }
      let(:admin) { create(:user, account: account, is_account_admin: true) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(admin)}"
      end

      it 'returns features for non-reseller account' do
        get :features
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['features']).to be_present
      end
    end

    context 'when user is super admin' do
      let(:super_admin) { create(:user) }

      before do
        allow(super_admin).to receive(:super_admin?).and_return(true)
        request.headers['Authorization'] = "Bearer #{generate_token(super_admin)}"
        allow(controller).to receive(:current_user).and_return(super_admin)
      end

      it 'returns unlimited features for super admin' do
        get :features
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['features']['max_users']).to eq(999999)
        expect(json['features']['max_buckets']).to eq(999999)
        expect(json['features']['allow_marketplace']).to be true
      end
    end

    context 'when account has no account_feature' do
      let(:account) { create(:account) }
      let(:admin) { create(:user, account: account, is_account_admin: true) }

      before do
        account.account_feature&.destroy
        request.headers['Authorization'] = "Bearer #{generate_token(admin)}"
      end

      it 'returns empty hash when account_feature is nil' do
        get :features
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['features']).to eq({})
      end
    end
  end

  # Test: PUT #update_features - Update account features
  describe 'PUT #update_features' do
    context 'when user is a reseller' do
      let(:account) { create(:account, is_reseller: true) }
      let(:reseller) { create(:user, account: account, is_account_admin: true) }
      let(:update_params) do
        {
          features: {
            max_users: 100,
            max_buckets: 200,
            allow_marketplace: false
          }
        }
      end

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
      end

      it 'updates the features' do
        put :update_features, params: update_params
        account.account_feature.reload
        expect(account.account_feature.max_users).to eq(100)
        expect(account.account_feature.max_buckets).to eq(200)
        expect(account.account_feature.allow_marketplace).to be false
      end

      it 'returns success' do
        put :update_features, params: update_params
        expect(response).to have_http_status(:success)
      end

      it 'validates numeric values' do
        put :update_features, params: { features: { max_users: 0 } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when user is not a reseller' do
      let(:account) { create(:account, is_reseller: false) }
      let(:user) { create(:user, account: account, is_account_admin: true) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
      end

      it 'returns forbidden' do
        put :update_features, params: { features: { max_users: 100 } }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when update fails validation' do
      let(:account) { create(:account, is_reseller: true) }
      let(:reseller) { create(:user, account: account, is_account_admin: true) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
      end

      it 'returns validation errors' do
        put :update_features, params: { features: { max_users: -1 } }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
      end
    end
  end
end

