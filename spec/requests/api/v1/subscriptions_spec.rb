require 'rails_helper'

RSpec.describe "Api::V1::Subscriptions", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/api/v1/subscriptions/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /checkout_session" do
    it "returns http success" do
      get "/api/v1/subscriptions/checkout_session"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /cancel" do
    it "returns http success" do
      get "/api/v1/subscriptions/cancel"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /webhook" do
    it "returns http success" do
      get "/api/v1/subscriptions/webhook"
      expect(response).to have_http_status(:success)
    end
  end

end
