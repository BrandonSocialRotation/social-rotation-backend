require 'rails_helper'

RSpec.describe Api::V1::PlansController, type: :controller do
  let(:user) { create(:user) }
  let(:plan) { create(:plan) }

  before do
    # Only stub auth for show action (which requires it)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'GET #index' do
    before do
      # Index doesn't require auth, so don't stub it
      allow(controller).to receive(:authenticate_user!).and_call_original
      Plan.destroy_all
      create_list(:plan, 3, status: true)
      create(:plan, status: false)
    end

    it 'returns all active plans' do
      get :index
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['plans'].length).to eq(3)
    end

    it 'filters by account_type' do
      create(:plan, plan_type: 'personal', status: true)
      create(:plan, plan_type: 'agency', status: true)
      get :index, params: { account_type: 'personal' }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['plans'].all? { |p| p['plan_type'] == 'personal' }).to be true
    end

    it 'filters by plan_type' do
      create(:plan, plan_type: 'agency', status: true)
      get :index, params: { plan_type: 'agency' }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['plans'].all? { |p| p['plan_type'] == 'agency' }).to be true
    end

    it 'handles missing plans table gracefully' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with('plans').and_return(false)
      get :index
      expect(response).to have_http_status(:service_unavailable)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('Plans table does not exist')
    end

    it 'handles errors gracefully' do
      allow(Plan).to receive(:active).and_raise(StandardError.new('Database error'))
      get :index
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Failed to load plans')
    end
  end

  describe 'GET #show' do
    it 'returns plan details' do
      get :show, params: { id: plan.id }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['plan']['id']).to eq(plan.id)
    end

    it 'returns 404 for non-existent plan' do
      get :show, params: { id: 99999 }
      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Plan not found')
    end
  end

  describe 'JSON serializer methods' do
    describe '#plan_json' do
      it 'returns correct JSON structure' do
        json = controller.send(:plan_json, plan)
        expect(json).to have_key(:id)
        expect(json).to have_key(:name)
        expect(json).to have_key(:plan_type)
        expect(json).to have_key(:price_cents)
        expect(json).to have_key(:price_dollars)
        expect(json).to have_key(:formatted_price)
        expect(json).to have_key(:max_locations)
        expect(json).to have_key(:max_users)
        expect(json).to have_key(:max_buckets)
        expect(json).to have_key(:max_images_per_bucket)
        expect(json).to have_key(:features)
        expect(json).to have_key(:stripe_price_id)
        expect(json).to have_key(:stripe_product_id)
        expect(json).to have_key(:display_name)
        expect(json).to have_key(:supports_per_user_pricing)
        expect(json).to have_key(:base_price_cents)
        expect(json).to have_key(:per_user_price_cents)
        expect(json).to have_key(:per_user_price_after_10_cents)
        expect(json).to have_key(:billing_period)
      end

      it 'handles missing supports_per_user_pricing attribute' do
        allow(plan).to receive(:has_attribute?) do |attr|
          attr == :supports_per_user_pricing ? false : plan.class.column_names.include?(attr.to_s)
        end
        json = controller.send(:plan_json, plan)
        expect(json[:supports_per_user_pricing]).to be false
      end

      it 'handles missing base_price_cents attribute' do
        allow(plan).to receive(:has_attribute?) do |attr|
          attr == :base_price_cents ? false : plan.class.column_names.include?(attr.to_s)
        end
        json = controller.send(:plan_json, plan)
        expect(json[:base_price_cents]).to eq(0)
      end

      it 'handles missing per_user_price_cents attribute' do
        allow(plan).to receive(:has_attribute?) do |attr|
          attr == :per_user_price_cents ? false : plan.class.column_names.include?(attr.to_s)
        end
        json = controller.send(:plan_json, plan)
        expect(json[:per_user_price_cents]).to eq(0)
      end

      it 'handles missing billing_period attribute' do
        allow(plan).to receive(:has_attribute?) do |attr|
          attr == :billing_period ? false : plan.class.column_names.include?(attr.to_s)
        end
        json = controller.send(:plan_json, plan)
        expect(json[:billing_period]).to eq('monthly')
      end
    end
  end
end

