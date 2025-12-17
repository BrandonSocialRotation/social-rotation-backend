require 'rails_helper'

RSpec.describe RssFetchService do
  let(:rss_feed) { create(:rss_feed, url: 'https://example.com/feed.xml') }
  let(:service) { RssFetchService.new(rss_feed) }
  
  describe '#fetch_and_parse' do
    context 'with valid RSS feed' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(
            status: 200,
            body: '<?xml version="1.0"?><rss version="2.0"><channel><title>Test Feed</title><item><title>Test Post</title><description>Test Description</description><link>https://example.com/post</link></item></channel></rss>',
            headers: { 'Content-Type' => 'application/xml' }
          )
      end
      
      it 'fetches and parses RSS feed successfully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to be >= 0
      end
    end
    
    context 'with invalid URL' do
      before do
        rss_feed.update(url: 'not-a-valid-url')
      end
      
      it 'handles invalid URL gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
        expect(result).to have_key(:error)
      end
    end
    
    context 'with network error' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_raise(StandardError.new('Network error'))
      end
      
      it 'handles network errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
        expect(result).to have_key(:error)
      end
    end
    
    context 'with HTTP error' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 404, body: 'Not Found')
      end
      
      it 'handles HTTP errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
      end
    end
  end
end

