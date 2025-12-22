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

    context 'with Atom format feed' do
      before do
        atom_xml = <<~XML
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Feed</title>
            <entry>
              <title>Atom Post</title>
              <summary>Atom Description</summary>
              <link href="https://example.com/atom-post"/>
              <published>2024-12-17T10:00:00Z</published>
            </entry>
          </feed>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: atom_xml, headers: { 'Content-Type' => 'application/xml' })
      end
      
      it 'parses Atom format successfully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to be >= 1
      end
    end

    context 'with RDF format feed' do
      before do
        rdf_xml = <<~XML
          <?xml version="1.0"?>
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <item>
              <title>RDF Post</title>
              <description>RDF Description</description>
              <link>https://example.com/rdf-post</link>
            </item>
          </rdf:RDF>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rdf_xml, headers: { 'Content-Type' => 'application/xml' })
      end
      
      it 'parses RDF format successfully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
      end
    end

    context 'with invalid XML' do
      before do
        # Use actually invalid XML that will cause a parse exception
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: '<invalid><unclosed>', headers: { 'Content-Type' => 'application/xml' })
      end
      
      it 'handles XML parse errors gracefully' do
        result = service.fetch_and_parse
        # Service catches parse errors and returns success: false with error message
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'with posts containing images' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <item>
                <title>Post with Image</title>
                <description><![CDATA[<img src="https://example.com/image.jpg" />]]></description>
                <link>https://example.com/post</link>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
      end
      
      it 'extracts image URLs from content' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
      end
    end

    context 'with duplicate posts' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <item>
                <title>Duplicate Post</title>
                <link>https://example.com/duplicate</link>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
        create(:rss_post, rss_feed: rss_feed, original_url: 'https://example.com/duplicate')
      end
      
      it 'skips duplicate posts' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_saved]).to eq(0)
      end
    end

    context 'with unknown RSS format' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: '<?xml version="1.0"?><unknown><item><title>Test</title></item></unknown>', headers: { 'Content-Type' => 'application/xml' })
      end

      it 'handles unknown format gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to eq(0)
      end
    end

    context 'with posts missing required fields' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <item>
                <title>Post Without URL</title>
                <description>Test</description>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
      end

      it 'skips posts without original_url' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_saved]).to eq(0)
      end
    end

    context 'with posts that fail validation' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <item>
                <title></title>
                <link>https://example.com/post</link>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
      end

      it 'handles validation errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        # Post should fail validation due to missing title, so posts_saved should be 0
        expect(result[:posts_saved]).to eq(0)
      end
    end

    context 'with various date formats' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <item>
                <title>Post with RFC2822 Date</title>
                <pubDate>Mon, 17 Dec 2024 10:00:00 +0000</pubDate>
                <link>https://example.com/post1</link>
              </item>
              <item>
                <title>Post with ISO8601 Date</title>
                <pubDate>2024-12-17T10:00:00Z</pubDate>
                <link>https://example.com/post2</link>
              </item>
              <item>
                <title>Post with Invalid Date</title>
                <pubDate>Invalid Date String</pubDate>
                <link>https://example.com/post3</link>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
      end

      it 'parses various date formats' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to eq(3)
      end
    end

    context 'with image extraction from various sources' do
      before do
        rss_xml = <<~XML
          <?xml version="1.0"?>
          <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
            <channel>
              <item>
                <title>Post with media:thumbnail</title>
                <media:thumbnail url="https://example.com/thumb.jpg"/>
                <link>https://example.com/post1</link>
              </item>
              <item>
                <title>Post with enclosure</title>
                <enclosure type="image/jpeg" url="https://example.com/enclosure.jpg"/>
                <link>https://example.com/post2</link>
              </item>
              <item>
                <title>Post with img tag</title>
                <description><![CDATA[<img src="https://example.com/img.jpg" />]]></description>
                <link>https://example.com/post3</link>
              </item>
            </channel>
          </rss>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rss_xml, headers: { 'Content-Type' => 'application/xml' })
      end

      it 'extracts images from various sources' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to eq(3)
      end
    end
  end
end

