require 'rails_helper'

RSpec.describe "Api::V1::RssFeeds", type: :request do
  let(:user) { create(:user, account_id: nil) }
  let(:account) { create(:account) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  let(:rss_feed) { create(:rss_feed, user: user, account: account) }

  before do
    allow_any_instance_of(User).to receive(:can_access_rss_feeds?).and_return(true)
    user.update!(account_id: account.id)
  end

  describe "GET /api/v1/rss_feeds" do
    it "returns list of RSS feeds for account" do
      get "/api/v1/rss_feeds.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feeds']).to be_an(Array)
    end

    it "returns feeds for super admin" do
      allow(user).to receive(:super_admin?).and_return(true)
      get "/api/v1/rss_feeds.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /api/v1/rss_feeds/:id" do
    it "returns RSS feed details" do
      get "/api/v1/rss_feeds/#{rss_feed.id}.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feed']['id']).to eq(rss_feed.id)
    end
  end

  describe "POST /api/v1/rss_feeds" do
    it "creates a new RSS feed" do
      post "/api/v1/rss_feeds.json",
           params: {
             rss_feed: {
               url: 'https://example.com/feed.xml',
               name: 'Test Feed',
               description: 'Test Description',
               is_active: true
             }
           },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feed']).to be_present
    end

    it "returns errors for invalid feed" do
      post "/api/v1/rss_feeds.json",
           params: {
             rss_feed: {
               url: '',
               name: ''
             }
           },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe "PATCH /api/v1/rss_feeds/:id" do
    it "updates RSS feed" do
      patch "/api/v1/rss_feeds/#{rss_feed.id}.json",
            params: {
              rss_feed: {
                name: 'Updated Name'
              }
            },
            headers: { 
              'Authorization' => "Bearer #{token}"
            },
            as: :json
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feed']['name']).to eq('Updated Name')
    end
  end

  describe "DELETE /api/v1/rss_feeds/:id" do
    it "deletes RSS feed" do
      delete "/api/v1/rss_feeds/#{rss_feed.id}.json",
             headers: { 
               'Authorization' => "Bearer #{token}",
               'Content-Type' => 'application/json'
             }
      
      expect(response).to have_http_status(:success)
      expect(RssFeed.find_by(id: rss_feed.id)).to be_nil
    end
  end

  describe "POST /api/v1/rss_feeds/fetch_all" do
    it "triggers background job to fetch all feeds" do
      expect(RssFeedFetchJob).to receive(:perform_later)
      
      post "/api/v1/rss_feeds/fetch_all.json",
           headers: { 
             'Authorization' => "Bearer #{token}",
             'Content-Type' => 'application/json'
           }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('RSS feed automation triggered')
    end
  end

  describe "POST /api/v1/rss_feeds/validate" do
    it "validates RSS feed URL" do
      mock_service = instance_double(RssFetchService)
      allow(RssFetchService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:send).with(:fetch_rss_content).and_return('<rss>content</rss>')
      allow(mock_service).to receive(:send).with(:parse_rss_content, '<rss>content</rss>').and_return([{ title: 'Test', description: 'Test desc' }])
      WebMock.stub_request(:get, /example\.com/).to_return(status: 200, body: '<rss>content</rss>')
      
      post "/api/v1/rss_feeds/validate.json",
           params: { url: 'https://example.com/feed.xml' },
           headers: { 
             'Authorization' => "Bearer #{token}"
           },
           as: :json
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be true
    end

    it "returns error for missing URL" do
      post "/api/v1/rss_feeds/validate.json",
           params: {},
           headers: { 
             'Authorization' => "Bearer #{token}",
             'Content-Type' => 'application/json'
           }
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be false
      expect(json_response['error']).to include('URL is required')
    end
  end

  describe "POST /api/v1/rss_feeds/:id/fetch_posts" do
    it "fetches posts for RSS feed" do
      allow_any_instance_of(RssFetchService).to receive(:fetch_and_parse).and_return({
        success: true,
        message: 'Fetched successfully',
        posts_found: 5,
        posts_saved: 5
      })
      
      post "/api/v1/rss_feeds/#{rss_feed.id}/fetch_posts.json",
           headers: { 
             'Authorization' => "Bearer #{token}",
             'Content-Type' => 'application/json'
           }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['posts_found']).to eq(5)
    end
  end

  describe "GET /api/v1/rss_feeds/:id/posts" do
    let!(:post1) { create(:rss_post, rss_feed: rss_feed, is_viewed: false) }
    let!(:post2) { create(:rss_post, rss_feed: rss_feed, is_viewed: true) }

    it "returns posts for RSS feed" do
      get "/api/v1/rss_feeds/#{rss_feed.id}/posts.json",
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['posts']).to be_an(Array)
      expect(json_response['pagination']).to be_present
    end

    it "filters by viewed status" do
      get "/api/v1/rss_feeds/#{rss_feed.id}/posts.json",
          params: { viewed: 'false' },
          headers: { 
            'Authorization' => "Bearer #{token}",
            'Content-Type' => 'application/json'
          }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['posts'].all? { |p| p['is_viewed'] == false }).to be true
    end
  end
end
