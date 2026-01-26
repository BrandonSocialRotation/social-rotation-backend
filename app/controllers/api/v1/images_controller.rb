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
    
    # Construct the full URL to DigitalOcean Spaces
    endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://se1.sfo2.digitaloceanspaces.com'
    endpoint = endpoint.chomp('/')
    
    # Handle different path formats
    if path.start_with?('uploads/')
      # Remove uploads/ prefix if present
      path = path.sub(/^uploads\//, '')
    end
    
    image_url = "#{endpoint}/#{path}"
    
    begin
      # Fetch the image from DigitalOcean Spaces
      require 'net/http'
      require 'uri'
      
      uri = URI(image_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(uri.path)
      response = http.request(request)
      
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
