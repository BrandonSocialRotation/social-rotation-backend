require 'rails_helper'

RSpec.describe "Api::V1::Subscriptions#webhook", type: :request do
  include Rails.application.routes.url_helpers
  
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return('whsec_test_secret')
    allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_key')
  end

  describe "POST /api/v1/subscriptions/webhook" do
    let(:payload) { '{"type":"checkout.session.completed","data":{"object":{"id":"cs_test"}}}' }
    let(:sig_header) { 'test_signature' }

    context "with valid webhook signature" do
      let(:mock_event) { double(type: 'checkout.session.completed', data: double(object: double)) }

      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_return(mock_event)
      end

      it "handles checkout.session.completed event" do
        session_object = double(
          metadata: {
            'user_id' => user.id.to_s,
            'plan_id' => plan.id.to_s,
            'billing_period' => 'monthly',
            'account_type' => 'personal',
            'company_name' => '',
            'user_count' => '1'
          },
          customer: 'cus_test'
        )
        allow(mock_event.data.object).to receive(:is_a?).and_return(false)
        allow(mock_event.data).to receive(:object).and_return(session_object)
        
        mock_subscription = double(
          id: 'sub_test',
          status: 'active',
          current_period_start: Time.current.to_i,
          current_period_end: 1.month.from_now.to_i,
          cancel_at_period_end: false
        )
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: [mock_subscription]))
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
      end

      it "handles customer.subscription.updated event" do
        subscription_object = double(
          id: 'sub_test',
          status: 'active',
          current_period_start: Time.current.to_i,
          current_period_end: 1.month.from_now.to_i,
          cancel_at_period_end: false,
          canceled_at: nil
        )
        subscription = create(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_test')
        
        allow(mock_event).to receive(:type).and_return('customer.subscription.updated')
        allow(mock_event.data).to receive(:object).and_return(subscription_object)
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
        subscription.reload
        expect(subscription.status).to eq('active')
      end

      it "handles customer.subscription.deleted event" do
        subscription = create(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_test')
        subscription_object = double(id: 'sub_test')
        
        allow(mock_event).to receive(:type).and_return('customer.subscription.deleted')
        allow(mock_event.data).to receive(:object).and_return(subscription_object)
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
        subscription.reload
        expect(subscription.status).to eq(Subscription::STATUS_CANCELED)
      end

      it "handles invoice.payment_succeeded event" do
        subscription = create(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_test')
        invoice_object = double(subscription: 'sub_test')
        stripe_subscription = double(
          status: 'active',
          current_period_start: Time.current.to_i,
          current_period_end: 1.month.from_now.to_i
        )
        
        allow(mock_event).to receive(:type).and_return('invoice.payment_succeeded')
        allow(mock_event.data).to receive(:object).and_return(invoice_object)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_subscription)
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
      end

      it "handles invoice.payment_failed event" do
        subscription = create(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_test')
        invoice_object = double(subscription: 'sub_test')
        
        allow(mock_event).to receive(:type).and_return('invoice.payment_failed')
        allow(mock_event.data).to receive(:object).and_return(invoice_object)
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
        subscription.reload
        expect(subscription.status).to eq(Subscription::STATUS_PAST_DUE)
      end

      it "handles unhandled event types" do
        allow(mock_event).to receive(:type).and_return('unknown.event.type')
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:ok)
      end
    end

    context "without webhook secret" do
      it "returns bad_request when STRIPE_WEBHOOK_SECRET is missing" do
        allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return(nil)
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with invalid signature" do
      it "returns bad_request for JSON parse errors" do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError.new('Invalid JSON'))
        
        post "/api/v1/subscriptions/webhook.json",
             params: 'invalid json',
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:bad_request)
      end

      it "returns bad_request for signature verification errors" do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(Stripe::SignatureVerificationError.new('Invalid signature', sig_header))
        
        post "/api/v1/subscriptions/webhook.json",
             params: payload,
             headers: { 
               'HTTP_STRIPE_SIGNATURE' => sig_header,
               'Content-Type' => 'application/json'
             }
        
        expect(response).to have_http_status(:bad_request)
      end
    end

    it "does not require authentication" do
      allow(Stripe::Webhook).to receive(:construct_event).and_return(double(type: 'unknown.event', data: double(object: double)))
      
      post "/api/v1/subscriptions/webhook.json",
           params: payload,
           headers: { 
             'HTTP_STRIPE_SIGNATURE' => sig_header,
             'Content-Type' => 'application/json'
           }
      
      # Should work without auth since it's in skip_before_action
      expect(response).to have_http_status(:ok)
    end
  end
end
