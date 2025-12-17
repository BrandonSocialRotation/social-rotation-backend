# Bucket Model
# Represents a content collection (group of images/videos)
# Can be scheduled for automatic posting to social media
# Can be sold in marketplace as a package
class Bucket < ApplicationRecord
  # ASSOCIATIONS
  # Bucket belongs to one user (owner)
  belongs_to :user
  # Bucket has many bucket_images (images in this collection) - destroy when bucket deleted
  has_many :bucket_images, dependent: :destroy
  # Bucket can access images through bucket_images join table
  has_many :images, through: :bucket_images
  # Bucket has many bucket_videos (videos in this collection) - destroy when bucket deleted
  has_many :bucket_videos, dependent: :destroy
  # Bucket can access videos through bucket_videos join table
  has_many :videos, through: :bucket_videos
  # Bucket has many schedules (when to post images/videos) - destroy when bucket deleted
  has_many :bucket_schedules, dependent: :destroy
  # Bucket tracks send history (posts already made) - destroy when bucket deleted
  has_many :bucket_send_histories, dependent: :destroy
  # Bucket can be listed in marketplace (optional) - destroy when bucket deleted
  has_one :market_item, dependent: :destroy
  
  # VALIDATIONS
  # Bucket must have a name
  validates :name, presence: true
  
  # SCOPES
  # Find marketplace buckets (account_id = 0 means it's for sale)
  scope :is_market, -> { where(account_id: 0) }
  
  # Check if this bucket is listed in marketplace
  # Returns: true if bucket is for sale, false otherwise
  # Logic: user's account_id of 0 means marketplace bucket
  def is_market_bucket?
    user.account_id == 0
  end
  
  # Check if any schedules in this bucket are due to run
  # Params: current_time - Time to check against
  # Returns: bucket_schedule object if due, nil if not due or no schedules
  # Logic:
  #   1. Return nil if no schedules exist
  #   2. Return false if user has no timezone set
  #   3. Convert current time to user's timezone
  #   4. Loop through each schedule and check if cron expression is due
  #   5. Skip invalid schedules (0 0 0 0 0) and log errors
  #   6. Return first schedule that is due
  def is_due(current_time)
    return nil if bucket_schedules.empty?
    
    # Use the already loaded user to avoid N+1 queries
    return false unless user&.timezone
    
    current_date = Time.current.in_time_zone(user.timezone)
    
    bucket_schedules.each do |bucket_schedule|
      next if bucket_schedule.schedule == '0 0 0 0 0'
      
      # Check if cron expression is due
      # For now, just check if it's a valid format
      # This would be implemented with proper cron parsing later
      begin
        if bucket_schedule.valid_cron_format?
          # Placeholder logic - would check actual cron due time
          return bucket_schedule
        end
      rescue => e
        Rails.logger.error "Invalid cron expression '#{bucket_schedule.schedule}': #{e.message}"
        next
      end
    end
    
    nil
  end
  
  # Get next image in rotation for this bucket
  # Params: 
  #   offset - Number of images to skip forward (default 0)
  #   skip_offset - Additional offset to apply (default 0)
  # Returns: BucketImage object or nil if no images
  # Logic:
  #   1. Add skip_offset to offset
  #   2. Find all rotation-type schedules for this bucket
  #   3. Get last sent image from send history
  #   4. If last sent exists:
  #      - Find that image in current images list
  #      - Calculate next index in rotation (wraps around to start)
  #      - Apply offset to get correct image
  #   5. If no history:
  #      - Start from first image
  #      - Apply offset (wraps around if needed)
  #   6. Return selected image
  def get_next_rotation_image(offset = 0, skip_offset = 0)
    offset += skip_offset if skip_offset > 0
    
    # Get all rotation schedules
    rotation_schedules = bucket_schedules.where(schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
    return nil if rotation_schedules.empty?
    
    temp_offset = offset
    
    # Get latest sent record
    last_sent = BucketSendHistory.where(bucket_schedule_id: rotation_schedules.pluck(:id))
                                 .order(sent_at: :desc)
                                 .first
    
    all_bucket_images = bucket_images.order(:friendly_name)
    return nil if all_bucket_images.empty?
    
    if last_sent
      last_sent_image = bucket_images.find_by(id: last_sent.bucket_image_id)
      
      unless last_sent_image
        # Find next image by friendly name
        last_sent_image = bucket_images.where('friendly_name > ?', last_sent.friendly_name)
                                      .order(:friendly_name)
                                      .first
        last_sent_image ||= bucket_images.first
      end
      
      # Find next image in sequence (skip the last sent one)
      current_index = all_bucket_images.index(last_sent_image)
      next_index = (current_index + 1) % all_bucket_images.count
      
      # Apply offset (offset of 0 means next image, offset of 1 means skip one more, etc.)
      temp_offset.times do
        next_index = (next_index + 1) % all_bucket_images.count
      end
      
      return all_bucket_images[next_index]
    else
      # No previous sends, start from first image with offset
      if temp_offset > 0
        offset_index = temp_offset % all_bucket_images.count
        return all_bucket_images[offset_index]
      end
      return all_bucket_images.first
    end
  end
end
