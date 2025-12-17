require 'rails_helper'

RSpec.describe "Api::V1::Plans", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/api/v1/plans/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    let(:user) { create(:user) }
    let(:plan) { create(:plan) }
    
    before do
      token = JsonWebToken.encode(user_id: user.id)
      get "/api/v1/plans/#{plan.id}", headers: { 'Authorization' => "Bearer #{token}" }
    end
    
    it "returns http success" do
      expect(response).to have_http_status(:success)
    end
  end

end
