# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Accounts', type: :request do
  let(:agency_account) { create(:account, is_reseller: true, name: 'Agency Test') }
  let(:agency_admin) do
    create(:user, account_id: agency_account.id, is_account_admin: true, email: 'agency@example.com', status: 1)
  end

  describe 'GET /api/v1/admin/accounts' do
    it 'returns 403 for non-super-admin' do
      token = JsonWebToken.encode(user_id: agency_admin.id)
      get '/api/v1/admin/accounts', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns accounts list for super admin' do
      Account.find_or_create_by!(id: Account::SUPER_ADMIN_ACCOUNT_ID) do |a|
        a.name = 'Platform administrator'
        a.is_reseller = true
      end
      super_user = create(:user, account_id: Account::SUPER_ADMIN_ACCOUNT_ID, email: 'super@test.com', status: 1)
      token = JsonWebToken.encode(user_id: super_user.id)

      get '/api/v1/admin/accounts', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['accounts']).to be_an(Array)
      expect(json['accounts'].first).to include('username', 'account_type', 'active')
    end
  end
end
