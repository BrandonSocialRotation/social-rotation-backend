# Process Scheduled Posts Job
# Checks all bucket schedules and posts content that is due
# Should be run periodically (e.g., every minute via cron or scheduler)
class ProcessScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    # Always use UTC - Rails default timezone
    utc_now = Time.current.utc
    Rails.logger.debug "Processing scheduled posts at #{utc_now.strftime('%Y-%m-%d %H:%M:%S')} UTC"
    
    # Get all active schedules
    schedules = BucketSchedule.includes(:bucket, :bucket_image, :bucket_send_histories, schedule_items: :bucket_image)
    total_count = schedules.count
    
    if total_count == 0
      Rails.logger.debug "No schedules found"
      return
    end
    
    schedules.find_each do |schedule|
      # Process schedule items if they exist (new multi-image feature)
      if schedule.schedule_items.any?
        schedule.schedule_items.ordered.find_each do |item|
          if schedule_item_should_run?(item, schedule)
            begin
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
            process_schedule(schedule)
          rescue => e
            Rails.logger.error "Error processing schedule #{schedule.id}: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          end
        end
      end
    end
  end

  def schedule_should_run?(schedule)
    return false unless schedule.bucket
    return false unless schedule.bucket.user
    
    user = schedule.bucket.user
    
    # Use schedule's timezone if set, otherwise fall back to user's profile timezone
    schedule_timezone = schedule.timezone.presence || user.timezone
    
    unless schedule_timezone.present?
      Rails.logger.warn "No timezone set for schedule #{schedule.id} or user #{user.id} (#{user.email}) - using UTC"
    end
    
    # Check if schedule is due based on cron expression, using schedule's timezone (or user's as fallback)
    return false unless cron_due?(schedule.schedule, schedule_timezone)
    
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
    
    # For BUCKET_ROTATION schedules, check if we already posted today
    if schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_BUCKET_ROTATION
      today_start = Time.current.beginning_of_day
      today_end = Time.current.end_of_day
      posted_today = schedule.bucket_send_histories.where(sent_at: today_start..today_end).exists?
      # Allow posting if we haven't posted today, or if all images have been posted today (cycle complete, start fresh)
      if posted_today
        # Check if all images in bucket have been posted today
        all_images_count = schedule.bucket.bucket_images.count
        posted_today_count = schedule.bucket_send_histories
                                .where(sent_at: today_start..today_end)
                                .distinct
                                .count(:bucket_image_id)
        # Only allow if we've posted all images today (cycle complete, can start fresh)
        return false if posted_today_count < all_images_count
      end
    end
    
    true
  end

  def cron_due?(cron_string, user_timezone = nil)
    return false unless cron_string.present?
    
    parts = cron_string.split(' ')
    unless parts.length == 5
      Rails.logger.warn "Invalid cron format: #{cron_string} (expected 5 parts, got #{parts.length})"
      return false
    end
    
    minute, hour, day, month, weekday = parts
    
    # Always get current time in UTC first (Rails default)
    utc_now = Time.current.utc
    
    # Use user's timezone if provided, otherwise use UTC
    if user_timezone.present?
      now = utc_now.in_time_zone(user_timezone)
    else
      now = utc_now
    end
    current_minute = now.min
    current_hour = now.hour
    current_day = now.day
    current_month = now.month
    
    # Log detailed check info at DEBUG level (only visible when needed)
    Rails.logger.debug "Checking cron: #{cron_string} | timezone: #{user_timezone || 'UTC'} | local time: #{now.strftime('%H:%M:%S %Z')}"
    
    # Check minute - allow match if scheduled minute is current or within last 5 minutes
    # This handles cases where scheduler runs slightly late or you test manually
    # The duplicate check (via send history) prevents posting the same item twice
    minute_val = minute == '*' ? '*' : minute.to_i
    hour_val = hour == '*' ? '*' : hour.to_i
    
    # Check day of month FIRST (before hour/minute) to properly handle future times
    day_val = day == '*' ? '*' : day.to_i
    unless day_val == '*' || day_val == current_day
      Rails.logger.debug "Cron day mismatch: scheduled day #{day_val} != current day #{current_day}"
      return false
    end
    
    if minute_val != '*' && hour_val != '*'
      # Calculate minute difference accounting for hour rollover
      # Allow matches within a 5-minute window (0-5 minutes past the scheduled time)
      hour_diff = current_hour - hour_val
      minute_diff = nil
      
      # Same day (or wildcard day) - check hour/minute
      if hour_diff == 0
        # Same hour: simple difference
        minute_diff = current_minute - minute_val
        if minute_diff < 0
          # Scheduled time is in the future within same hour (reject)
          Rails.logger.debug "Cron minute in future: scheduled #{hour_val}:#{minute_val.to_s.rjust(2, '0')}, current #{current_hour}:#{current_minute.to_s.rjust(2, '0')}"
          return false
        elsif minute_diff > 5
          # Too far in past, reject
          Rails.logger.debug "Cron too far in past: scheduled #{hour_val}:#{minute_val.to_s.rjust(2, '0')}, current #{current_hour}:#{current_minute.to_s.rjust(2, '0')}"
          return false
        end
      elsif hour_diff == 1
        # Previous hour: check if within 5-minute window
        # e.g., scheduled 13:57, current 14:02 -> diff = (60 - 57) + 2 = 5 minutes
        minute_diff = (60 - minute_val) + current_minute
        if minute_diff > 5
          # Too far in past, reject
          Rails.logger.debug "Cron too far in past (crossed hour): scheduled #{hour_val}:#{minute_val.to_s.rjust(2, '0')}, current #{current_hour}:#{current_minute.to_s.rjust(2, '0')}"
          return false
        end
      elsif hour_diff < 0
        # Current hour is LESS than scheduled hour (e.g., current=0, scheduled=12)
        # This means scheduled time is in the future (later today, since day already matched)
        Rails.logger.debug "Cron scheduled time is in future: scheduled #{hour_val}:#{minute_val.to_s.rjust(2, '0')}, current #{current_hour}:#{current_minute.to_s.rjust(2, '0')}"
        return false
      else
        # hour_diff > 1: Scheduled time is more than 1 hour in the past
        Rails.logger.debug "Cron too far in past: scheduled #{hour_val}:#{minute_val.to_s.rjust(2, '0')} (#{hour_diff} hours ago), current #{current_hour}:#{current_minute.to_s.rjust(2, '0')}"
        return false
      end
      
      # minute_val matches or is within last 5 minutes (0 <= minute_diff <= 5)
      Rails.logger.debug "Cron minute match: #{hour_val}:#{minute_val.to_s.rjust(2, '0')} matches #{current_hour}:#{current_minute.to_s.rjust(2, '0')} (diff: #{minute_diff})"
    elsif hour_val != '*'
      # Hour specified but minute is wildcard - just check hour
      unless hour_val == current_hour
        Rails.logger.debug "Cron hour mismatch: #{hour_val} != #{current_hour} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
        return false
      end
    end
    
    # Day check already happened above, before hour/minute check
    # If we get here, minute/hour/day/month all match
    if minute_val != '*' && hour_val != '*'
      Rails.logger.info "✓ Schedule match: #{hour_val}:#{minute_val.to_s.rjust(2, '0')} on day #{current_day} (#{user_timezone || 'UTC'})"
    end
    
    # Check month (exact match or wildcard)
    # For rotation schedules, month is usually '*'
    month_val = month == '*' ? '*' : month.to_i
    unless month_val == '*' || month_val == current_month
      Rails.logger.debug "Cron month mismatch: #{month_val} != #{current_month} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
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
    
    true
  end

  def process_schedule(schedule)
    user = schedule.bucket.user
    
    # Check if user has active subscription (super admins bypass this check)
    return unless user.super_admin? || user.account&.has_active_subscription?
    
    # Get the image to post
    bucket_image = if schedule.bucket_image_id.present?
      schedule.bucket_image
    else
      # For rotation schedules, get next image
      schedule.get_next_bucket_image_due
    end
    
    return unless bucket_image
    
    # Get descriptions - prefer bucket_image description, then schedule description
    description = if bucket_image.description.present?
      bucket_image.description
    elsif schedule.description.present?
      schedule.description
    else
      ''
    end
    
    twitter_description = if bucket_image.twitter_description.present?
      bucket_image.twitter_description
    elsif schedule.twitter_description.present?
      schedule.twitter_description
    else
      description
    end
    
    # Log what description is being used for debugging
    Rails.logger.info "Description sources - bucket_image: '#{bucket_image.description}', schedule: '#{schedule.description}' => final: '#{description}' (length: #{description.length})"
    
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
    
    user = schedule.bucket.user
    
    # Use schedule_item's timezone if set, otherwise use schedule's timezone, then fall back to user's profile timezone
    item_timezone = item.timezone.presence || schedule.timezone.presence || user.timezone
    
    unless item_timezone.present?
      Rails.logger.warn "No timezone set for schedule item #{item.id} - using UTC"
    end
    
    # Check if schedule item is due based on cron expression, using item's timezone (or schedule/user's as fallback)
    cron_match_result = cron_due?(item.schedule, item_timezone)
    unless cron_match_result
      Rails.logger.debug "Schedule item #{item.id} is not due yet"
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
      Rails.logger.debug "Schedule item #{item.id} has already been sent, skipping"
      return false
    end
    
    true
  end
  
  def process_schedule_item(item, schedule)
    user = schedule.bucket.user
    
    # Check if user has active subscription (super admins bypass this check)
    unless user.super_admin? || user.account&.has_active_subscription?
      Rails.logger.warn "Cannot post schedule item #{item.id}: user #{user.id} does not have active subscription"
      return
    end
    
    bucket_image = item.bucket_image
    unless bucket_image
      Rails.logger.warn "Cannot post schedule item #{item.id}: bucket_image is missing"
      return
    end
    
    Rails.logger.info "Posting schedule item #{item.id} (schedule #{schedule.id}, image #{bucket_image.id})"
    
    # Get descriptions (item description overrides schedule description)
    # Use the first non-blank description found, or empty string if all are blank
    description = if item.description.present?
      item.description
    elsif schedule.description.present?
      schedule.description
    elsif bucket_image.description.present?
      bucket_image.description
    else
      ''
    end
    
    twitter_description = if item.twitter_description.presence
      item.twitter_description
    elsif schedule.twitter_description.presence
      schedule.twitter_description
    elsif bucket_image.twitter_description.presence
      bucket_image.twitter_description
    else
      description
    end
    
    # Log what description is being used for debugging
    Rails.logger.info "Description sources - item: '#{item.description}', schedule: '#{schedule.description}', bucket_image: '#{bucket_image.description}' => final: '#{description}' (length: #{description.length})"
    
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
      schedule_item_id: item.id
    )
    
    # Update schedule
    schedule.increment!(:times_sent)
    
    Rails.logger.info "✓ Successfully posted schedule item #{item.id} (schedule #{schedule.id})"
  rescue => e
    Rails.logger.error "Failed to post schedule item #{item.id}: #{e.message}"
    raise
  end
end
