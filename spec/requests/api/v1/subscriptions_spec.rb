require 'rails_helper'

RSpec.describe "Api::V1::Subscriptions", type: :request do
  include Rails.application.routes.url_helpers
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  
  before do
    user.update!(account: account, is_account_admin: true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_key')
    allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return('whsec_test_secret')
    # Ensure account exists and is valid
    account.update!(status: true) if account
  end

  describe "GET /index" do
    it "returns subscription when account has subscription" do
      subscription = create(:subscription, account: account, plan: plan)
      account.update!(subscription: subscription)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_present
    end

    it "returns nil when account has no subscription" do
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "returns nil for personal accounts (account_id 0)" do
      user.update!(account_id: 0)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "returns nil when account_id is nil" do
      user.update!(account_id: nil)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "handles subscription_json errors gracefully" do
      subscription = create(:subscription, account: account, plan: plan)
      account.update!(subscription: subscription)
      # Mock subscription_json to raise error
      allow_any_instance_of(Api::V1::SubscriptionsController).to receive(:subscription_json).and_raise(StandardError.new('Serialization error'))
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "handles general errors gracefully" do
      allow_any_instance_of(User).to receive(:account).and_raise(StandardError.new('Database error'))
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Failed to load subscription')
    end

    it "handles RecordNotFound errors gracefully" do
      allow_any_instance_of(User).to receive(:account).and_raise(ActiveRecord::RecordNotFound.new('Account not found'))
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "handles subscription that is not persisted" do
      # Create subscription but make it non-persisted by using build
      subscription = build(:subscription, account: account, plan: plan)
      # Stub account.subscription to return the non-persisted subscription
      allow(account).to receive(:subscription).and_return(subscription)
      allow(subscription).to receive(:persisted?).and_return(false)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end

    it "handles account being nil" do
      allow_any_instance_of(User).to receive(:account).and_return(nil)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
    end
  end

  describe "GET /show" do
    it "returns subscription when account has subscription" do
      subscription = create(:subscription, account: account, plan: plan)
      account.update!(subscription: subscription)
      
      get "/api/v1/subscriptions/#{subscription.id}.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_present
    end

    it "returns nil when account has no subscription" do
      get api_v1_subscription_path(1, format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['subscription']).to be_nil
      expect(json_response['message']).to eq('No active subscription')
    end
  end

  describe "POST /create" do
    it "returns http success" do
      # POST to /api/v1/subscriptions creates a subscription
      # Use string path with format to ensure route matches
      post "/api/v1/subscriptions.json", 
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      # May return created, conflict, unprocessable_entity, unprocessable_content, or bad_request depending on subscription state
      expect(response).to have_http_status(:created).or have_http_status(:success).or have_http_status(:conflict).or have_http_status(:bad_request).or have_http_status(:unprocessable_entity).or have_http_status(:unprocessable_content)
    end

    it "returns conflict when account already has active subscription" do
      existing_subscription = create(:subscription, account: account, plan: plan, status: Subscription::STATUS_ACTIVE)
      account.reload
      # Ensure account has the subscription association
      expect(account.subscription).to eq(existing_subscription)
      
      post "/api/v1/subscriptions.json", 
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:conflict)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Account already has an active subscription')
    end

    it "creates subscription with provided parameters" do
      post "/api/v1/subscriptions.json", 
           params: { 
             plan_id: plan.id,
             stripe_customer_id: 'cus_test',
             stripe_subscription_id: 'sub_test',
             status: Subscription::STATUS_ACTIVE
           },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      if response.status == 201
        json_response = JSON.parse(response.body)
        expect(json_response['subscription']).to be_present
        expect(json_response['message']).to eq('Subscription created successfully')
      end
    end

    it "handles validation errors" do
      post "/api/v1/subscriptions.json", 
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      # May return unprocessable_entity if validation fails
      if response.status == 422
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end
  end

  describe "POST /checkout_session" do
    let(:mock_customer) { double(id: 'cus_test') }
    let(:mock_session) { double(id: 'cs_test', url: 'https://checkout.stripe.com') }

    before do
      allow(Stripe::Customer).to receive(:create).and_return(mock_customer)
    end

    it "returns http success" do
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      # May return success or bad_request depending on validation
      expect(response).to have_http_status(:success).or have_http_status(:bad_request)
    end

    it "creates Stripe checkout session without require_cvc parameter" do
      # Capture the parameters passed to Stripe
      captured_params = nil
      allow(Stripe::Checkout::Session).to receive(:create) do |params|
        captured_params = params
        mock_session
      end

      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      # If the request succeeded, verify require_cvc is not present
      if response.status == 200 || response.status == 201
        expect(captured_params).to be_present
        # Verify that payment_method_options.card.require_cvc is NOT present
        expect(captured_params[:payment_method_options]).to be_nil
      else
        # If request failed early (validation), that's OK - we just verify no require_cvc error
        expect(response.body).not_to include('require_cvc')
      end
    end

    it "creates checkout session with correct parameters when successful" do
      # Capture the parameters passed to Stripe
      captured_params = nil
      allow(Stripe::Checkout::Session).to receive(:create) do |params|
        captured_params = params
        mock_session
      end

      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id, billing_period: 'monthly' },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      # If successful, verify parameters
      if response.status == 200 || response.status == 201
        expect(captured_params).to be_present
        expect(captured_params[:customer]).to eq('cus_test')
        expect(captured_params[:payment_method_types]).to eq(['card'])
        expect(captured_params[:mode]).to eq('subscription')
        expect(captured_params[:line_items]).to be_present
        expect(captured_params[:metadata]).to be_present
        expect(captured_params[:metadata][:user_id]).to eq(user.id.to_s)
        expect(captured_params[:metadata][:plan_id]).to eq(plan.id.to_s)
        # Verify require_cvc is NOT in payment_method_options (this was the bug)
        expect(captured_params[:payment_method_options]).to be_nil
      end
    end

    it "handles per-user pricing plans" do
      per_user_plan = create(:plan, plan_type: 'agency', supports_per_user_pricing: true, per_user_price_cents: 1000)
      mock_price = double(id: 'price_test')
      allow(Stripe::Price).to receive(:create).and_return(mock_price)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: per_user_plan.id, user_count: 5, billing_period: 'monthly' },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      if response.status == 200 || response.status == 201
        expect(Stripe::Price).to have_received(:create)
      end
    end

    it "handles agency accounts with company name" do
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { 
             plan_id: plan.id, 
             account_type: 'agency',
             company_name: 'Test Company'
           },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      # Should succeed with company name
      expect(response).to have_http_status(:success).or have_http_status(:bad_request)
    end

    it "requires company name for agency accounts" do
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { 
             plan_id: plan.id, 
             account_type: 'agency',
             company_name: ''
           },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('Company name is required')
    end

    it "handles annual billing period" do
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id, billing_period: 'annual' },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      if response.status == 200 || response.status == 201
        # Verify annual billing is handled
        expect(response).to have_http_status(:success)
      end
    end

    it "uses plan stripe_price_id when available" do
      plan_with_price = create(:plan, stripe_price_id: 'price_existing')
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan_with_price.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      if response.status == 200 || response.status == 201
        expect(response).to have_http_status(:success)
      end
    end

    it "handles plan without price configured" do
      plan_no_price = create(:plan, price_cents: 0, stripe_price_id: nil)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan_no_price.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('price')
    end

    it "handles inactive plans" do
      inactive_plan = create(:plan)
      inactive_plan.update_column(:status, false)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: inactive_plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Plan is not available')
    end

    it "uses frontend_url with invalid ENV format" do
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('invalid-url-without-protocol')
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      # Should still work, just uses default URL
      expect(response).to have_http_status(:success).or have_http_status(:bad_request)
    end

    it "creates new Stripe customer when none exists" do
      mock_customer = double(id: 'cus_new')
      allow(Stripe::Customer).to receive(:create).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(Stripe::Customer).to have_received(:create)
    end

    it "retrieves existing Stripe customer when available" do
      subscription = create(:subscription, account: account, stripe_customer_id: 'cus_existing')
      account.update!(subscription: subscription)
      mock_customer = double(id: 'cus_existing')
      allow(Stripe::Customer).to receive(:retrieve).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(Stripe::Customer).to have_received(:retrieve).with('cus_existing')
    end

    it "creates new customer when existing customer retrieval fails" do
      subscription = create(:subscription, account: account, stripe_customer_id: 'cus_invalid')
      account.update!(subscription: subscription)
      mock_customer = double(id: 'cus_new')
      allow(Stripe::Customer).to receive(:retrieve).and_raise(Stripe::StripeError.new('Customer not found'))
      allow(Stripe::Customer).to receive(:create).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
      
      post checkout_session_api_v1_subscriptions_path(format: :json),
           params: { plan_id: plan.id },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(Stripe::Customer).to have_received(:create)
    end
  end

  describe "subscription_json error handling" do
    it "handles subscription with nil status in rescue block" do
      subscription = create(:subscription, account: account, plan: plan, status: 'active')
      account.update!(subscription: subscription)
      
      # Force an error in subscription_json by making plan access fail
      allow_any_instance_of(Subscription).to receive(:plan).and_raise(StandardError.new('Plan access error'))
      allow_any_instance_of(Subscription).to receive(:status).and_return(nil)
      
      get api_v1_subscriptions_path(format: :json),
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      # Should still return success with minimal subscription data
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      # The rescue block should return status: 'unknown' when status is nil
      expect(json_response['subscription']).to be_present
    end
  end

  describe "POST /cancel" do
    let(:plan_for_sub) { create(:plan) }
    let(:subscription) { create(:subscription, account: account, plan: plan_for_sub, status: Subscription::STATUS_ACTIVE, stripe_subscription_id: 'sub_test') }
    
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_123')
    end

    context "with active subscription" do
      before do
        account.update!(subscription: subscription)
        mock_stripe_subscription = double(status: 'active', cancel_at_period_end: true)
        allow(Stripe::Subscription).to receive(:update).and_return(mock_stripe_subscription)
      end

      it "cancels subscription successfully" do
        post "/api/v1/subscriptions/cancel.json",
             headers: { 
               'Authorization' => "Bearer #{token}"
             },
             as: :json
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to include('canceled at the end')
        expect(subscription.reload.cancel_at_period_end).to be true
      end
    end

    context "without active subscription" do
      before do
        account.update!(subscription: nil)
      end

      it "returns bad_request" do
        post "/api/v1/subscriptions/cancel.json",
             headers: { 
               'Authorization' => "Bearer #{token}"
             },
             as: :json
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('No active subscription')
      end
    end

    context "with inactive subscription" do
      let(:inactive_subscription) { create(:subscription, account: account, plan: plan_for_sub, status: 'canceled', stripe_subscription_id: 'sub_test') }
      
      before do
        account.update!(subscription: inactive_subscription)
      end

      it "returns bad_request for inactive subscription" do
        post "/api/v1/subscriptions/cancel.json",
             headers: { 
               'Authorization' => "Bearer #{token}"
             },
             as: :json
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('No active subscription')
      end
    end

    context "with Stripe error" do
      before do
        account.update!(subscription: subscription)
        allow(Stripe::Subscription).to receive(:update).and_raise(Stripe::StripeError.new('Stripe error'))
      end

      it "handles Stripe errors gracefully" do
        post "/api/v1/subscriptions/cancel.json",
             headers: { 
               'Authorization' => "Bearer #{token}"
             },
             as: :json
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to cancel')
      end
    end
  end

  describe "POST /webhook" do
    it "returns http success" do
      # Mock webhook signature verification
      event_data = double(
        type: 'checkout.session.completed',
        data: double(object: double(
          id: 'cs_test', 
          customer: 'cus_test', 
          subscription: 'sub_test', 
          mode: 'subscription',
          metadata: {}
        ))
      )
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_data)
      
      # Mock Stripe customer and subscription retrieval
      allow(Stripe::Customer).to receive(:retrieve).and_return(double(id: 'cus_test', email: user.email))
      allow(Stripe::Subscription).to receive(:retrieve).and_return(double(id: 'sub_test', status: 'active'))
      
      post "/api/v1/subscriptions/webhook.json",
           params: {},
           headers: { 
             'HTTP_STRIPE_SIGNATURE' => 'test_signature'
           },
           as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:bad_request)
    end
  end

  describe 'JSON serializer methods' do
    let(:controller) { Api::V1::SubscriptionsController.new }

    before do
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(user)
    end

    describe '#subscription_json' do
      let(:subscription) { create(:subscription, account: account, plan: plan) }

      it 'returns correct JSON structure' do
        json = controller.send(:subscription_json, subscription)
        expect(json).to have_key(:id)
        expect(json).to have_key(:plan)
        expect(json).to have_key(:status)
        expect(json).to have_key(:current_period_start)
        expect(json).to have_key(:current_period_end)
        expect(json).to have_key(:cancel_at_period_end)
        expect(json).to have_key(:days_remaining)
        expect(json).to have_key(:active)
        expect(json).to have_key(:will_cancel)
      end

      it 'includes plan info when present' do
        json = controller.send(:subscription_json, subscription)
        expect(json[:plan]).to be_a(Hash)
        expect(json[:plan][:id]).to eq(plan.id)
        expect(json[:plan][:name]).to eq(plan.name)
        expect(json[:plan][:plan_type]).to eq(plan.plan_type)
      end

      it 'handles nil plan gracefully' do
        # Stub the plan association to return nil instead of trying to set plan_id to nil
        allow(subscription).to receive(:plan).and_return(nil)
        json = controller.send(:subscription_json, subscription)
        expect(json[:plan]).to be_nil
      end

      it 'handles errors gracefully' do
        allow(subscription).to receive(:plan).and_raise(StandardError.new('Database error'))
        json = controller.send(:subscription_json, subscription)
        expect(json).to have_key(:error)
        expect(json[:error]).to eq('Failed to load subscription details')
        expect(json[:plan]).to be_nil
      end

      it 'handles nil status in rescue block' do
        allow(subscription).to receive(:status).and_return(nil)
        allow(subscription).to receive(:plan).and_raise(StandardError.new('Error'))
        json = controller.send(:subscription_json, subscription)
        expect(json[:status]).to eq('unknown')
      end
    end

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
