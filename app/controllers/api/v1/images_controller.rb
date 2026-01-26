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
    
    # Ensure path has images/ folder if it's missing (for incorrectly saved files)
    if !path.include?('/images/') && !path.start_with?('images/')
      # If path is just "production/{filename}", add "images/" folder
      if path.match(/^(production|development|test)\/[^\/]+$/)
        path = path.sub(/\/([^\/]+)$/, '/images/\1')
      end
    end
    
    # Construct the full URL to DigitalOcean Spaces
    # DigitalOcean Spaces uses virtual-hosted-style: https://<bucket-name>.<region>.digitaloceanspaces.com/<key>
    if bucket_name.present?
      if endpoint.include?('digitaloceanspaces.com')
        # Extract the full hostname from endpoint (e.g., "sfo2" or "se1.sfo2" from https://sfo2.digitaloceanspaces.com or https://se1.sfo2.digitaloceanspaces.com)
        # Match everything between https:// and .digitaloceanspaces.com
        if endpoint.match(/https?:\/\/([^\/]+)\.digitaloceanspaces\.com/)
          region_part = endpoint.match(/https?:\/\/([^\/]+)\.digitaloceanspaces\.com/)[1]
          image_url = "https://#{bucket_name}.#{region_part}.digitaloceanspaces.com/#{path}"
        else
          # Fallback: try to extract just the region (last part before .digitaloceanspaces.com)
          # For se1.sfo2, we want sfo2; for sfo2, we want sfo2
          region_part = endpoint.split('.').first.split('//').last rescue 'sfo2'
          image_url = "https://#{bucket_name}.#{region_part}.digitaloceanspaces.com/#{path}"
        end
      else
        # Use path-style if endpoint is custom
        image_url = "#{endpoint}/#{bucket_name}/#{path}"
      end
    else
      Rails.logger.warn "Image proxy: No bucket name configured, using endpoint directly (may fail)"
      # Fallback: try without bucket name (will likely fail but worth trying)
      image_url = "#{endpoint}/#{path}"
    end
    
    begin
      # Fetch the image from DigitalOcean Spaces
      require 'net/http'
      require 'uri'
      
      uri = URI(image_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      
      Rails.logger.info "Image proxy: Fetching #{image_url}, response code: #{response.code}"
      
      if response.code == '200'
        # Determine content type
        content_type = response.content_type || Rack::Mime.mime_type(File.extname(path))
        
        # Set CORS headers
        headers = {
          'Content-Type' => content_type,
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'GET, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type',
          'Cache-Control' => 'public, max-age=31536000' # Cache for 1 year
        }
        
        send_data response.body, type: content_type, disposition: 'inline', headers: headers
      else
        render json: { error: 'Image not found' }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Image proxy error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: 'Failed to fetch image' }, status: :internal_server_error
    end
  end
end
