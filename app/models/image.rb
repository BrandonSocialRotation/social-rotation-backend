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
    if environments.any? { |env| file_path.start_with?("#{env}/") }
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
        # For test environment, don't include bucket in path (matches test expectations)
        "#{endpoint}/#{file_path}"
      end
    elsif file_path.start_with?('http://', 'https://')
      file_path
    elsif file_path.start_with?('placeholder/')
      # Placeholder image for production without DigitalOcean
      "https://via.placeholder.com/400x300/cccccc/666666?text=Image+Upload+Disabled"
    else
      # Local file URL
      # For development, serve from public folder
      if Rails.env.development? || Rails.env.test?
        "/#{file_path}"
      else
        # For production without DigitalOcean, use a placeholder
        "https://via.placeholder.com/400x300/cccccc/666666?text=Image+Upload+Disabled"
      end
    end
  end
end
