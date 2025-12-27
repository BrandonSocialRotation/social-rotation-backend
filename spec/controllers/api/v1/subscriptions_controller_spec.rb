require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :controller do
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:plan) { create(:plan, stripe_price_id: nil, price_cents: 1000) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  
  before do
    request.headers['Authorization'] = "Bearer #{token}"
    allow(controller).to receive(:current_user).and_return(user)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_key')
    allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return('whsec_test_secret')
    allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://example.com')
  end

  describe 'POST #checkout_session' do
    before do
      user.update!(account: account, is_account_admin: true)
      allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test'))
      allow(Stripe::Price).to receive(:create).and_return(double(id: 'price_test'))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(double(id: 'sess_test', url: 'https://checkout.stripe.com'))
    end

    context 'when plan does not have stripe_price_id' do
      it 'creates Stripe price dynamically' do
        post :checkout_session, params: { plan_id: plan.id }
        
        expect(response).to have_http_status(:success)
        expect(Stripe::Price).to have_received(:create)
      end

      it 'handles annual billing period' do
        post :checkout_session, params: { plan_id: plan.id, billing_period: 'annual' }
        
        expect(response).to have_http_status(:success)
        expect(Stripe::Price).to have_received(:create)
      end
    end

    context 'when Stripe error occurs' do
      before do
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::StripeError.new('Stripe error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles Stripe errors gracefully' do
        post :checkout_session, params: { plan_id: plan.id }
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Payment processing error')
        expect(Rails.logger).to have_received(:error).with(match(/Stripe error/))
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(StandardError.new('Unexpected error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles unexpected errors gracefully' do
        post :checkout_session, params: { plan_id: plan.id }
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Failed to create checkout session')
        expect(Rails.logger).to have_received(:error).with(match(/Subscription error/))
      end
    end
  end

  describe 'POST #webhook' do
    let(:payload) { '{"type":"checkout.session.completed"}' }
    let(:sig_header) { 'test_signature' }

    before do
      request.env['HTTP_STRIPE_SIGNATURE'] = sig_header
      allow(request).to receive(:body).and_return(double(read: payload))
    end

    context 'when JSON parse error occurs' do
      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError.new('Invalid JSON'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles JSON parse errors' do
        post :webhook
        
        expect(response).to have_http_status(:bad_request)
        expect(Rails.logger).to have_received(:error).with(match(/Webhook JSON parse error/))
      end
    end

    context 'when signature verification fails' do
      before do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(Stripe::SignatureVerificationError.new('Invalid signature', 'sig'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles signature verification errors' do
        post :webhook
        
        expect(response).to have_http_status(:bad_request)
        expect(Rails.logger).to have_received(:error).with(match(/Webhook signature verification error/))
      end
    end
  end

  describe '#require_account_admin!' do
    context 'when user is not account admin' do
      before do
        allow(user).to receive(:account_admin?).and_return(false)
        allow(user).to receive(:super_admin?).and_return(false)
      end

      it 'returns forbidden error' do
        post :create, params: { plan_id: plan.id }
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Only account admins')
      end
    end
  end

  describe '#check_stripe_configured!' do
    context 'when Stripe connection succeeds' do
      let(:product) { double(id: 'prod1', name: 'Product 1', active: true, description: 'Desc 1') }
      let(:products) { double(data: [product]) }
      let(:price) { double(id: 'price1', unit_amount: 1000, currency: 'usd', active: true, recurring: nil) }
      let(:prices) { double(data: [price]) }
      
      before do
        allow(Stripe::Product).to receive(:list).and_return(products)
        allow(Stripe::Price).to receive(:list).and_return(prices)
        allow(Stripe::Account).to receive(:retrieve).and_return(double(
          id: 'acct_test',
          email: 'test@example.com',
          country: 'US',
          default_currency: 'usd'
        ))
      end

      it 'returns success with Stripe account info' do
        get :test_stripe
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['account']).to be_present
        expect(json_response['account']['id']).to eq('acct_test')
      end
    end

    context 'when Stripe Account.retrieve raises PermissionError' do
      let(:products) { double(data: []) }
      let(:prices) { double(data: []) }
      
      before do
        allow(Stripe::Product).to receive(:list).and_return(products)
        allow(Stripe::Price).to receive(:list).and_return(prices)
        allow(Stripe::Account).to receive(:retrieve).and_raise(Stripe::PermissionError.new('Permission denied'))
      end

      it 'handles PermissionError gracefully' do
        get :test_stripe
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['account']['error']).to eq('Account endpoint requires additional permissions')
        expect(json_response['account']['message']).to include('restricted API key')
      end
    end

    context 'when STRIPE_SECRET_KEY is not set' do
      before do
        allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return(nil)
      end

      it 'returns service unavailable' do
        get :test_stripe
        
        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Stripe is not configured')
      end
    end

    context 'when check raises exception' do
      before do
        allow(ENV).to receive(:[]).and_raise(StandardError.new('Config error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles configuration check errors' do
        get :test_stripe
        
        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Stripe service unavailable')
        expect(Rails.logger).to have_received(:error).with(match(/Stripe configuration check failed/))
      end
    end
  end

  describe '#get_or_create_stripe_customer' do
    let(:subscription) { create(:subscription, account: account, stripe_customer_id: 'cus_existing') }

    before do
      user.update!(account: account, is_account_admin: true)
      allow(controller).to receive(:get_or_create_stripe_customer).and_call_original
    end

    context 'when customer exists in Stripe' do
      before do
        account.update!(subscription: subscription)
        allow(Stripe::Customer).to receive(:retrieve).and_return(double(id: 'cus_existing'))
      end

      it 'retrieves existing customer' do
        customer = controller.send(:get_or_create_stripe_customer, account)
        expect(customer.id).to eq('cus_existing')
      end
    end

    context 'when customer does not exist in Stripe' do
      before do
        account.update!(subscription: subscription)
        allow(Stripe::Customer).to receive(:retrieve).and_raise(Stripe::StripeError.new('Not found'))
        allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_new'))
      end

      it 'creates new customer' do
        customer = controller.send(:get_or_create_stripe_customer, account)
        expect(customer.id).to eq('cus_new')
      end
    end

    context 'when account has no subscription' do
      before do
        allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_new'))
      end

      it 'creates new customer' do
        customer = controller.send(:get_or_create_stripe_customer, account)
        expect(customer.id).to eq('cus_new')
      end
    end
  end

  describe 'POST #create' do
    context 'when user is not account admin' do
      before do
        allow(user).to receive(:account_admin?).and_return(false)
        allow(user).to receive(:super_admin?).and_return(false)
      end

      it 'returns forbidden error' do
        post :create, params: { plan_id: plan.id }
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Only account admins can manage subscriptions')
      end
    end
  end

  describe 'POST #cancel' do
    context 'when user is not account admin' do
      before do
        user.update!(is_account_admin: false)
        user.update!(account: account)
        create(:subscription, account: account, stripe_subscription_id: 'sub_test')
        allow(user).to receive(:super_admin?).and_return(false)
        allow(user).to receive(:account_admin?).and_return(false)
      end

      it 'returns forbidden error' do
        post :cancel
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Only account admins can manage subscriptions')
      end
    end
  end

  describe '#handle_checkout_completed' do
    let(:session) { double(
      metadata: {
        'user_id' => user.id.to_s,
        'plan_id' => plan.id.to_s,
        'billing_period' => 'monthly',
        'account_type' => 'agency',
        'company_name' => 'Test Company',
        'user_count' => '5'
      },
      customer: 'cus_test'
    ) }
    let(:stripe_subscription) { double(
      id: 'sub_test',
      status: 'active',
      current_period_start: Time.current.to_i,
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: false
    ) }

    before do
      allow(Stripe::Subscription).to receive(:list).and_return(double(data: [stripe_subscription]))
    end

    context 'when creating agency account' do
      it 'creates agency account with company name' do
        controller.send(:handle_checkout_completed, session)
        
        account = Account.find_by(name: 'Test Company')
        expect(account).to be_present
        expect(account.is_reseller).to be true
        expect(user.reload.account_id).to eq(account.id)
        expect(user.is_account_admin).to be true
        expect(user.role).to eq('reseller')
      end
    end

    context 'when creating personal account' do
      let(:session) { double(
        metadata: {
          'user_id' => user.id.to_s,
          'plan_id' => plan.id.to_s,
          'billing_period' => 'monthly',
          'account_type' => 'personal',
          'company_name' => '',
          'user_count' => '1'
        },
        customer: 'cus_test'
      ) }

      it 'creates personal account' do
        controller.send(:handle_checkout_completed, session)
        
        account = Account.find_by(is_reseller: false)
        expect(account).to be_present
        expect(account.name).to include(user.name)
        expect(user.reload.account_id).to eq(account.id)
        expect(user.is_account_admin).to be true
      end
    end
  end
end

