class BucketSendHistory < ApplicationRecord
  # Constants from original PHP
  SENT_TO_FACEBOOK = 1
  
  # Associations
  belongs_to :bucket
  belongs_to :bucket_schedule
  belongs_to :bucket_image
  
  # Methods from original PHP
  def get_sent_to_name
    return 'Unknown' if sent_to.nil? || sent_to == 0
    
    sent_to_platforms = []
    
    sent_to_platforms << 'Facebook' if (sent_to & BucketSchedule::BIT_FACEBOOK) > 0
    sent_to_platforms << 'Twitter' if (sent_to & BucketSchedule::BIT_TWITTER) > 0
    sent_to_platforms << 'LinkedIn' if (sent_to & BucketSchedule::BIT_LINKEDIN) > 0
    sent_to_platforms << 'Google My Business' if (sent_to & BucketSchedule::BIT_GMB) > 0
    sent_to_platforms << 'Instagram' if (sent_to & BucketSchedule::BIT_INSTAGRAM) > 0
    
    sent_to_platforms.empty? ? 'Unknown' : sent_to_platforms.join(', ')
  end
end
