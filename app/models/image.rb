class Image < ApplicationRecord
  # Associations
  has_many :bucket_images, dependent: :destroy
  has_many :buckets, through: :bucket_images
  has_many :market_items, foreign_key: 'front_image_id', dependent: :destroy
  
  # Validations
  validates :file_path, presence: true
  
  # Methods from original PHP
  def get_source_url
    environments = %w[production development test]
    
    # If already a full URL, return as-is
    return file_path if file_path.start_with?('http://', 'https://')
    
    # Handle placeholder paths
    if file_path.start_with?('placeholder/')
      return "https://via.placeholder.com/400x300/cccccc/666666?text=Image+Upload+Disabled"
    end
    
    # Check if path starts with uploads/ (local storage format)
    if file_path.start_with?('uploads/')
      # Check if it's for DigitalOcean Spaces (has environment prefix like uploads/production/)
      if environments.any? { |env| file_path.start_with?("uploads/#{env}/") }
        # Prefer explicit host overrides first
        storage_host = ENV['ACTIVE_STORAGE_URL'].presence ||
                       ENV['DO_SPACES_CDN_HOST'].presence ||
                       ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'].presence ||
                       ENV['DO_SPACES_ENDPOINT'].presence

        if storage_host.present?
          storage_host = storage_host.chomp('/')
          "#{storage_host}/#{file_path}"
        else
          endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://se1.sfo2.digitaloceanspaces.com'
          endpoint = endpoint.chomp('/')
          "#{endpoint}/#{file_path}"
        end
      else
        # Local file in uploads/ folder - serve from backend
        if Rails.env.production?
          # In production, use the backend URL
          backend_url = ENV['BACKEND_URL'] || ENV['API_BASE_URL'] || 'https://new-social-rotation-backend-qzyk8.ondigitalocean.app'
          backend_url = backend_url.chomp('/')
          "#{backend_url}/#{file_path}"
        else
          # Development/Test: serve from public folder
          "/#{file_path}"
        end
      end
    # Legacy format: paths starting with environment name directly (production/, development/, test/)
    elsif environments.any? { |env| file_path.start_with?("#{env}/") }
      # Prefer explicit host overrides first
      storage_host = ENV['ACTIVE_STORAGE_URL'].presence ||
                     ENV['DO_SPACES_CDN_HOST'].presence ||
                     ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'].presence ||
                     ENV['DO_SPACES_ENDPOINT'].presence

      if storage_host.present?
        storage_host = storage_host.chomp('/')
        "#{storage_host}/#{file_path}"
      else
        endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://se1.sfo2.digitaloceanspaces.com'
        endpoint = endpoint.chomp('/')
        "#{endpoint}/#{file_path}"
      end
    else
      # Fallback: treat as local file
      if Rails.env.production?
        # In production, try to serve from backend
        backend_url = ENV['BACKEND_URL'] || ENV['API_BASE_URL'] || 'https://new-social-rotation-backend-qzyk8.ondigitalocean.app'
        backend_url = backend_url.chomp('/')
        "#{backend_url}/#{file_path}"
      else
        # Development/Test: serve from public folder
        "/#{file_path}"
      end
    end
  end
end
