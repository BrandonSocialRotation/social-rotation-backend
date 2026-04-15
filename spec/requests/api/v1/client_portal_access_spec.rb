# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client portal access', type: :request do
  let(:account) { create(:account, is_reseller: true, top_level_domain: 'contentrotator.com') }
  let!(:subscription) { create(:subscription, account: account) }
  let(:agency) { create(:user, account: account, account_id: account.id, is_account_admin: true, role: 'reseller') }
  let(:client) do
    create(:user,
           account: account,
           account_id: account.id,
           is_account_admin: false,
           role: 'sub_account',
           client_portal_only: true)
  end

  def auth_headers(user)
    token = JsonWebToken.encode(user_id: user.id)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'buckets API' do
    it 'returns 403 for client portal users' do
      get '/api/v1/buckets', headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end
  end

  describe 'bucket schedules read' do
    it 'allows index for client portal users' do
      get '/api/v1/bucket_schedules', headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
    end

    it 'blocks mutating schedule actions' do
      post '/api/v1/bucket_schedules/bulk_update', headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end
  end

  describe 'schedule items API' do
    it 'returns 403 for client portal users' do
      post '/api/v1/bucket_schedules/1/schedule_items', headers: auth_headers(client), params: {}
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end
  end

  describe 'user_info' do
    it 'allows GET profile' do
      get '/api/v1/user_info', headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['user']['account_type']).to eq('client_portal')
      expect(json['user']['client_portal_only']).to be true
    end

    it 'blocks PATCH profile (agency makes changes)' do
      patch '/api/v1/user_info',
            headers: auth_headers(client).merge('Content-Type' => 'application/json'),
            params: { user: { name: 'Hacked' } }.to_json
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end
  end

  describe 'analytics (allowed for portal)' do
    # No social tokens — avoids WebMock errors from Meta/Twitter in request specs
    let(:client) do
      create(:user,
             account: account,
             account_id: account.id,
             is_account_admin: false,
             role: 'sub_account',
             client_portal_only: true,
             fb_user_access_key: nil,
             instagram_business_id: nil,
             twitter_oauth_token: nil,
             twitter_oauth_token_secret: nil,
             linkedin_access_token: nil,
             google_refresh_token: nil)
    end

    it 'allows overall analytics' do
      get '/api/v1/analytics/overall', headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
    end

    it 'allows facebook_pages (401 if FB not connected — not client_portal 403)' do
      get '/api/v1/user_info/facebook_pages', headers: auth_headers(client)
      expect(response).not_to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).not_to eq('client_portal_restricted')
    end
  end

  describe 'other surfaces clients should not reach' do
    it 'returns 403 for RSS feeds' do
      get '/api/v1/rss_feeds', headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end

    it 'returns 403 for marketplace' do
      get '/api/v1/marketplace', headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('client_portal_restricted')
    end
  end

  describe 'public branding' do
    it 'returns 404 when hostname is unknown' do
      get '/api/v1/client_portal/branding', params: { hostname: 'unknown.example.test' }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns branding when hostname is registered' do
      create(:client_portal_domain,
             user: client,
             account: account,
             hostname: 'portal.contentrotator.com',
             branding: { 'app_name' => 'Agency Co', 'primary_color' => '#112233' })

      get '/api/v1/client_portal/branding', params: { hostname: 'portal.contentrotator.com' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['branding']['app_name']).to eq('Agency Co')
    end

    it 'merges account white-label defaults when domain JSON has no app_name' do
      account.update!(software_title: 'From Account Settings', name: 'Fallback Name')
      create(:client_portal_domain,
             user: client,
             account: account,
             hostname: 'bare.contentrotator.com',
             branding: {})

      get '/api/v1/client_portal/branding', params: { hostname: 'bare.contentrotator.com' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['branding']['app_name']).to eq('From Account Settings')
      expect(json['app_name']).to eq('From Account Settings')
    end
  end
end
