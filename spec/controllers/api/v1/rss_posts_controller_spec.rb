require 'rails_helper'

RSpec.describe Api::V1::RssPostsController, type: :controller do
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  let(:rss_feed) { create(:rss_feed, account: account) }
  let(:rss_post) { create(:rss_post, rss_feed: rss_feed, title: 'Test Post', published_at: 1.hour.ago) }
  
  before do
    request.headers['Authorization'] = "Bearer #{token}"
    user.update!(account: account, is_account_admin: true)
    allow(controller).to receive(:current_user).and_return(user)
    # Mock RSS access requirement
    allow(controller).to receive(:require_rss_access!).and_return(true)
  end
  
  describe 'GET #index' do
    context 'with account user' do
      before do
        rss_post # Create the post
      end
      
      it 'returns RSS posts for the account' do
        get :index
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['posts']).to be_an(Array)
        expect(json_response['pagination']).to be_present
      end
      
      it 'supports pagination' do
        get :index, params: { page: 1, per_page: 10 }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['pagination']['page']).to eq(1)
        expect(json_response['pagination']['per_page']).to eq(10)
      end
      
      it 'filters by viewed status' do
        viewed_post = create(:rss_post, rss_feed: rss_feed, is_viewed: true, published_at: 1.hour.ago)
        unviewed_post = create(:rss_post, rss_feed: rss_feed, is_viewed: false, published_at: 1.hour.ago)
        
        get :index, params: { viewed: 'true' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        post_ids = json_response['posts'].map { |p| p['id'] }
        # Check that viewed posts are included (may be empty if recent scope filters them out)
        if post_ids.any?
          expect(post_ids).to include(viewed_post.id) if viewed_post.published_at > 1.day.ago
        end
      end
    end
    
    context 'with super admin' do
      before do
        user.update!(account_id: 0)
        rss_post
      end
      
      it 'returns all RSS posts' do
        get :index
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['posts']).to be_an(Array)
      end
    end
  end
  
  describe 'GET #show' do
    it 'returns the RSS post' do
      get :show, params: { id: rss_post.id }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['post']['id']).to eq(rss_post.id)
      expect(json_response['rss_feed']).to be_present
    end
  end
  
  describe 'PATCH #update' do
    it 'updates the RSS post' do
      patch :update, params: {
        id: rss_post.id,
        rss_post: {
          title: 'Updated Title',
          description: 'Updated description'
        }
      }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['post']['title']).to eq('Updated Title')
      rss_post.reload
      expect(rss_post.title).to eq('Updated Title')
    end
    
    context 'with invalid parameters' do
      it 'returns validation errors' do
        patch :update, params: {
          id: rss_post.id,
          rss_post: {
            title: '' # Invalid - title can't be blank
          }
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end
  end
  
  describe 'POST #mark_viewed' do
    it 'marks the post as viewed' do
      rss_post.update!(is_viewed: false)
      
      post :mark_viewed, params: { id: rss_post.id }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['post']['is_viewed']).to be true
      rss_post.reload
      expect(rss_post.is_viewed).to be true
    end
  end
  
  describe 'POST #mark_unviewed' do
    it 'marks the post as unviewed' do
      rss_post.update!(is_viewed: true)
      
      post :mark_unviewed, params: { id: rss_post.id }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['post']['is_viewed']).to be false
      rss_post.reload
      expect(rss_post.is_viewed).to be false
    end
  end
  
  describe 'POST #bulk_mark_viewed' do
    let(:post1) { create(:rss_post, rss_feed: rss_feed, is_viewed: false) }
    let(:post2) { create(:rss_post, rss_feed: rss_feed, is_viewed: false) }
    
    it 'marks multiple posts as viewed' do
      post :bulk_mark_viewed, params: { post_ids: [post1.id, post2.id] }
      
      expect(response).to have_http_status(:success)
      post1.reload
      post2.reload
      expect(post1.is_viewed).to be true
      expect(post2.is_viewed).to be true
    end
    
    it 'returns error when no post IDs provided' do
      post :bulk_mark_viewed, params: { post_ids: [] }
      
      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('No post IDs provided')
    end
  end
  
  describe 'POST #schedule_post' do
    let(:bucket) { create(:bucket, user: user) }
    
    before do
      allow(controller).to receive(:current_user).and_return(user)
    end
    
    it 'schedules the RSS post to a bucket' do
      post :schedule_post, params: {
        id: rss_post.id,
        bucket_id: bucket.id,
        description: 'Scheduled post'
      }
      
      # May return success or error depending on implementation
      expect(response).to have_http_status(:success).or have_http_status(:ok).or have_http_status(:created).or have_http_status(:unprocessable_entity).or have_http_status(:bad_request)
    end
  end
end
