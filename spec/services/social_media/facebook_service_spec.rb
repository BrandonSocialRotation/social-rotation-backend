require 'rails_helper'

RSpec.describe SocialMedia::FacebookService do
  let(:user) { create(:user, fb_user_access_key: 'test_token') }
  let(:service) { SocialMedia::FacebookService.new(user) }
  
  before do
    stub_request(:get, /graph\.facebook\.com/).to_return(status: 200, body: '{}')
    stub_request(:post, /graph\.facebook\.com/).to_return(status: 200, body: '{"id": "123"}')
  end
  
  describe '#post_photo' do
    context 'when user has Facebook connected' do
      it 'posts photo successfully' do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/page123\/photos/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
        
        result = service.post_photo('Test message', 'https://example.com/image.jpg')
        expect(result).to have_key('id')
      end
    end
    
    context 'when user does not have Facebook connected' do
      before do
        user.update(fb_user_access_key: nil)
      end
      
      it 'raises an error' do
        expect {
          service.post_photo('Test', 'https://example.com/image.jpg')
        }.to raise_error(/does not have Facebook connected/)
      end
    end
  end
  
  describe '#fetch_pages' do
    context 'when user has Facebook connected' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: {
            data: [
              { id: 'page1', name: 'Page 1', access_token: 'token1' },
              { id: 'page2', name: 'Page 2', access_token: 'token2' }
            ]
          }.to_json)
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/debug_token/)
          .to_return(status: 200, body: { data: { is_valid: true, scopes: ['pages_manage_posts'] } }.to_json)
      end
      
      it 'fetches pages successfully' do
        pages = service.fetch_pages
        expect(pages).to be_an(Array)
        expect(pages.length).to eq(2)
        expect(pages.first).to have_key(:id)
        expect(pages.first).to have_key(:name)
        expect(pages.first).to have_key(:access_token)
      end
    end
    
    context 'when user does not have Facebook connected' do
      before do
        user.update(fb_user_access_key: nil)
      end
      
      it 'raises an error' do
        expect {
          service.fetch_pages
        }.to raise_error(/does not have Facebook connected/)
      end
    end
    
    context 'with API errors' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 400, body: { error: { message: 'Invalid token', code: 190 } }.to_json)
      end
      
      it 'raises an error with helpful message' do
        expect {
          service.fetch_pages
        }.to raise_error(/Facebook/)
      end
    end
  end
  
  describe '#post_to_instagram' do
    context 'when user has Instagram connected' do
      before do
        user.update(instagram_business_id: 'ig_id')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token', instagram_business_account: { id: 'ig_id' } }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media/)
          .to_return(status: 200, body: { id: 'container123' }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media_publish/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
      end
      
      it 'posts to Instagram successfully' do
        result = service.post_to_instagram('Test caption', 'https://example.com/image.jpg')
        expect(result).to have_key('id')
      end
    end
    
    context 'when user does not have Instagram connected' do
      before do
        user.update(instagram_business_id: nil)
      end
      
      it 'raises an error' do
        expect {
          service.post_to_instagram('Test', 'https://example.com/image.jpg')
        }.to raise_error(/does not have Instagram connected/)
      end
    end
  end
end

