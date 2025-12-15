class BucketVideo < ApplicationRecord
  # Associations
  belongs_to :bucket
  belongs_to :video
  has_many :bucket_schedules, dependent: :destroy
  has_many :bucket_send_histories, dependent: :destroy
  
  # Validations
  validates :friendly_name, presence: true
  
  # Methods similar to BucketImage
  def forced_is_due?
    return false unless force_send_date
    
    user = bucket.user
    return false unless user&.timezone
    
    current_date = Time.current.in_time_zone(user.timezone)
    run_date = force_send_date.in_time_zone(user.timezone)
    
    current_date.strftime('%Y-%m-%d %H:%M') == run_date.strftime('%Y-%m-%d %H:%M')
  end
  
  def should_display_twitter_warning?
    description&.length > BucketSchedule::TWITTER_CHARACTER_LIMIT && twitter_description.blank?
  end
end


