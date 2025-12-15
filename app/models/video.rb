class Video < ApplicationRecord
  # Constants from original PHP
  STATUS_UNPROCESSED = 0
  STATUS_PROCESSING = 1
  STATUS_PROCESSED = 2
  
  # Associations
  belongs_to :user
  has_many :bucket_videos, dependent: :destroy
  has_many :buckets, through: :bucket_videos
  
  # Validations
  validates :file_path, presence: true
  validates :status, presence: true, inclusion: { in: [STATUS_UNPROCESSED, STATUS_PROCESSING, STATUS_PROCESSED] }
  
  # Methods from original PHP
  def get_source_url
    # Check if it's already a full URL
    return file_path if file_path.start_with?('http://') || file_path.start_with?('https://')
    
    # For DigitalOcean Spaces
    if Rails.env.production?
      bucket_name = ENV['DO_SPACES_BUCKET'] || ENV['DIGITAL_OCEAN_SPACES_NAME']
      endpoint = ENV['DO_SPACES_CDN_HOST'] || ENV['ACTIVE_STORAGE_URL'] || ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT']
      
      if endpoint.present?
        # Remove protocol and path if present
        base_url = endpoint.gsub(/^https?:\/\//, '').gsub(/\/.*$/, '')
        "https://#{base_url}/#{bucket_name}/#{file_path}"
      else
        "https://se1.sfo2.digitaloceanspaces.com/#{file_path}"
      end
    else
      # Development: local file
      "http://localhost:3000/#{file_path}"
    end
  end
end
