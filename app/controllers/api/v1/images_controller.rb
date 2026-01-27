class Api::V1::ImagesController < ApplicationController
  # Skip authentication for image proxy (public images)
  skip_before_action :authenticate_user!, only: [:proxy, :proxy_options]
  skip_before_action :require_active_subscription!, only: [:proxy, :proxy_options]
  
  # Handle CORS preflight requests for image proxy
  def proxy_options
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS, HEAD'
    headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Range, Authorization'
    headers['Access-Control-Max-Age'] = '3600'
    head :ok
  end
  
  # POST /api/v1/images
  # Create an image record from a URL (for RSS feeds)
  def create
    # Handle both top-level params and nested image params
    file_path = params[:file_path] || params.dig(:image, :file_path)
    friendly_name = params[:friendly_name] || params.dig(:image, :friendly_name) || 'Untitled Image'
    
    if file_path.blank?
      return render json: { error: 'file_path is required' }, status: :bad_request
    end
    
    # Create image record with the URL as file_path
    # This is used for RSS feed images that are hosted externally
    image = Image.new(
      file_path: file_path,
      friendly_name: friendly_name
    )
    
    if image.save
      Rails.logger.info "Created image #{image.id} with file_path: #{image.file_path}"
      render json: {
        image: {
          id: image.id,
          file_path: image.file_path,
          friendly_name: image.friendly_name,
          source_url: image.get_source_url
        }
      }, status: :created
    else
      Rails.logger.error "Failed to create image: #{image.errors.full_messages.join(', ')}"
      render json: {
        errors: image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  # Proxy endpoint to serve images from DigitalOcean Spaces or external URLs with CORS headers
  # GET /api/v1/images/proxy?path=production/images/xxx.png
  # GET /api/v1/images/proxy?url=https://example.com/image.png (for external URLs)
  def proxy
    path = params[:path]
    url = params[:url]
    
    # Handle external URLs - decode if URL-encoded
    if url.present?
      require 'cgi'
      # Decode the URL if it's encoded (common when passed as query parameter)
      decoded_url = CGI.unescape(url.to_s)
      Rails.logger.info "Image proxy: Received URL param: #{url}, decoded: #{decoded_url}"
      
      if decoded_url.start_with?('http://') || decoded_url.start_with?('https://')
        Rails.logger.info "Image proxy: Proxying external URL: #{decoded_url}"
        proxy_external_url(decoded_url)
        return
      else
        Rails.logger.warn "Image proxy: Invalid URL format: #{decoded_url}"
        render json: { error: 'Invalid URL format - must start with http:// or https://' }, status: :bad_request
        return
      end
    end
    
    if path.blank?
      return render json: { error: 'Path or URL parameter required' }, status: :bad_request
    end
    
    # Get bucket name and endpoint
    bucket_name = ENV['DO_SPACES_BUCKET'] || ENV['DIGITAL_OCEAN_SPACES_NAME']
    endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://sfo2.digitaloceanspaces.com'
    endpoint = endpoint.chomp('/')
    
    Rails.logger.debug "Image proxy: bucket_name=#{bucket_name.present? ? 'SET' : 'NOT SET'}, endpoint=#{endpoint}, path=#{path}"
    
    # Handle different path formats
    if path.start_with?('uploads/')
      # Remove uploads/ prefix if present (for local files that were saved incorrectly)
      path = path.sub(/^uploads\//, '')
    end
    
    # Try multiple path variations if the file doesn't exist
    # Some files were saved incorrectly (missing images/ folder or extension)
    original_path = path.dup
    path_variations = []
    
    # Original path
    path_variations << path
    
    # If path doesn't have images/ folder, try adding it
    if !path.include?('/images/') && !path.start_with?('images/')
      if path.match(/^(production|development|test)\/([^\/]+)$/)
        # Path is like "production/filename" - try "production/images/filename"
        path_variations << path.sub(/\/([^\/]+)$/, '/images/\1')
      end
    end
    
    # If path has images/ folder, try without it (for incorrectly saved files)
    if path.include?('/images/')
      path_variations << path.sub('/images/', '/')
    end
    
    # Construct the base URL to DigitalOcean Spaces
    # DigitalOcean Spaces uses virtual-hosted-style: https://<bucket-name>.<region>.digitaloceanspaces.com/<key>
    base_url = nil
    if bucket_name.present?
      if endpoint.include?('digitaloceanspaces.com')
        # Extract the region/hostname from endpoint
        if endpoint.match(/https?:\/\/([^\/]+)\.digitaloceanspaces\.com/)
          endpoint_host = endpoint.match(/https?:\/\/([^\/]+)\.digitaloceanspaces\.com/)[1]
          # If endpoint_host is like "se1.sfo2", extract just "sfo2" (the region)
          region = endpoint_host.split('.').last
          base_url = "https://#{bucket_name}.#{region}.digitaloceanspaces.com/"
        else
          base_url = "https://#{bucket_name}.sfo2.digitaloceanspaces.com/"
        end
      else
        base_url = "#{endpoint}/#{bucket_name}/"
      end
    else
      Rails.logger.warn "Image proxy: No bucket name configured, using endpoint directly (may fail)"
      base_url = "#{endpoint}/"
    end
    
    # Try each path variation until one works
    require 'net/http'
    require 'uri'
    
    last_error = nil
    path_variations.each do |try_path|
      image_url = "#{base_url}#{try_path}"
      
      begin
        uri = URI(image_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        
        Rails.logger.info "Image proxy: Fetching #{image_url}, response code: #{response.code}"
        
        if response.code == '200'
          # Determine content type
          content_type = response.content_type || Rack::Mime.mime_type(File.extname(try_path)) || 'image/jpeg'
          
          # Set CORS headers - critical for canvas manipulation
          # Must set on response.headers first, then pass to send_data
          response.headers['Access-Control-Allow-Origin'] = '*'
          response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS, HEAD'
          response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Range'
          response.headers['Access-Control-Expose-Headers'] = 'Content-Length, Content-Type'
          
          headers = {
            'Content-Type' => content_type,
            'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'GET, OPTIONS, HEAD',
            'Access-Control-Allow-Headers' => 'Content-Type, Accept, Range',
            'Access-Control-Expose-Headers' => 'Content-Length, Content-Type',
            'Cache-Control' => 'public, max-age=31536000' # Cache for 1 year
          }
          
          send_data response.body, type: content_type, disposition: 'inline', headers: headers
          return # Success - exit early
        end
      rescue => e
        last_error = e
        Rails.logger.debug "Image proxy: Failed to fetch #{image_url}: #{e.message}"
      end
    end
    
    # If we get here, all variations failed
    Rails.logger.error "Image proxy: All path variations failed for path: #{original_path}"
    render json: { error: 'Image not found' }, status: :not_found
  rescue => e
    Rails.logger.error "Image proxy error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'Failed to fetch image' }, status: :internal_server_error
  end
  
  # Proxy external URLs (for RSS feed images and other external sources)
  def proxy_external_url(image_url)
    require 'net/http'
    require 'uri'
    require 'cgi'
    
    begin
      Rails.logger.info "Image proxy: Attempting to fetch external URL: #{image_url}"
      
      # Parse the URI - handle encoding issues
      begin
        uri = URI.parse(image_url)
      rescue URI::InvalidURIError => e
        Rails.logger.error "Image proxy: Invalid URI: #{image_url}, error: #{e.message}"
        render json: { error: "Invalid URL format: #{e.message}" }, status: :bad_request
        return
      end
      
      # Validate URI
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        Rails.logger.error "Image proxy: URI is not HTTP/HTTPS: #{uri.class}"
        render json: { error: 'URL must be HTTP or HTTPS' }, status: :bad_request
        return
      end
      
      Rails.logger.info "Image proxy: Parsed URI - scheme: #{uri.scheme}, host: #{uri.host}, path: #{uri.path}"
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      http.read_timeout = 10 # 10 second timeout
      http.open_timeout = 5  # 5 second connection timeout
      
      request = Net::HTTP::Get.new(uri.request_uri)
      # Set a user agent to avoid blocking
      request['User-Agent'] = 'Mozilla/5.0 (compatible; SocialRotation/1.0)'
      request['Accept'] = 'image/*'
      
      Rails.logger.info "Image proxy: Making HTTP request to #{uri.host}#{uri.path}"
      response = http.request(request)
      
      Rails.logger.info "Image proxy: Fetching external URL #{image_url}, response code: #{response.code}"
      
      if response.code == '200'
        # Determine content type from response or file extension
        content_type = response.content_type
        if content_type.blank? || content_type == 'application/octet-stream'
          # Try to determine from URL
          ext = File.extname(uri.path).downcase
          content_type = case ext
                        when '.png' then 'image/png'
                        when '.jpg', '.jpeg' then 'image/jpeg'
                        when '.gif' then 'image/gif'
                        when '.webp' then 'image/webp'
                        else 'image/jpeg'
                        end
        end
        
        # Validate that we actually got image data
        if response.body.blank? || response.body.length < 100
          Rails.logger.error "Image proxy: External URL returned empty or too small response: #{image_url}, body size: #{response.body&.length || 0}"
          render json: { error: 'Image data is invalid or empty' }, status: :bad_request
          return
        end
        
        Rails.logger.info "Image proxy: Serving external image with content-type: #{content_type}, size: #{response.body.length} bytes"
        
        # Set CORS headers on Rails response object (not Net::HTTP response)
        # This is critical for canvas manipulation in react-easy-crop
        # The Cropper component uses HTML5 Canvas which requires proper CORS headers
        headers['Access-Control-Allow-Origin'] = '*'
        headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS, HEAD'
        headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Range, Authorization'
        headers['Access-Control-Expose-Headers'] = 'Content-Length, Content-Type'
        headers['Cache-Control'] = 'public, max-age=3600'
        
        # Pass headers to send_data
        send_data response.body, type: content_type, disposition: 'inline', headers: headers
      else
        Rails.logger.error "Image proxy: Failed to fetch external URL #{image_url}, response code: #{response.code}, body preview: #{response.body[0..200] if response.body}"
        render json: { error: "Failed to fetch image: HTTP #{response.code}" }, status: :bad_gateway
      end
    rescue => e
      Rails.logger.error "Image proxy error for external URL #{image_url}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Failed to fetch image: #{e.message}" }, status: :internal_server_error
    end
  end
end
