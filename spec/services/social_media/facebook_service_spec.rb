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

    context 'when API response is not successful' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 500, body: 'Internal Server Error')
        allow(Rails.logger).to receive(:error)
      end
      
      it 'returns empty array' do
        pages = service.fetch_pages
        expect(pages).to eq([])
        expect(Rails.logger).to have_received(:error).with(match(/Facebook fetch_pages error/))
      end
    end

    context 'when response data is empty' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [] }.to_json)
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/debug_token/)
          .to_return(status: 200, body: { data: { is_valid: true } }.to_json)
      end
      
      it 'returns empty array when no pages' do
        pages = service.fetch_pages
        expect(pages).to eq([])
      end
    end

    context 'when exception is RuntimeError but not authentication error' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_raise(RuntimeError.new('Some other error'))
        allow(Rails.logger).to receive(:error)
      end
      
      it 'raises User does not have Facebook connected error' do
        expect {
          service.fetch_pages
        }.to raise_error(/User does not have Facebook connected/)
      end
    end

    context 'when exception is not RuntimeError' do
      before do
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_raise(StandardError.new('Network error'))
        allow(Rails.logger).to receive(:error)
      end
      
      it 'returns empty array' do
        pages = service.fetch_pages
        expect(pages).to eq([])
        expect(Rails.logger).to have_received(:error).with(match(/Facebook fetch_pages error/))
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

    context 'when page access token cannot be retrieved' do
      before do
        user.update(instagram_business_id: 'ig_id')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [] }.to_json)
      end
      
      it 'raises an error' do
        expect {
          service.post_to_instagram('Test', 'https://example.com/image.jpg')
        }.to raise_error(/Could not get Facebook page access token for Instagram/)
      end
    end

    context 'with video media' do
      before do
        user.update(instagram_business_id: 'ig_id')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media/)
          .to_return(status: 200, body: { id: 'container123' }.to_json)
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
          .to_return(status: 200, body: { status_code: 'FINISHED' }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media_publish/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
      end
      
      it 'posts video to Instagram' do
        result = service.post_to_instagram('Test video', 'https://example.com/video.mp4', is_video: true)
        expect(result).to have_key('id')
      end
    end

    context 'when media container creation fails' do
      before do
        user.update(instagram_business_id: 'ig_id')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media/)
          .to_return(status: 400, body: { error: { message: 'Invalid media' } }.to_json)
      end
      
      it 'raises an error' do
        expect {
          service.post_to_instagram('Test', 'https://example.com/image.jpg')
        }.to raise_error(/Failed to create Instagram media container/)
      end
    end
  end

  describe '#post_photo with video extension' do
    before do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
        .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
      stub_request(:post, /graph\.facebook\.com\/v18\.0\/me\/videos/)
        .to_return(status: 200, body: { id: 'video123' }.to_json)
    end
    
    it 'posts video when URL has .mp4 extension' do
      result = service.post_photo('Test video', 'https://example.com/video.mp4')
      expect(result).to have_key('id')
    end

    it 'posts video when URL has .gif extension' do
      result = service.post_photo('Test gif', 'https://example.com/animation.gif')
      expect(result).to have_key('id')
    end
  end

  describe '#get_page_access_token' do
    it 'returns first page token when pages exist' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
        .to_return(status: 200, body: { data: [{ id: 'page1', access_token: 'token1' }, { id: 'page2', access_token: 'token2' }] }.to_json)
      
      token = service.send(:get_page_access_token)
      expect(token).to eq('token1')
    end

    it 'returns nil when no pages exist' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
        .to_return(status: 200, body: { data: [] }.to_json)
      
      token = service.send(:get_page_access_token)
      expect(token).to be_nil
    end
  end

  describe '#wait_for_video_processing' do
    before do
      user.update(instagram_business_id: 'ig_id')
    end

    it 'waits for video to finish processing' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
        .to_return(status: 200, body: { status_code: 'FINISHED' }.to_json)
      
      result = service.send(:wait_for_video_processing, 'container123', 'page_token', 10)
      expect(result).to be true
    end

    it 'raises error when video processing fails' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
        .to_return(status: 200, body: { status_code: 'ERROR', error: { message: 'Processing failed' } }.to_json)
      
      expect {
        service.send(:wait_for_video_processing, 'container123', 'page_token', 10)
      }.to raise_error(/Instagram video processing failed/)
    end

    it 'raises timeout error when processing takes too long' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
        .to_return(status: 200, body: { status_code: 'IN_PROGRESS' }.to_json)
      
      expect {
        service.send(:wait_for_video_processing, 'container123', 'page_token', 1)
      }.to raise_error(/timeout/)
    end

    it 'handles IN_PROGRESS status and continues waiting' do
      call_count = 0
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
        .to_return do |request|
          call_count += 1
          if call_count < 3
            { status: 200, body: { status_code: 'IN_PROGRESS' }.to_json }
          else
            { status: 200, body: { status_code: 'FINISHED' }.to_json }
          end
        end
      
      result = service.send(:wait_for_video_processing, 'container123', 'page_token', 10)
      expect(result).to be true
    end

    it 'handles API errors during status check' do
      stub_request(:get, /graph\.facebook\.com\/v18\.0\/container123/)
        .to_return(status: 400, body: { error: { message: 'API error' } }.to_json)
      
      expect {
        service.send(:wait_for_video_processing, 'container123', 'page_token', 10)
      }.to raise_error(/Instagram video processing/)
    end
  end
end

