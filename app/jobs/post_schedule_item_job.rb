# Post Schedule Item Job
# Posts a single schedule item at its scheduled time
# This job is scheduled to run at the exact time specified in the schedule_item
class PostScheduleItemJob < ApplicationJob
  queue_as :default

  def perform(schedule_item_id)
    schedule_item = ScheduleItem.find_by(id: schedule_item_id)
    return unless schedule_item
    
    schedule = schedule_item.bucket_schedule
    return unless schedule
    return unless schedule.bucket
    return unless schedule.bucket.user
    
    user = schedule.bucket.user
    
    # Check if user has active subscription
    unless user.account&.has_active_subscription?
      Rails.logger.warn "User #{user.id} does not have active subscription, skipping schedule item #{schedule_item_id}"
      return
    end
    
    # Check if this item has already been sent
    last_sent = schedule.bucket_send_histories
                       .where(bucket_image_id: schedule_item.bucket_image_id)
                       .where(schedule_item_id: schedule_item.id)
                       .exists?
    
    if last_sent
      Rails.logger.info "Schedule item #{schedule_item_id} has already been sent, skipping"
      return
    end
    
    bucket_image = schedule_item.bucket_image
    unless bucket_image
      Rails.logger.error "Schedule item #{schedule_item_id} has no bucket_image"
      return
    end
    
    # Get descriptions (item description overrides schedule description)
    description = schedule_item.description.presence || schedule.description.presence || bucket_image.description.presence || ''
    twitter_description = schedule_item.twitter_description.presence || schedule.twitter_description.presence || bucket_image.twitter_description.presence || description
    
    Rails.logger.info "Posting schedule item #{schedule_item_id} (schedule #{schedule.id}) at #{Time.current}"
    
    # Post to all selected platforms
    poster = SocialMediaPosterService.new(
      user,
      bucket_image,
      schedule.post_to,
      description,
      twitter_description: twitter_description,
      facebook_page_id: schedule.facebook_page_id,
      linkedin_organization_urn: schedule.linkedin_organization_urn
    )
    
    results = poster.post_to_all
    
    # Create send history with schedule_item reference
    schedule.bucket_send_histories.create!(
      bucket_id: schedule.bucket_id,
      bucket_image_id: bucket_image.id,
      friendly_name: bucket_image.friendly_name,
      text: description,
      twitter_text: twitter_description,
      sent_to: schedule.post_to,
      sent_at: Time.current,
      schedule_item_id: schedule_item.id
    )
    
    # Update schedule
    schedule.increment!(:times_sent)
    
    Rails.logger.info "Successfully posted schedule item #{schedule_item_id} (schedule #{schedule.id}) to social media"
  rescue => e
    Rails.logger.error "Failed to post schedule item #{schedule_item_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
