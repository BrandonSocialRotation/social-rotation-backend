class BucketSchedule < ApplicationRecord
  # Constants from original PHP
  SCHEDULE_TYPE_ROTATION = 1
  SCHEDULE_TYPE_ONCE = 2
  SCHEDULE_TYPE_ANNUALLY = 3
  
  # Social media platform bit flags
  BIT_FACEBOOK = 1
  BIT_TWITTER = 2
  BIT_INSTAGRAM = 4
  BIT_LINKEDIN = 8
  BIT_GMB = 16
  BIT_PINTEREST = 32
  
  # Default values
  DEFAULT_TIME = '12:00'
  TWITTER_CHARACTER_LIMIT = 280
  
  # Associations
  belongs_to :bucket
  belongs_to :bucket_image, optional: true
  has_many :bucket_send_histories, dependent: :destroy
  
  # Validations
  validates :schedule, presence: true
  validates :schedule_type, presence: true, inclusion: { in: [SCHEDULE_TYPE_ROTATION, SCHEDULE_TYPE_ONCE, SCHEDULE_TYPE_ANNUALLY] }
  validate :valid_cron_format
  
  # Methods from original PHP
  def get_next_schedule(offset = 0)
    return 'Already sent' if times_sent > 0 && schedule_type == SCHEDULE_TYPE_ONCE
    
    begin
      if schedule && valid_cron_format?
        # For now, return a placeholder since we don't have cron parsing
        # This would be implemented with a proper cron gem later
        return 'Next run calculated'
      end
    rescue => e
      Rails.logger.error "Error calculating next schedule for schedule '#{schedule}': #{e.message}"
      return 'Invalid Schedule'
    end
    
    'Invalid Schedule'
  end
  
  def get_type_image
    case schedule_type
    when SCHEDULE_TYPE_ROTATION
      'rotation.png'
    when SCHEDULE_TYPE_ONCE
      'post_once.png'
    when SCHEDULE_TYPE_ANNUALLY
      'annual.png'
    end
  end
  
  def get_posts_to_images
    {
      'Facebook' => (post_to & BIT_FACEBOOK) > 0 ? 'facebook_on.png' : 'facebook_off.png',
      'Twitter' => (post_to & BIT_TWITTER) > 0 ? 'twitter_on.png' : 'twitter_off.png',
      'LinkedIn' => (post_to & BIT_LINKEDIN) > 0 ? 'linkedin_on.png' : 'linkedin_off.png',
      'Instagram' => (post_to & BIT_INSTAGRAM) > 0 ? 'instagram_on.png' : 'instagram_off.png',
      'GMB' => (post_to & BIT_GMB) > 0 ? 'gmb_on.png' : 'gmb_off.png'
    }
  end
  
  def can_send?
    bucket_send_history = bucket_send_histories.order(sent_at: :desc).first
    
    if schedule_type == SCHEDULE_TYPE_ANNUALLY
      return true unless bucket_send_history
      return bucket_send_history.sent_at < 1.year.ago
    end
    
    true
  end
  
  def get_next_bucket_image_due(offset = 0, skip_offset = 0)
    if schedule_type == SCHEDULE_TYPE_ONCE || schedule_type == SCHEDULE_TYPE_ANNUALLY
      return bucket_image if bucket_image
      # If schedule_type is ONCE/ANNUALLY but no bucket_image_id, fall through to rotation logic
    end
    
    # For rotation schedules, get next image from bucket
    result = bucket.get_next_rotation_image(offset, skip_offset)
    
    # If rotation returns nil but bucket has images, return first image as fallback
    if result.nil? && bucket.bucket_images.any?
      Rails.logger.warn "get_next_rotation_image returned nil for bucket #{bucket.id}, falling back to first image"
      return bucket.bucket_images.order(:friendly_name).first
    end
    
    result
  end
  
  def should_display_twitter_warning?
    if schedule_type == SCHEDULE_TYPE_ONCE || schedule_type == SCHEDULE_TYPE_ANNUALLY
      if bucket_image
        return true if description&.length > TWITTER_CHARACTER_LIMIT && 
                     twitter_description.blank? && 
                     bucket_image.twitter_description.blank? && 
                     (post_to & BIT_TWITTER) > 0
      end
    end
    
    if schedule_type == SCHEDULE_TYPE_ROTATION && (post_to & BIT_TWITTER) > 0
      bucket.bucket_images.each do |bucket_image|
        return true if bucket_image.description&.length > TWITTER_CHARACTER_LIMIT && bucket_image.twitter_description.blank?
      end
    end
    
    false
  end
  
  def get_next_description_due(offset = 0, skip_offset = 0, twitter_text = false)
    if schedule_type == SCHEDULE_TYPE_ONCE || schedule_type == SCHEDULE_TYPE_ANNUALLY
      if bucket_image
        if twitter_text
          return twitter_description.present? ? twitter_description : bucket_image.twitter_description
        else
          return description.present? ? description : bucket_image.description
        end
      else
        return ''
      end
    end
    
    bucket_image = get_next_bucket_image_due(offset, skip_offset)
    
    if twitter_text
      bucket_image&.twitter_description || ''
    else
      bucket_image&.description || ''
    end
  end
  
  def self.get_network_hash
    {
      BIT_FACEBOOK => 'facebook_on.png',
      BIT_TWITTER => 'twitter_on.png',
      BIT_LINKEDIN => 'linkedin_on.png',
      BIT_INSTAGRAM => 'instagram_on.png',
      BIT_GMB => 'gmb_on.png'
    }
  end
  
  def is_network_selected?(network_id)
    (post_to & network_id) > 0
  end
  
  def get_days_selected
    return [] unless schedule
    
    parts = schedule.split(' ')
    return [] if parts.length < 5
    
    parts[4].split(',') # 5th column is days of week
  end
  
  def is_day_selected?(day)
    days = get_days_selected
    days.include?(day.to_s) || days.include?('*')
  end
  
  def get_time_format
    return DEFAULT_TIME unless schedule
    
    parts = schedule.split(' ')
    return DEFAULT_TIME if parts.length < 2 || parts[0] == '*' || parts[1] == '*'
    
    "#{parts[1]}:#{parts[0]}" # Hour:Minute
  end
  
  def get_scheduled_date_format
    return Date.current.strftime('%Y-%m-%d') unless schedule
    
    parts = schedule.split(' ')
    return Date.current.strftime('%Y-%m-%d') if parts.length < 4 || parts[3] == '*' || parts[2] == '*'
    
    "#{Date.current.year}-#{parts[3]}-#{parts[2]}" # Year-Month-Day
  end
  
  def self.get_days_of_week_array
    {
      1 => 'Monday',
      2 => 'Tuesday',
      3 => 'Wednesday',
      4 => 'Thursday',
      5 => 'Friday',
      6 => 'Saturday',
      7 => 'Sunday'
    }
  end

  private

  def valid_cron_format
    return unless schedule.present?
    
    # Simple cron format validation - 5 space-separated parts
    parts = schedule.split(' ')
    if parts.length != 5
      errors.add(:schedule, "must have exactly 5 space-separated parts (minute hour day month weekday)")
    end
  end

  def valid_cron_format?
    return false unless schedule.present?
    
    parts = schedule.split(' ')
    parts.length == 5
  end
end
