class Api::V1::ImagesController < ApplicationController
  # Skip authentication for image proxy (public images)
  skip_before_action :authenticate_user!, only: [:proxy]
  skip_before_action :require_active_subscription!, only: [:proxy]
  
  # Proxy endpoint to serve images from DigitalOcean Spaces with CORS headers
  # GET /api/v1/images/proxy?path=production/images/xxx.png
  def proxy
    path = params[:path]
    
    if path.blank?
      return render json: { error: 'Path parameter required' }, status: :bad_request
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
          
          # Set CORS headers
          headers = {
            'Content-Type' => content_type,
            'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'GET, OPTIONS',
            'Access-Control-Allow-Headers' => 'Content-Type',
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
  end
end
