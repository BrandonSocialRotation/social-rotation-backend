# Process Scheduled Posts Job
# Checks all bucket schedules and posts content that is due
# Should be run periodically (e.g., every minute via cron or scheduler)
class ProcessScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Processing scheduled posts..."
    
    # Get all active schedules
    schedules = BucketSchedule.includes(:bucket, :bucket_image, :bucket_send_histories, :schedule_items)
    
    schedules.find_each do |schedule|
      # Process schedule items if they exist (new multi-image feature)
      if schedule.schedule_items.any?
        schedule.schedule_items.ordered.find_each do |item|
          next unless schedule_item_should_run?(item, schedule)
          
          begin
            process_schedule_item(item, schedule)
          rescue => e
            Rails.logger.error "Error processing schedule item #{item.id}: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          end
        end
      else
        # Legacy: process schedule directly (single image or rotation)
        next unless schedule_should_run?(schedule)
        
        begin
          process_schedule(schedule)
        rescue => e
          Rails.logger.error "Error processing schedule #{schedule.id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end
    end
    
    Rails.logger.info "Finished processing scheduled posts"
  end

  private

  def schedule_should_run?(schedule)
    return false unless schedule.bucket
    return false unless schedule.bucket.user
    
    # Check if schedule is due based on cron expression
    return false unless cron_due?(schedule.schedule)
    
    # For ONCE schedules, check if already sent
    if schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_ONCE
      return false if schedule.times_sent > 0
    end
    
    # For ANNUALLY schedules, check if already sent this year
    if schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_ANNUALLY
      this_year = Time.current.year
      last_sent = schedule.bucket_send_histories.where("EXTRACT(YEAR FROM sent_at) = ?", this_year).exists?
      return false if last_sent
    end
    
    true
  end

  def cron_due?(cron_string)
    return false unless cron_string.present?
    
    parts = cron_string.split(' ')
    return false unless parts.length == 5
    
    minute, hour, day, month, weekday = parts
    
    now = Time.current
    
    # Check minute (exact match or wildcard)
    # Handle leading zeros by converting to integer
    minute_val = minute == '*' ? '*' : minute.to_i
    return false unless minute_val == '*' || minute_val == now.min
    
    # Check hour (exact match or wildcard)
    hour_val = hour == '*' ? '*' : hour.to_i
    return false unless hour_val == '*' || hour_val == now.hour
    
    # Check day of month (exact match or wildcard)
    # For rotation schedules, day is usually '*'
    day_val = day == '*' ? '*' : day.to_i
    return false unless day_val == '*' || day_val == now.day
    
    # Check month (exact match or wildcard)
    # For rotation schedules, month is usually '*'
    month_val = month == '*' ? '*' : month.to_i
    return false unless month_val == '*' || month_val == now.month
    
    # Check weekday
    # Cron format: 0-6 (0=Sunday) or 1-7 (1=Monday) depending on system
    # Rails wday: 0=Sunday, 1=Monday, ..., 6=Saturday
    if weekday != '*'
      # Handle comma-separated weekdays (e.g., "1,2,3,4,5" for Mon-Fri)
      weekdays = weekday.split(',').map(&:to_i)
      current_weekday = now.wday
      # Cron typically uses 0-6 where 0=Sunday, same as Rails
      return false unless weekdays.include?(current_weekday)
    end
    
    Rails.logger.debug "Cron match: #{cron_string} matches current time #{now.strftime('%Y-%m-%d %H:%M:%S')}"
    true
  end

  def process_schedule(schedule)
    user = schedule.bucket.user
    
    # Check if user has active subscription
    return unless user.account&.has_active_subscription?
    
    # Get the image to post
    bucket_image = if schedule.bucket_image_id.present?
      schedule.bucket_image
    else
      # For rotation schedules, get next image
      schedule.get_next_bucket_image_due
    end
    
    return unless bucket_image
    
    # Get descriptions
    description = bucket_image.description.presence || schedule.description.presence || ''
    twitter_description = bucket_image.twitter_description.presence || schedule.twitter_description.presence || description
    
    # Post to all selected platforms
    poster = SocialMediaPosterService.new(
      user,
      bucket_image,
      schedule.post_to,
      description,
      twitter_description,
      schedule.facebook_page_id,
      schedule.linkedin_organization_urn
    )
    
    results = poster.post_to_all
    
    # Create send history
    schedule.bucket_send_histories.create!(
      bucket_id: schedule.bucket_id,
      bucket_image_id: bucket_image.id,
      friendly_name: bucket_image.friendly_name,
      text: description,
      twitter_text: twitter_description,
      sent_to: schedule.post_to,
      sent_at: Time.current
    )
    
    # Update schedule
    schedule.increment!(:times_sent)
    
    Rails.logger.info "Successfully posted schedule #{schedule.id} to social media"
  rescue => e
    Rails.logger.error "Failed to post schedule #{schedule.id}: #{e.message}"
    raise
  end
  
  def schedule_item_should_run?(item, schedule)
    return false unless schedule.bucket
    return false unless schedule.bucket.user
    
    # Check if schedule item is due based on cron expression
    return false unless cron_due?(item.schedule)
    
    # Check if this item has already been sent (for once-type schedules)
    # We'll track this via send history with schedule_item_id
    last_sent = schedule.bucket_send_histories
                       .where(bucket_image_id: item.bucket_image_id)
                       .where(schedule_item_id: item.id)
                       .exists?
    
    # For ONCE schedules, don't re-post if already sent
    return false if last_sent && schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_ONCE
    
    true
  end
  
  def process_schedule_item(item, schedule)
    user = schedule.bucket.user
    
    # Check if user has active subscription
    return unless user.account&.has_active_subscription?
    
    bucket_image = item.bucket_image
    return unless bucket_image
    
    # Get descriptions (item description overrides schedule description)
    description = item.description.presence || schedule.description.presence || bucket_image.description.presence || ''
    twitter_description = item.twitter_description.presence || schedule.twitter_description.presence || bucket_image.twitter_description.presence || description
    
    # Post to all selected platforms
    poster = SocialMediaPosterService.new(
      user,
      bucket_image,
      schedule.post_to,
      description,
      twitter_description,
      schedule.facebook_page_id,
      schedule.linkedin_organization_urn
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
      schedule_item_id: item.id
    )
    
    # Update schedule
    schedule.increment!(:times_sent)
    
    Rails.logger.info "Successfully posted schedule item #{item.id} (schedule #{schedule.id}) to social media"
  rescue => e
    Rails.logger.error "Failed to post schedule item #{item.id}: #{e.message}"
    raise
  end
end
