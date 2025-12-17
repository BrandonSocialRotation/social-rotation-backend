require 'rails_helper'

RSpec.describe "Api::V1::Subscriptions#test_stripe", type: :request do
  let(:user) { create(:user) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_123')
  end

  describe "GET /api/v1/subscriptions/test_stripe" do
    context "with valid Stripe connection" do
      let(:mock_products) { double(data: [double(id: 'prod_1', name: 'Product 1', active: true, description: 'Test')]) }
      let(:mock_prices) { double(data: [double(id: 'price_1', unit_amount: 1000, currency: 'usd', active: true, recurring: double(interval: 'month'))]) }
      let(:mock_account) { double(id: 'acct_123', email: 'test@example.com', country: 'US', default_currency: 'usd') }

      before do
        allow(Stripe::Product).to receive(:list).and_return(mock_products)
        allow(Stripe::Price).to receive(:list).and_return(mock_prices)
        allow(Stripe::Account).to receive(:retrieve).and_return(mock_account)
      end

      it "returns success with Stripe connection info" do
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['message']).to eq('Stripe is connected and working!')
        expect(json_response['products_count']).to eq(1)
        expect(json_response['prices_count']).to eq(1)
      end

      it "includes account information when available" do
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        json_response = JSON.parse(response.body)
        expect(json_response['account']).to be_present
        expect(json_response['account']['id']).to eq('acct_123')
      end

      it "handles restricted API keys gracefully" do
        allow(Stripe::Account).to receive(:retrieve).and_raise(Stripe::PermissionError.new('Permission denied'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['account']['error']).to be_present
      end

      it "identifies restricted keys" do
        allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('rk_test_123')
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        json_response = JSON.parse(response.body)
        expect(json_response['api_key_type']).to eq('restricted')
      end

      it "identifies secret keys" do
        allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return('sk_test_123')
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        json_response = JSON.parse(response.body)
        expect(json_response['api_key_type']).to eq('secret')
      end
    end

    context "with authentication errors" do
      it "handles Stripe authentication errors" do
        allow(Stripe::Product).to receive(:list).and_raise(Stripe::AuthenticationError.new('Invalid API key'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to eq('Stripe authentication failed')
      end
    end

    context "with permission errors" do
      it "handles Stripe permission errors" do
        allow(Stripe::Product).to receive(:list).and_raise(Stripe::PermissionError.new('Permission denied'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('partial_success')
      end
    end

    context "with other Stripe errors" do
      it "handles generic Stripe errors" do
        allow(Stripe::Product).to receive(:list).and_raise(Stripe::StripeError.new('API error'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('error')
        expect(json_response['error_type']).to be_present
      end
    end

    context "with unexpected errors" do
      it "handles unexpected errors gracefully" do
        allow(Stripe::Product).to receive(:list).and_raise(StandardError.new('Unexpected error'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to eq('Unexpected error')
      end

      it "includes backtrace in development" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        allow(Stripe::Product).to receive(:list).and_raise(StandardError.new('Unexpected error'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        json_response = JSON.parse(response.body)
        expect(json_response['backtrace']).to be_present
      end

      it "excludes backtrace in production" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        allow(Stripe::Product).to receive(:list).and_raise(StandardError.new('Unexpected error'))
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        json_response = JSON.parse(response.body)
        expect(json_response['backtrace']).to be_nil
      end
    end

    context "without Stripe configuration" do
      it "returns service unavailable when STRIPE_SECRET_KEY is missing" do
        allow(ENV).to receive(:[]).with('STRIPE_SECRET_KEY').and_return(nil)
        
        get "/api/v1/subscriptions/test_stripe.json",
            headers: { 
              'Authorization' => "Bearer #{token}",
              'Content-Type' => 'application/json'
            }
        
        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Stripe is not configured')
      end
    end

    it "does not require authentication" do
      get "/api/v1/subscriptions/test_stripe.json"
      # Should work without auth since it's in skip_before_action
      expect(response).to have_http_status(:service_unavailable).or have_http_status(:success)
    end
  end
end
