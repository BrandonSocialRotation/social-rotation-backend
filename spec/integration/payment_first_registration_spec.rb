require 'rails_helper'

RSpec.describe 'Payment-First Registration Flow', type: :request do
  describe 'Complete registration flow' do
    let(:plan) { create(:plan, price_cents: 1000) }
    let(:registration_params) do
      {
        name: 'Test User',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        account_type: 'personal',
        plan_id: plan.id,
        billing_period: 'monthly'
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_fake')
      allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://test.com')
      
      customer_double = double(id: 'cus_test123')
      session_double = double(id: 'cs_test123', url: 'https://checkout.stripe.com/test')
      
      allow(Stripe::Customer).to receive(:create).and_return(customer_double)
      allow(Stripe::Price).to receive(:create).and_return(double(id: 'price_test123'))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(session_double)
    end

    it 'does NOT create user account during registration' do
      expect {
        post '/api/v1/auth/register', params: registration_params
      }.to change(PendingRegistration, :count).by(1)
        .and change(User, :count).by(0)
        .and change(Account, :count).by(0)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['checkout_url']).to be_present
      
      # Verify no user was created
      expect(User.find_by(email: 'test@example.com')).to be_nil
    end

    it 'creates user account only after successful payment webhook' do
      # Step 1: Register (creates pending registration)
      post '/api/v1/auth/register', params: registration_params
      pending = PendingRegistration.last
      
      expect(User.find_by(email: 'test@example.com')).to be_nil
      
      # Step 2: Simulate successful payment webhook
      mock_subscription = double(
        id: 'sub_test',
        status: 'active',
        current_period_start: Time.current.to_i,
        current_period_end: 1.month.from_now.to_i,
        cancel_at_period_end: false
      )
      allow(Stripe::Subscription).to receive(:list).and_return(double(data: [mock_subscription]))
      allow(Stripe).to receive(:api_key=)
      
      session = double(
        metadata: {
          'pending_registration_id' => pending.id.to_s,
          'plan_id' => plan.id.to_s,
          'billing_period' => 'monthly',
          'account_type' => 'personal',
          'company_name' => '',
          'user_count' => '1'
        },
        customer: 'cus_test123'
      )
      
      # Simulate webhook handler
      controller = Api::V1::SubscriptionsController.new
      allow(controller).to receive(:frontend_url).and_return('https://test.com')
      controller.send(:handle_checkout_completed, session)
      
      # Now user should exist
      user = User.find_by(email: 'test@example.com')
      expect(user).to be_present
      expect(user.name).to eq('Test User')
      expect(user.authenticate('password123')).to eq(user)
      
      # Account should be created
      expect(user.account).to be_present
      expect(user.account.subscription).to be_present
      
      # Pending registration should be cleaned up
      expect(PendingRegistration.find_by(id: pending.id)).to be_nil
    end

    it 'allows email to be reused if payment is not completed' do
      # Register but don't complete payment
      post '/api/v1/auth/register', params: registration_params
      pending = PendingRegistration.last
      
      # Expire the pending registration
      pending.update!(expires_at: 1.hour.ago)
      
      # Should be able to register again with same email
      expect {
        post '/api/v1/auth/register', params: registration_params
      }.to change(PendingRegistration, :count).by(1)
      
      expect(response).to have_http_status(:created)
    end

    it 'prevents account creation without payment' do
      # Register
      post '/api/v1/auth/register', params: registration_params
      
      # Wait (simulate time passing without payment)
      # No webhook fired
      
      # Verify no user or account was created
      expect(User.find_by(email: 'test@example.com')).to be_nil
      expect(Account.count).to eq(0)
      
      # Pending registration exists but expires
      pending = PendingRegistration.last
      expect(pending).to be_present
      
      # After expiration, email is available again
      pending.update!(expires_at: 1.hour.ago)
      expect(pending.expired?).to be true
    end
  end
end
