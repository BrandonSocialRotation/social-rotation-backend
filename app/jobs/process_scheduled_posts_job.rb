# Process Scheduled Posts Job
# Checks all bucket schedules and posts content that is due
# Should be run periodically (e.g., every minute via cron or scheduler)
class ProcessScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "=== Processing scheduled posts at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')} ==="
    
    # Get all active schedules
    schedules = BucketSchedule.includes(:bucket, :bucket_image, :bucket_send_histories, schedule_items: :bucket_image)
    total_count = schedules.count
    Rails.logger.info "Found #{total_count} total schedules to check"
    
    if total_count == 0
      Rails.logger.info "No schedules found, exiting"
      return
    end
    
    schedules.find_each do |schedule|
      # Process schedule items if they exist (new multi-image feature)
      if schedule.schedule_items.any?
        Rails.logger.debug "Processing schedule #{schedule.id} with #{schedule.schedule_items.count} schedule_items"
        schedule.schedule_items.ordered.find_each do |item|
          if schedule_item_should_run?(item, schedule)
            begin
              Rails.logger.info "Processing schedule item #{item.id} for schedule #{schedule.id}"
              process_schedule_item(item, schedule)
            rescue => e
              Rails.logger.error "Error processing schedule item #{item.id}: #{e.message}"
              Rails.logger.error e.backtrace.join("\n")
            end
          end
        end
      else
        # Legacy: process schedule directly (single image or rotation)
        if schedule_should_run?(schedule)
          begin
            Rails.logger.info "Processing legacy schedule #{schedule.id}"
            process_schedule(schedule)
          rescue => e
            Rails.logger.error "Error processing schedule #{schedule.id}: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          end
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
    unless parts.length == 5
      Rails.logger.warn "Invalid cron format: #{cron_string} (expected 5 parts, got #{parts.length})"
      return false
    end
    
    minute, hour, day, month, weekday = parts
    
    now = Time.current
    
    # Check minute (exact match or wildcard)
    # Handle leading zeros by converting to integer
    minute_val = minute == '*' ? '*' : minute.to_i
    unless minute_val == '*' || minute_val == now.min
      Rails.logger.debug "Cron minute mismatch: #{minute_val} != #{now.min} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      return false
    end
    
    # Check hour (exact match or wildcard)
    hour_val = hour == '*' ? '*' : hour.to_i
    unless hour_val == '*' || hour_val == now.hour
      Rails.logger.debug "Cron hour mismatch: #{hour_val} != #{now.hour} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      return false
    end
    
    # Check day of month (exact match or wildcard)
    # For rotation schedules, day is usually '*'
    day_val = day == '*' ? '*' : day.to_i
    unless day_val == '*' || day_val == now.day
      Rails.logger.debug "Cron day mismatch: #{day_val} != #{now.day} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      return false
    end
    
    # Check month (exact match or wildcard)
    # For rotation schedules, month is usually '*'
    month_val = month == '*' ? '*' : month.to_i
    unless month_val == '*' || month_val == now.month
      Rails.logger.debug "Cron month mismatch: #{month_val} != #{now.month} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      return false
    end
    
    # Check weekday
    # Cron format: 0-6 (0=Sunday) or 1-7 (1=Monday) depending on system
    # Rails wday: 0=Sunday, 1=Monday, ..., 6=Saturday
    if weekday != '*'
      # Handle comma-separated weekdays (e.g., "1,2,3,4,5" for Mon-Fri)
      weekdays = weekday.split(',').map(&:to_i)
      current_weekday = now.wday
      # Cron typically uses 0-6 where 0=Sunday, same as Rails
      unless weekdays.include?(current_weekday)
        Rails.logger.debug "Cron weekday mismatch: #{weekdays.inspect} does not include #{current_weekday} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
        return false
      end
    end
    
    Rails.logger.info "✓ Cron match: #{cron_string} matches current time #{now.strftime('%Y-%m-%d %H:%M:%S')}"
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
    unless schedule.bucket
      Rails.logger.debug "Schedule item #{item.id}: schedule has no bucket"
      return false
    end
    
    unless schedule.bucket.user
      Rails.logger.debug "Schedule item #{item.id}: bucket has no user"
      return false
    end
    
    Rails.logger.debug "Checking schedule item #{item.id} (cron: #{item.schedule}, current time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')})"
    
    # Check if schedule item is due based on cron expression
    unless cron_due?(item.schedule)
      Rails.logger.debug "Schedule item #{item.id} is not due yet (cron: #{item.schedule})"
      return false
    end
    
    # Check if this item has already been sent
    # For MULTIPLE schedules, each item should post once at its scheduled time
    # We track this via send history with schedule_item_id
    last_sent = schedule.bucket_send_histories
                       .where(bucket_image_id: item.bucket_image_id)
                       .where(schedule_item_id: item.id)
                       .exists?
    
    if last_sent
      Rails.logger.info "Schedule item #{item.id} has already been sent, skipping"
      return false
    end
    
    Rails.logger.info "✓ Schedule item #{item.id} is due and ready to post (cron: #{item.schedule})"
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
