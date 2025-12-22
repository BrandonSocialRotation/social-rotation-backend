# RSS Fetch Service
# Handles fetching and parsing RSS feeds to extract posts
# Supports RSS 2.0, Atom, and other common RSS formats
class RssFetchService
  require 'net/http'
  require 'uri'
  require 'rexml/document'
  require 'open-uri'

  def initialize(rss_feed)
    @rss_feed = rss_feed
    @url = rss_feed.url
  end

  # Main method to fetch and parse RSS feed
  def fetch_and_parse
    begin
      # Fetch the RSS content
      content = fetch_rss_content
      return { success: false, error: 'Failed to fetch RSS content' } unless content

      # Parse the RSS content
      posts = parse_rss_content(content)
      # Return success: false only if parsing actually failed (nil), not if posts array is empty
      return { success: false, error: 'Failed to parse RSS content' } if posts.nil?

      # Save posts to database
      begin
        saved_posts = save_posts_to_database(posts)
      rescue => e
        Rails.logger.error "Error in save_posts_to_database: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        saved_posts = 0
      end
      
      # Update feed status (wrap in rescue to handle any errors)
      begin
        @rss_feed.mark_as_fetched!
      rescue => e
        Rails.logger.error "Failed to mark feed as fetched: #{e.message}"
        # Continue anyway - this is not critical
      end
      
      {
        success: true,
        posts_found: posts.length,
        posts_saved: saved_posts,
        message: "Successfully fetched #{saved_posts} new posts"
      }
    rescue StandardError => e
      Rails.logger.error "RSS Fetch Error for #{@url}: #{e.message}"
      {
        success: false,
        error: "RSS fetch failed: #{e.message}"
      }
    end
  end

  private

  # Fetch RSS content from URL
  def fetch_rss_content
    uri = URI.parse(@url)
    
    # Set up HTTP request with proper headers
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30
    http.open_timeout = 10
    
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'Social Rotation RSS Fetcher/1.0'
    request['Accept'] = 'application/rss+xml, application/xml, text/xml, */*'
    
    response = http.request(request)
    
    if response.code == '200'
      response.body
    else
      Rails.logger.error "HTTP Error #{response.code} for #{@url}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "Network error fetching #{@url}: #{e.message}"
    nil
  end

  # Parse RSS content and extract posts
  def parse_rss_content(content)
    posts = []
    
    begin
      doc = REXML::Document.new(content)
      
      # Try RSS 2.0 format first
      if doc.root&.name == 'rss'
        posts = parse_rss2_format(doc)
      # Try Atom format
      elsif doc.root&.name == 'feed'
        posts = parse_atom_format(doc)
      # Try RDF format
      elsif doc.root&.name == 'RDF'
        posts = parse_rdf_format(doc)
      else
        Rails.logger.warn "Unknown RSS format for #{@url}: root element is #{doc.root&.name}"
        return [] # Return empty array for unknown formats (not a parse failure, just no posts found)
      end
      
      posts
    rescue REXML::ParseException => e
      Rails.logger.error "XML Parse Error for #{@url}: #{e.message}"
      nil # Return nil to indicate parse failure
    rescue => e
      Rails.logger.error "Unexpected error parsing RSS content: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil # Return nil to indicate parse failure
    end
  end

  # Parse RSS 2.0 format
  def parse_rss2_format(doc)
    posts = []
    
    begin
      doc.elements.each('rss/channel/item') do |item|
        post = extract_rss2_post(item)
        # Only add post if it has required fields (original_url is required for saving)
        posts << post if post && post[:original_url].present?
      end
    rescue => e
      Rails.logger.error "Error parsing RSS 2.0 format: #{e.message}"
      # Return empty array on error, not nil (so it's not treated as parse failure)
      return []
    end
    
    posts
  end

  # Parse Atom format
  def parse_atom_format(doc)
    posts = []
    
    doc.elements.each('feed/entry') do |entry|
      post = extract_atom_post(entry)
      posts << post if post
    end
    
    posts
  end

  # Parse RDF format
  def parse_rdf_format(doc)
    posts = []
    
    doc.elements.each('RDF/item') do |item|
      post = extract_rdf_post(item)
      posts << post if post
    end
    
    posts
  end

  # Extract post data from RSS 2.0 item
  def extract_rss2_post(item)
    begin
      {
        title: get_text_content(item, 'title'),
        description: get_text_content(item, 'description'),
        content: get_text_content(item, 'content:encoded') || get_text_content(item, 'description'),
        image_url: extract_image_url(item),
        original_url: get_text_content(item, 'link'),
        published_at: parse_date(get_text_content(item, 'pubDate'))
      }
    rescue => e
      Rails.logger.error "Error extracting RSS post: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  # Extract post data from Atom entry
  def extract_atom_post(entry)
    {
      title: get_text_content(entry, 'title'),
      description: get_text_content(entry, 'summary'),
      content: get_text_content(entry, 'content') || get_text_content(entry, 'summary'),
      image_url: extract_image_url(entry),
      original_url: get_attribute(entry, 'link', 'href') || get_text_content(entry, 'id'),
      published_at: parse_date(get_text_content(entry, 'published')) || parse_date(get_text_content(entry, 'updated'))
    }
  end

  # Extract post data from RDF item
  def extract_rdf_post(item)
    {
      title: get_text_content(item, 'title'),
      description: get_text_content(item, 'description'),
      content: get_text_content(item, 'content:encoded') || get_text_content(item, 'description'),
      image_url: extract_image_url(item),
      original_url: get_text_content(item, 'link'),
      published_at: parse_date(get_text_content(item, 'dc:date'))
    }
  end

  # Helper method to get text content from XML element
  def get_text_content(element, xpath)
    begin
      text = element.elements[xpath]&.text
      text&.strip
    rescue => e
      Rails.logger.warn "Error getting text content from #{xpath}: #{e.message}"
      nil
    end
  end

  # Helper method to get attribute value
  def get_attribute(element, xpath, attribute)
    begin
      elem = element.elements[xpath]
      return nil unless elem && elem.attributes
      elem.attributes[attribute]
    rescue => e
      Rails.logger.warn "Error getting attribute #{attribute} from #{xpath}: #{e.message}"
      nil
    end
  end

  # Extract image URL from post content
  def extract_image_url(element)
    # Try to find image in various places
    image_url = nil
    
    begin
      # Check for media:thumbnail (RSS 2.0 with media extensions)
      # Handle both with and without namespace prefix
      ['media:thumbnail', 'thumbnail'].each do |xpath|
        image_url = get_attribute(element, xpath, 'url')
        break if image_url
      end
      
      # Also try direct element iteration for media:thumbnail (handles namespaces)
      if image_url.nil?
        begin
          element.elements.each do |child|
            # Check if element name matches thumbnail (with or without namespace prefix)
            if child.name == 'thumbnail' || child.name == 'media:thumbnail' || child.name.end_with?(':thumbnail')
              image_url = child.attributes['url'] if child.attributes && child.attributes['url']
              break if image_url
            end
          end
        rescue => e
          Rails.logger.warn "Error extracting thumbnail: #{e.message}"
          # Continue to try other methods
        end
      end
      
      # Check for enclosure with image type
      if image_url.nil?
        begin
          element.elements.each('enclosure') do |enclosure|
            next unless enclosure.attributes
            type = enclosure.attributes['type']
            if type&.start_with?('image/')
              image_url = enclosure.attributes['url']
              break
            end
          end
        rescue => e
          Rails.logger.warn "Error extracting enclosure: #{e.message}"
        end
      end
      
      # Extract from content/description HTML
      if image_url.nil?
        begin
          content = get_text_content(element, 'content:encoded') || 
                    get_text_content(element, 'description') || 
                    get_text_content(element, 'content')
          
          if content
            # Simple regex to find first img tag
            img_match = content.match(/<img[^>]+src=["']([^"']+)["'][^>]*>/i)
            image_url = img_match[1] if img_match && img_match[1]
          end
        rescue => e
          Rails.logger.warn "Error extracting image from content: #{e.message}"
        end
      end
    rescue => e
      Rails.logger.error "Error in extract_image_url: #{e.message}"
      image_url = nil
    end
    
    image_url
  end

  # Parse date string to DateTime
  def parse_date(date_string)
    return nil unless date_string
    
    begin
      # Try various date formats
      DateTime.parse(date_string)
    rescue ArgumentError
      begin
        # Try RFC 2822 format
        DateTime.rfc2822(date_string)
      rescue ArgumentError
        begin
          # Try ISO 8601 format
          DateTime.iso8601(date_string)
        rescue ArgumentError
          Rails.logger.warn "Could not parse date: #{date_string}"
          nil
        end
      end
    end
  end

  # Save posts to database
  def save_posts_to_database(posts)
    saved_count = 0
    
    posts.each do |post_data|
      begin
        # Skip if post already exists (check by original_url)
        next if post_data[:original_url].blank? || 
                @rss_feed.rss_posts.exists?(original_url: post_data[:original_url])
        
        # Create new RSS post
        rss_post = @rss_feed.rss_posts.build(
          title: post_data[:title],
          description: post_data[:description],
          content: post_data[:content],
          image_url: post_data[:image_url],
          original_url: post_data[:original_url],
          published_at: post_data[:published_at] || Time.current,
          is_viewed: false
        )
        
        if rss_post.save
          saved_count += 1
          Rails.logger.info "Saved RSS post: #{rss_post.title}"
        else
          Rails.logger.error "Failed to save RSS post: #{rss_post.errors.full_messages.join(', ')}"
        end
      rescue => e
        Rails.logger.error "Error saving RSS post: #{e.message}"
        # Continue to next post
      end
    end
    
    saved_count
  end
end
