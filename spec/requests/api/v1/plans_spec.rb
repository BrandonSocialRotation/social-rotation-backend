require 'rails_helper'

RSpec.describe "Api::V1::Plans", type: :request do
  describe "GET /api/v1/plans" do
    context "when plans table exists" do
      let!(:personal_plan) { create(:plan, plan_type: 'personal', status: true) }
      let!(:agency_plan) { create(:plan, plan_type: 'agency', status: true) }
      let!(:inactive_plan) { create(:plan, plan_type: 'personal', status: false) }

      it "returns all active plans when no filter" do
        get "/api/v1/plans.json"
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['plans'].length).to eq(2)
        expect(json_response['plans'].map { |p| p['id'] }).to contain_exactly(personal_plan.id, agency_plan.id)
      end

      it "filters by account_type=personal" do
        get "/api/v1/plans.json", params: { account_type: 'personal' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['plans'].length).to eq(1)
        expect(json_response['plans'].first['id']).to eq(personal_plan.id)
      end

      it "filters by account_type=agency" do
        get "/api/v1/plans.json", params: { account_type: 'agency' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['plans'].length).to eq(1)
        expect(json_response['plans'].first['id']).to eq(agency_plan.id)
      end

      it "filters by plan_type param" do
        get "/api/v1/plans.json", params: { plan_type: 'personal' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['plans'].length).to eq(1)
        expect(json_response['plans'].first['id']).to eq(personal_plan.id)
      end

      it "includes all plan attributes in response" do
        get "/api/v1/plans.json"
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        plan_data = json_response['plans'].first
        
        expect(plan_data).to have_key('id')
        expect(plan_data).to have_key('name')
        expect(plan_data).to have_key('plan_type')
        expect(plan_data).to have_key('price_cents')
        expect(plan_data).to have_key('formatted_price')
        expect(plan_data).to have_key('stripe_price_id')
      end
    end

    context "when plans table does not exist" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with('plans').and_return(false)
        migration_context = double(needs_migration?: true)
        allow(ActiveRecord::Base.connection).to receive(:migration_context).and_return(migration_context)
      end

      it "returns service unavailable with instructions" do
        get "/api/v1/plans.json"
        
        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Plans table does not exist')
        expect(json_response['pending_migrations']).to be true
        expect(json_response['plans']).to eq([])
      end
    end

    context "when error occurs" do
      before do
        allow(Plan).to receive(:active).and_raise(StandardError.new('Database error'))
      end

      it "handles errors gracefully" do
        get "/api/v1/plans.json"
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to load plans')
      end
    end
  end

  describe "GET /api/v1/plans/:id" do
    let(:user) { create(:user) }
    let(:token) { JsonWebToken.encode(user_id: user.id) }
    let(:plan) { create(:plan) }

    it "returns plan details" do
      get "/api/v1/plans/#{plan.id}.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['plan']['id']).to eq(plan.id)
      expect(json_response['plan']['name']).to eq(plan.name)
    end

    it "returns not found for non-existent plan" do
      get "/api/v1/plans/99999.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Plan not found')
    end
  end
end
