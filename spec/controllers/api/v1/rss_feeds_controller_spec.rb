require 'rails_helper'

RSpec.describe Api::V1::RssFeedsController, type: :controller do
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:rss_feed) { create(:rss_feed, user: user, account: account) }

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:require_rss_access!).and_return(true)
    user.update!(account: account)
  end

  describe 'POST #fetch_all' do
    it 'triggers RSS feed fetch job' do
      expect(RssFeedFetchJob).to receive(:perform_later)
      
      post :fetch_all
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('RSS feed automation triggered')
    end
  end

  describe 'POST #validate' do
    before do
      stub_request(:get, 'https://example.com/feed.xml')
        .to_return(
          status: 200,
          body: '<?xml version="1.0"?><rss version="2.0"><channel><title>Test Feed</title><item><title>Test Post</title><description>Test Description</description><link>https://example.com/post</link></item></channel></rss>',
          headers: { 'Content-Type' => 'application/xml' }
        )
    end

    it 'validates valid RSS feed' do
      post :validate, params: { url: 'https://example.com/feed.xml' }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be true
      expect(json_response['message']).to include('Valid RSS feed')
    end

    it 'returns error for missing URL' do
      post :validate
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be false
      expect(json_response['error']).to eq('URL is required')
    end

    it 'returns error for inaccessible feed' do
      stub_request(:get, 'https://example.com/feed.xml')
        .to_return(status: 404, body: 'Not Found')
      
      post :validate, params: { url: 'https://example.com/feed.xml' }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be false
      expect(json_response['error']).to include('Unable to fetch feed')
    end

    it 'handles validation errors gracefully' do
      allow_any_instance_of(RssFetchService).to receive(:send).and_raise(StandardError.new('Network error'))
      
      post :validate, params: { url: 'https://example.com/feed.xml' }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['valid']).to be false
      expect(json_response['error']).to include('Feed validation failed')
    end
  end

  describe 'GET #index' do
    before do
      create(:rss_feed, user: user, account: account)
      create(:rss_feed, user: user, account: account)
    end

    it 'returns RSS feeds for account user' do
      get :index
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feeds'].length).to eq(2)
    end

    context 'with super admin' do
      let(:super_admin) { create(:user, account_id: 0) }

      before do
        allow(controller).to receive(:current_user).and_return(super_admin)
        create(:rss_feed, user: super_admin)
        create(:rss_feed, user: user, account: account)
      end

      it 'returns all RSS feeds for super admin' do
        get :index
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['rss_feeds'].length).to be >= 2
      end
    end

    context 'with user without account' do
      let(:user_no_account) { create(:user, account_id: nil) }

      before do
        allow(controller).to receive(:current_user).and_return(user_no_account)
        create(:rss_feed, user: user_no_account)
      end

      it 'returns user RSS feeds' do
        get :index
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['rss_feeds'].length).to eq(1)
      end
    end
  end

  describe 'GET #show' do
    before do
      create_list(:rss_post, 10, rss_feed: rss_feed, published_at: 1.hour.ago)
    end

    it 'returns RSS feed with recent posts' do
      get :show, params: { id: rss_feed.id }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feed']['id']).to eq(rss_feed.id)
      expect(json_response['recent_posts'].length).to eq(5)
    end
  end

  describe 'POST #create' do
    let(:create_params) do
      {
        rss_feed: {
          url: 'https://example.com/feed.xml',
          name: 'Test Feed',
          description: 'Test Description',
          is_active: true
        }
      }
    end

    it 'creates RSS feed successfully' do
      expect {
        post :create, params: create_params
      }.to change(RssFeed, :count).by(1)
      
      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['rss_feed']['name']).to eq('Test Feed')
    end

    it 'sets account_id when user has account' do
      post :create, params: create_params
      
      feed = RssFeed.last
      expect(feed.account_id).to eq(account.id)
    end

    it 'returns errors for invalid params' do
      invalid_params = { rss_feed: { url: '', name: 'Test' } }
      
      post :create, params: invalid_params
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe 'PATCH #update' do
    it 'updates RSS feed successfully' do
      patch :update, params: { id: rss_feed.id, rss_feed: { name: 'Updated Name' } }
      
      expect(response).to have_http_status(:ok)
      rss_feed.reload
      expect(rss_feed.name).to eq('Updated Name')
    end

    it 'returns errors for invalid params' do
      patch :update, params: { id: rss_feed.id, rss_feed: { url: '' } }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe 'DELETE #destroy' do
    before do
      # Ensure user can access the RSS feed
      allow(user).to receive(:can_access_rss_feeds?).and_return(true)
      allow(user).to receive(:super_admin?).and_return(false)
      allow(user).to receive(:account_id).and_return(account.id)
    end

    it 'deletes RSS feed' do
      feed_id = rss_feed.id
      expect {
        delete :destroy, params: { id: feed_id }
      }.to change(RssFeed, :count).by(-1)
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('RSS feed deleted successfully')
    end
  end

  describe 'POST #fetch_posts' do
    before do
      stub_request(:get, rss_feed.url)
        .to_return(
          status: 200,
          body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>New Post</title><link>https://example.com/new</link></item></channel></rss>',
          headers: { 'Content-Type' => 'application/xml' }
        )
    end

    it 'fetches posts successfully' do
      post :fetch_posts, params: { id: rss_feed.id }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('Successfully fetched')
    end

    it 'handles fetch errors gracefully' do
      allow_any_instance_of(RssFetchService).to receive(:fetch_and_parse).and_return({
        success: false,
        error: 'Network error'
      })
      
      post :fetch_posts, params: { id: rss_feed.id }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Network error')
    end

    it 'handles exceptions gracefully' do
      allow_any_instance_of(RssFetchService).to receive(:fetch_and_parse).and_raise(StandardError.new('Service error'))
      
      post :fetch_posts, params: { id: rss_feed.id }
      
      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('Failed to fetch RSS feed')
    end
  end

  describe 'GET #posts' do
    before do
      create_list(:rss_post, 25, rss_feed: rss_feed, published_at: 1.hour.ago, is_viewed: false)
      create_list(:rss_post, 5, rss_feed: rss_feed, published_at: 1.hour.ago, is_viewed: true)
    end

    it 'returns paginated posts' do
      get :posts, params: { id: rss_feed.id, page: 1, per_page: 10 }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['posts'].length).to eq(10)
      expect(json_response['pagination']['total']).to eq(30)
    end

    it 'filters by viewed status' do
      get :posts, params: { id: rss_feed.id, viewed: 'true' }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['posts'].length).to eq(5)
    end

    it 'filters by unviewed status' do
      get :posts, params: { id: rss_feed.id, viewed: 'false' }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['posts'].length).to eq(20)
    end

    it 'uses default pagination' do
      get :posts, params: { id: rss_feed.id }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['pagination']['page']).to eq(1)
      expect(json_response['pagination']['per_page']).to eq(20)
    end
  end

  describe 'set_rss_feed' do
    context 'with super admin' do
      let(:super_admin) { create(:user, account_id: 0) }
      let(:other_feed) { create(:rss_feed) }

      before do
        allow(controller).to receive(:current_user).and_return(super_admin)
      end

      it 'allows access to any feed' do
        get :show, params: { id: other_feed.id }
        
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with account user' do
      it 'allows access to account feeds' do
        get :show, params: { id: rss_feed.id }
        
        expect(response).to have_http_status(:ok)
      end

      it 'denies access to other account feeds' do
        other_account = create(:account)
        other_feed = create(:rss_feed, account: other_account)
        
        get :show, params: { id: other_feed.id }
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'require_rss_access!' do
    context 'when user cannot access RSS' do
      before do
        account.account_feature.update!(allow_rss: false)
        # Remove the stub from the main before block for this test
        allow(controller).to receive(:require_rss_access!).and_call_original
        allow(controller).to receive(:current_user).and_return(user)
        allow(user).to receive(:can_access_rss_feeds?).and_return(false)
      end

      it 'returns forbidden' do
        get :index
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('RSS access not allowed')
      end
    end
  end

  describe 'JSON serializer methods' do
    describe '#rss_feed_json' do
      before do
        create_list(:rss_post, 5, rss_feed: rss_feed, is_viewed: false)
        create_list(:rss_post, 3, rss_feed: rss_feed, is_viewed: true)
      end

      it 'returns correct JSON structure' do
        json = controller.send(:rss_feed_json, rss_feed)
        expect(json).to have_key(:id)
        expect(json).to have_key(:url)
        expect(json).to have_key(:name)
        expect(json).to have_key(:description)
        expect(json).to have_key(:is_active)
        expect(json).to have_key(:status)
        expect(json).to have_key(:health_status)
        expect(json).to have_key(:last_fetched_at)
        expect(json).to have_key(:last_successful_fetch_at)
        expect(json).to have_key(:fetch_failure_count)
        expect(json).to have_key(:last_fetch_error)
        expect(json).to have_key(:posts_count)
        expect(json).to have_key(:unviewed_posts_count)
        expect(json).to have_key(:created_at)
        expect(json).to have_key(:updated_at)
        expect(json).to have_key(:account)
        expect(json).to have_key(:created_by)
        expect(json[:posts_count]).to eq(8)
        expect(json[:unviewed_posts_count]).to eq(5)
      end

      it 'includes account info when present' do
        json = controller.send(:rss_feed_json, rss_feed)
        expect(json[:account]).to be_a(Hash)
        expect(json[:account][:id]).to eq(account.id)
        expect(json[:account][:name]).to eq(account.name)
      end

      it 'handles nil account gracefully' do
        feed = create(:rss_feed, user: user, account: nil)
        json = controller.send(:rss_feed_json, feed)
        expect(json[:account]).to be_nil
      end

      it 'includes created_by user info' do
        json = controller.send(:rss_feed_json, rss_feed)
        expect(json[:created_by]).to be_a(Hash)
        expect(json[:created_by][:id]).to eq(user.id)
        expect(json[:created_by][:name]).to eq(user.name)
        expect(json[:created_by][:email]).to eq(user.email)
      end
    end
  end
end
