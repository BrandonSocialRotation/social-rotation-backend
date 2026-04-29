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

    it 'returns grouped accounts for super admin' do
      Account.find_or_create_by!(id: Account::SUPER_ADMIN_ACCOUNT_ID) do |a|
        a.name = 'Platform administrator'
        a.is_reseller = true
      end
      super_user = create(:user, account_id: Account::SUPER_ADMIN_ACCOUNT_ID, email: 'super@test.com', status: 1)
      token = JsonWebToken.encode(user_id: super_user.id)

      get '/api/v1/admin/accounts', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['groups']).to be_an(Array)
      first = json['groups'].first
      expect(first).to include(
        'account_id',
        'account_title',
        'account_kind',
        'billing_summary',
        'main_users',
        'sub_accounts'
      )
      expect(first['main_users']).to be_an(Array)
      expect(first['sub_accounts']).to be_an(Array)
      if first['main_users'].any?
        expect(first['main_users'].first).to include('username', 'role', 'account_type', 'active')
      end
    end

    it 'lists agency admins under main_users and other users under sub_accounts' do
      Account.find_or_create_by!(id: Account::SUPER_ADMIN_ACCOUNT_ID) do |a|
        a.name = 'Platform administrator'
        a.is_reseller = true
      end
      super_user = create(:user, account_id: Account::SUPER_ADMIN_ACCOUNT_ID, email: 'super2@test.com', status: 1)

      agency = create(:account, is_reseller: true, name: 'Grouped Agency')
      create(:user,
             account_id: agency.id,
             is_account_admin: true,
             email: 'owner@grouped.test',
             status: 1)
      create(:user,
             account_id: agency.id,
             is_account_admin: false,
             email: 'client@grouped.test',
             status: 1)

      token = JsonWebToken.encode(user_id: super_user.id)
      get '/api/v1/admin/accounts', headers: { 'Authorization' => "Bearer #{token}" }

      json = JSON.parse(response.body)
      group = json['groups'].find { |g| g['account_title'] == 'Grouped Agency' }
      expect(group).to be_present
      expect(group['main_users'].map { |u| u['username'] }).to include('owner@grouped.test')
      expect(group['sub_accounts'].map { |u| u['username'] }).to include('client@grouped.test')
      expect(group['sub_accounts'].first['role']).to match(/Sub-account/)
    end

    it 'includes plan name, amount, and billing interval when subscription exists' do
      Account.find_or_create_by!(id: Account::SUPER_ADMIN_ACCOUNT_ID) do |a|
        a.name = 'Platform administrator'
        a.is_reseller = true
      end
      super_user = create(:user, account_id: Account::SUPER_ADMIN_ACCOUNT_ID, email: 'super3@test.com', status: 1)

      plan = create(:plan, name: 'Pro Stack', price_cents: 4900, supports_per_user_pricing: false)
      paid_agency = create(:account, is_reseller: true, name: 'Paid Agency')
      create(:subscription, account: paid_agency, plan: plan, billing_period: 'monthly', status: Subscription::STATUS_ACTIVE)

      create(:user,
             account_id: paid_agency.id,
             is_account_admin: true,
             email: 'paid-owner@test.com',
             status: 1)

      token = JsonWebToken.encode(user_id: super_user.id)
      get '/api/v1/admin/accounts', headers: { 'Authorization' => "Bearer #{token}" }

      json = JSON.parse(response.body)
      group = json['groups'].find { |g| g['account_title'] == 'Paid Agency' }
      expect(group['billing_summary']).to include('Pro Stack').and include('$49.00/month')

      main = group['main_users'].find { |u| u['username'] == 'paid-owner@test.com' }
      expect(main['account_type']).to include('Agency').and include('Pro Stack').and include('$49.00/month')
    end
  end
end
