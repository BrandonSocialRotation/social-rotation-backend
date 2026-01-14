# ScheduleItem Model
# Represents a single image scheduled within a BucketSchedule
# Allows multiple images with different times/descriptions in one schedule
class ScheduleItem < ApplicationRecord
  belongs_to :bucket_schedule
  belongs_to :bucket_image
  
  validates :schedule, presence: true
  validates :position, presence: true
  
  # Validate cron format
  validate :valid_cron_format
  
  scope :ordered, -> { order(:position) }
  
  def valid_cron_format?
    return false unless schedule.present?
    
    parts = schedule.split(' ')
    parts.length == 5
  end
  
  private
  
  def valid_cron_format
    return unless schedule.present?
    
    parts = schedule.split(' ')
    if parts.length != 5
      errors.add(:schedule, "must have exactly 5 space-separated parts (minute hour day month weekday)")
    end
  end
end
