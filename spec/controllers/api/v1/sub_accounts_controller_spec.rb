# Test suite for SubAccountsController
# Tests: index, create, show, update, destroy, switch actions with authorization
require 'rails_helper'

RSpec.describe Api::V1::SubAccountsController, type: :controller do
  # Helper: Generate JWT token for authentication
  def generate_token(user)
    JsonWebToken.encode(user_id: user.id)
  end

  # Test: GET #index - List all sub-accounts
  describe 'GET #index' do
    context 'when user is a reseller' do
      let(:account) { create(:account, is_reseller: true) }
      let(:reseller) { create(:user, account: account, is_account_admin: true) }
      let!(:sub1) { create(:user, account: account, is_account_admin: false, name: 'Sub 1') }
      let!(:sub2) { create(:user, account: account, is_account_admin: false, name: 'Sub 2') }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
      end

      it 'returns http success' do
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'returns all sub-accounts' do
        get :index
        json = JSON.parse(response.body)
        expect(json['sub_accounts'].length).to eq(2)
        expect(json['sub_accounts'].map { |s| s['name'] }).to contain_exactly('Sub 1', 'Sub 2')
      end
    end

    context 'when user is not a reseller' do
      let(:account) { create(:account, is_reseller: false) }
      let(:user) { create(:user, account: account, is_account_admin: true) }

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(user)}"
      end

      it 'returns forbidden' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get :index
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Test: POST #create - Create a new sub-account
  describe 'POST #create' do
    context 'when user is a reseller' do
      let(:account) { create(:account, is_reseller: true) }
      let(:reseller) { create(:user, account: account, is_account_admin: true) }
      let(:valid_params) do
        {
          sub_account: {
            name: 'New Sub',
            email: 'newsub@test.com',
            password: 'password123',
            password_confirmation: 'password123'
          }
        }
      end

      before do
        request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
        account.account_feature.update!(max_users: 10)
      end

      it 'creates a new sub-account' do
        expect {
          post :create, params: valid_params
        }.to change(User, :count).by(1)
      end

      it 'returns created status' do
        post :create, params: valid_params
        expect(response).to have_http_status(:created)
      end

      it 'sets correct account_id' do
        post :create, params: valid_params
        new_user = User.last
        expect(new_user.account_id).to eq(account.id)
        expect(new_user.is_account_admin).to be false
      end

      it 'fails when max_users limit reached' do
        account.account_feature.update!(max_users: 1)
        post :create, params: valid_params
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # Test: GET #show - Show specific sub-account
  describe 'GET #show' do
    let(:account) { create(:account, is_reseller: true) }
    let(:reseller) { create(:user, account: account, is_account_admin: true) }
    let(:sub_account) { create(:user, account: account, is_account_admin: false) }

    before do
      request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
    end

    it 'returns http success' do
      get :show, params: { id: sub_account.id }
      expect(response).to have_http_status(:success)
    end

    it 'returns the sub-account' do
      get :show, params: { id: sub_account.id }
      json = JSON.parse(response.body)
      expect(json['sub_account']['id']).to eq(sub_account.id)
    end
  end

  # Test: PUT #update - Update sub-account
  describe 'PUT #update' do
    let(:account) { create(:account, is_reseller: true) }
    let(:reseller) { create(:user, account: account, is_account_admin: true) }
    let(:sub_account) { create(:user, account: account, is_account_admin: false, name: 'Old Name') }

    before do
      request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
    end

    it 'updates the sub-account' do
      put :update, params: { id: sub_account.id, sub_account: { name: 'New Name' } }
      sub_account.reload
      expect(sub_account.name).to eq('New Name')
    end

    it 'returns success' do
      put :update, params: { id: sub_account.id, sub_account: { name: 'New Name' } }
      expect(response).to have_http_status(:success)
    end
  end

  # Test: DELETE #destroy - Delete sub-account
  describe 'DELETE #destroy' do
    let(:account) { create(:account, is_reseller: true) }
    let(:reseller) { create(:user, account: account, is_account_admin: true) }
    let!(:sub_account) { create(:user, account: account, is_account_admin: false) }

    before do
      request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
    end

    it 'deletes the sub-account' do
      expect {
        delete :destroy, params: { id: sub_account.id }
      }.to change(User, :count).by(-1)
    end

    it 'returns success' do
      delete :destroy, params: { id: sub_account.id }
      expect(response).to have_http_status(:success)
    end
  end

  # Test: POST #switch - Switch to sub-account
  describe 'POST #switch' do
    let(:account) { create(:account, is_reseller: true) }
    let(:reseller) { create(:user, account: account, is_account_admin: true) }
    let(:sub_account) { create(:user, account: account, is_account_admin: false) }

    before do
      request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
    end

    it 'returns success' do
      post :switch, params: { id: sub_account.id }
      expect(response).to have_http_status(:success)
    end

    it 'returns new token for sub-account' do
      post :switch, params: { id: sub_account.id }
      json = JSON.parse(response.body)
      expect(json['token']).to be_present
      expect(json['user']['id']).to eq(sub_account.id)
    end

    it 'prevents switching to user from different account' do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      
      post :switch, params: { id: other_user.id }
      expect(response).to have_http_status(:forbidden)
    end

    context 'when user is super admin' do
      let(:super_admin) { create(:user) }
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }

      before do
        allow(super_admin).to receive(:super_admin?).and_return(true)
        request.headers['Authorization'] = "Bearer #{generate_token(super_admin)}"
        allow(controller).to receive(:current_user).and_return(super_admin)
      end

      it 'allows super admin to switch to any user' do
        post :switch, params: { id: other_user.id }
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['user']['id']).to eq(other_user.id)
      end
    end
  end

  describe 'set_sub_account error handling' do
    let(:account) { create(:account, is_reseller: true) }
    let(:reseller) { create(:user, account: account, is_account_admin: true) }

    before do
      request.headers['Authorization'] = "Bearer #{generate_token(reseller)}"
    end

    it 'returns not_found when sub-account does not exist' do
      get :show, params: { id: 99999 }
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Sub-account not found')
    end
  end
end

