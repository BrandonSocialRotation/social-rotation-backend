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
    # BucketVideo doesn't have force_send_date column - always return false
    false
  end
  
  def should_display_twitter_warning?
    description&.length > BucketSchedule::TWITTER_CHARACTER_LIMIT && twitter_description.blank?
  end
end
