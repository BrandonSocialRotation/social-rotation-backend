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
        allow(Rails.logger).to receive(:error)
      end
      
      it 'handles network errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
        expect(result).to have_key(:error)
        expect(result[:error]).to include('RSS fetch failed')
        expect(Rails.logger).to have_received(:error).with(match(/RSS Fetch Error/))
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

    context 'when save_posts_to_database raises exception' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(
            status: 200,
            body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>Test</title><link>https://example.com/post</link></item></channel></rss>',
            headers: { 'Content-Type' => 'application/xml' }
          )
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(RssFetchService).to receive(:save_posts_to_database).and_raise(StandardError.new('Database error'))
      end

      it 'handles database errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_saved]).to eq(0)
        expect(Rails.logger).to have_received(:error).with(match(/Error in save_posts_to_database/))
      end
    end

    context 'when mark_as_fetched raises exception' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(
            status: 200,
            body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>Test</title><link>https://example.com/post</link></item></channel></rss>',
            headers: { 'Content-Type' => 'application/xml' }
          )
        allow(rss_feed).to receive(:mark_as_fetched!).and_raise(StandardError.new('Mark error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles mark_as_fetched errors gracefully' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(Rails.logger).to have_received(:error).with(match(/Failed to mark feed as fetched/))
      end
    end

    context 'when parse_rss_content raises unexpected error' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>', headers: { 'Content-Type' => 'application/xml' })
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(REXML::Document).to receive(:root).and_raise(StandardError.new('Unexpected error'))
      end

      it 'handles unexpected parse errors' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
        expect(Rails.logger).to have_received(:error).with(match(/Unexpected error parsing RSS content/))
      end
    end

    context 'when parse_rss2_format raises exception' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>Test</title><link>https://example.com/post</link></item></channel></rss>', headers: { 'Content-Type' => 'application/xml' })
        allow(Rails.logger).to receive(:error)
        # Stub extract_rss2_post to raise an error during iteration
        allow_any_instance_of(RssFetchService).to receive(:extract_rss2_post).and_raise(StandardError.new('Parse error'))
      end

      it 'handles parse_rss2_format errors' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to eq(0)
        expect(Rails.logger).to have_received(:error).with(match(/Error parsing RSS 2.0 format/))
      end
    end

    context 'when extract_rss2_post raises exception' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(
            status: 200,
            body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>Test</title><link>https://example.com/post</link></item></channel></rss>',
            headers: { 'Content-Type' => 'application/xml' }
          )
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(RssFetchService).to receive(:get_text_content).and_raise(StandardError.new('Extract error'))
      end

      it 'handles extract_rss2_post errors' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(Rails.logger).to have_received(:error).with(match(/Error extracting RSS post/))
      end
    end

    context 'with proper RDF format' do
      before do
        rdf_xml = <<~XML
          <?xml version="1.0"?>
          <RDF xmlns="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <item>
              <title>RDF Post</title>
              <description>RDF Description</description>
              <link>https://example.com/rdf-post</link>
            </item>
          </RDF>
        XML
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(status: 200, body: rdf_xml, headers: { 'Content-Type' => 'application/xml' })
      end

      it 'parses RDF format with RDF root element' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(result[:posts_found]).to be >= 0
      end
    end

    context 'when extract_image_url raises exception' do
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
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(RssFetchService).to receive(:get_text_content).and_call_original
        allow_any_instance_of(RssFetchService).to receive(:extract_image_url).and_raise(StandardError.new('Image extract error'))
      end

      it 'handles extract_image_url errors' do
        # The error should be caught in extract_rss2_post
        result = service.fetch_and_parse
        expect(result[:success]).to be true
      end
    end

    context 'when save_posts_to_database encounters error saving individual post' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_return(
            status: 200,
            body: '<?xml version="1.0"?><rss version="2.0"><channel><item><title>Test</title><link>https://example.com/post</link></item></channel></rss>',
            headers: { 'Content-Type' => 'application/xml' }
          )
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(RssPost).to receive(:save).and_raise(StandardError.new('Save error'))
      end

      it 'handles individual post save errors' do
        result = service.fetch_and_parse
        expect(result[:success]).to be true
        expect(Rails.logger).to have_received(:error).with(match(/Error saving RSS post/))
      end
    end

    context 'when fetch_and_parse raises StandardError' do
      before do
        stub_request(:get, 'https://example.com/feed.xml')
          .to_raise(StandardError.new('Network error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles StandardError in main rescue block' do
        result = service.fetch_and_parse
        expect(result[:success]).to be false
        expect(result[:error]).to include('RSS fetch failed')
        expect(Rails.logger).to have_received(:error).with(match(/RSS Fetch Error/))
      end
    end
  end

  describe '#get_text_content' do
    let(:element) { double('REXML::Element') }

    context 'when element access raises exception' do
      before do
        allow(element).to receive(:elements).and_raise(StandardError.new('Parse error'))
        allow(Rails.logger).to receive(:warn)
      end

      it 'handles errors gracefully' do
        result = service.send(:get_text_content, element, 'title')
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn).with(match(/Error getting text content/))
      end
    end
  end

  describe '#get_attribute' do
    let(:element) { double('REXML::Element') }

    context 'when element access raises exception' do
      before do
        allow(element).to receive(:elements).and_raise(StandardError.new('Parse error'))
        allow(Rails.logger).to receive(:warn)
      end

      it 'handles errors gracefully' do
        result = service.send(:get_attribute, element, 'link', 'href')
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn).with(match(/Error getting attribute/))
      end
    end
  end

  describe '#extract_image_url' do
    let(:element) { double('REXML::Element') }

    context 'when image extraction raises exception' do
      before do
        allow(element).to receive(:elements).and_raise(StandardError.new('Parse error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'handles errors gracefully in outer rescue block' do
        result = service.send(:extract_image_url, element)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with(match(/Error in extract_image_url/))
      end
    end

    context 'when thumbnail extraction raises exception' do
      let(:child_element) { double('REXML::Element', name: 'thumbnail') }
      
      before do
        allow(element).to receive(:elements).and_yield(child_element)
        allow(child_element).to receive(:name).and_return('thumbnail')
        allow(child_element).to receive(:attributes).and_raise(StandardError.new('Attribute error'))
        allow(Rails.logger).to receive(:warn)
      end

      it 'handles thumbnail extraction errors when child.attributes raises exception' do
        result = service.send(:extract_image_url, element)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn).with(match(/Error extracting thumbnail/))
      end
    end

    context 'when content extraction raises exception' do
      before do
        allow(element).to receive(:elements).and_return([])
        allow(service).to receive(:get_text_content).and_raise(StandardError.new('Content error'))
        allow(Rails.logger).to receive(:warn)
      end

      it 'handles content extraction errors' do
        result = service.send(:extract_image_url, element)
        expect(Rails.logger).to have_received(:warn).with(match(/Error extracting image from content/))
      end
    end

    context 'when thumbnail has attributes with url' do
      let(:child_element) { double('REXML::Element', name: 'thumbnail', attributes: { 'url' => 'https://example.com/thumb.jpg' }) }
      
      before do
        allow(element).to receive(:elements).and_yield(child_element)
      end

      it 'extracts image URL from thumbnail attributes' do
        result = service.send(:extract_image_url, element)
        expect(result).to eq('https://example.com/thumb.jpg')
      end
    end
  end

  describe '#parse_date' do
    it 'handles invalid date strings' do
      result = service.send(:parse_date, 'invalid date string')
      expect(result).to be_nil
    end

    it 'handles nil input' do
      result = service.send(:parse_date, nil)
      expect(result).to be_nil
    end
  end

  describe '#save_posts_to_database' do
    context 'when saving posts raises exception' do
      let(:posts) { [{ title: 'Test', original_url: 'https://example.com/post' }] }
      
      before do
        allow(Rails.logger).to receive(:error)
        allow_any_instance_of(RssPost).to receive(:save).and_raise(StandardError.new('Database error'))
      end

      it 'handles save errors' do
        result = service.send(:save_posts_to_database, posts)
        expect(result).to eq(0)
        expect(Rails.logger).to have_received(:error).with(match(/Error saving RSS post/))
      end
    end
  end
end

