# Process Scheduled Posts Job
# Checks all bucket schedules and posts content that is due
# Should be run periodically (e.g., every minute via cron or scheduler)
class ProcessScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    # Use STDOUT to ensure logs are visible in cron job output
    # Always use UTC - Rails default timezone
    utc_now = Time.current.utc
    system_time = Time.now  # System time (may be wrong if server clock is off)
    
    puts "=== Processing scheduled posts at #{utc_now.strftime('%Y-%m-%d %H:%M:%S')} UTC ==="
    puts "=== Server system time: #{system_time.strftime('%Y-%m-%d %H:%M:%S')} | Rails timezone: #{Time.zone.name} ==="
    Rails.logger.info "=== Processing scheduled posts at #{utc_now.strftime('%Y-%m-%d %H:%M:%S')} UTC ==="
    Rails.logger.info "=== Server system time: #{system_time.strftime('%Y-%m-%d %H:%M:%S')} | Rails timezone: #{Time.zone.name} ==="
    
    # Get all active schedules
    schedules = BucketSchedule.includes(:bucket, :bucket_image, :bucket_send_histories, schedule_items: :bucket_image)
    total_count = schedules.count
    puts "Found #{total_count} total schedules to check"
    Rails.logger.info "Found #{total_count} total schedules to check"
    
    if total_count == 0
      puts "No schedules found, exiting"
      Rails.logger.info "No schedules found, exiting"
      return
    end
    
    schedules.find_each do |schedule|
      # Process schedule items if they exist (new multi-image feature)
      if schedule.schedule_items.any?
        puts "Processing schedule #{schedule.id} with #{schedule.schedule_items.count} schedule_items"
        Rails.logger.info "Processing schedule #{schedule.id} with #{schedule.schedule_items.count} schedule_items"
        schedule.schedule_items.ordered.find_each do |item|
          if schedule_item_should_run?(item, schedule)
            begin
              puts "Processing schedule item #{item.id} for schedule #{schedule.id}"
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
    
    puts "Finished processing scheduled posts"
    Rails.logger.info "Finished processing scheduled posts"
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
    
    # Log at INFO level so it's visible in production logs
    timezone_info = user_timezone.present? ? "user timezone: #{user_timezone}" : "UTC (no user timezone)"
    Rails.logger.info "Checking cron: #{cron_string} | #{timezone_info} | Server UTC: #{utc_now.strftime('%Y-%m-%d %H:%M:%S')} | User Local: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')} | (min: #{current_minute}, hour: #{current_hour}, day: #{current_day}, month: #{current_month})"
    puts "Checking cron: #{cron_string} | #{timezone_info} | Server UTC: #{utc_now.strftime('%Y-%m-%d %H:%M:%S')} | User Local: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')} | (min: #{current_minute}, hour: #{current_hour}, day: #{current_day}, month: #{current_month})"
    
    # Check minute - allow match if scheduled minute is current or within last 5 minutes
    # This handles cases where scheduler runs slightly late or you test manually
    # The duplicate check (via send history) prevents posting the same item twice
    minute_val = minute == '*' ? '*' : minute.to_i
    hour_val = hour == '*' ? '*' : hour.to_i
    
    if minute_val != '*' && hour_val != '*'
      # Calculate minute difference accounting for hour rollover
      minute_diff = current_minute - minute_val
      
      # Check if we need to account for hour rollover (e.g., scheduled 13:57, current 14:02)
      # If current minute is small (< 5) and scheduled minute is large (> 55), might be previous hour
      if minute_diff < -50
        # Hour rollover backward (e.g., scheduled 13:57, current 14:02 -> 57 - 2 + 60 = 115 minutes, but means 5 min past)
        hour_diff = current_hour - hour_val
        if hour_diff == 1
          minute_diff = minute_diff + 60  # Adjust for previous hour
        end
      elsif minute_diff < 0
        # Scheduled time is in the future within same hour (reject)
        Rails.logger.debug "Cron minute in future: scheduled #{hour_val}:#{minute_val}, current #{current_hour}:#{current_minute} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
        return false
      elsif minute_diff > 5
        # Check if it's from previous hour (within 5 minute window)
        hour_diff = current_hour - hour_val
        if hour_diff == 1 && minute_diff > 55
          # It's from previous hour, recalculate: (60 - scheduled_minute) + current_minute
          minute_diff = (60 - minute_val) + current_minute
          if minute_diff > 5
            Rails.logger.debug "Cron too far in past (crossed hour): #{hour_val}:#{minute_val} is #{minute_diff} minutes ago (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
            return false
          end
        else
          # Too far in past, reject
          Rails.logger.debug "Cron minute too far in past: #{hour_val}:#{minute_val} is #{minute_diff} minutes ago (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
          return false
        end
      end
      
      # Now check hour (allow current hour or previous hour if within 5 minute window)
      unless hour_val == '*' || hour_val == current_hour || (hour_val == current_hour - 1 && minute_diff > 55)
        Rails.logger.debug "Cron hour mismatch: #{hour_val} != #{current_hour} and not previous hour within window (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
        return false
      end
      
      # minute_val matches or is within last 5 minutes (0 <= minute_diff <= 5)
      Rails.logger.info "Cron minute match: #{hour_val}:#{minute_val} is within 5 minutes of #{current_hour}:#{current_minute} (diff: #{minute_diff}, cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
    elsif hour_val != '*'
      # Hour specified but minute is wildcard - just check hour
      unless hour_val == current_hour
        Rails.logger.debug "Cron hour mismatch: #{hour_val} != #{current_hour} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
        return false
      end
    end
    
    # Check day of month (exact match or wildcard)
    # For rotation schedules, day is usually '*'
    day_val = day == '*' ? '*' : day.to_i
    unless day_val == '*' || day_val == current_day
      Rails.logger.info "Cron day mismatch: scheduled day #{day_val} != current day #{current_day} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      puts "Cron day mismatch: scheduled day #{day_val} != current day #{current_day} (cron: #{cron_string}, now: #{now.strftime('%Y-%m-%d %H:%M:%S')})"
      return false
    end
    
    # If we get here, minute/hour/day/month all match - log it
    if minute_val != '*' && hour_val != '*'
      Rails.logger.info "✓ Cron time match: #{hour_val}:#{minute_val} matches #{current_hour}:#{current_minute}"
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
    
    puts "✓ Cron match: #{cron_string} matches current time #{now.strftime('%Y-%m-%d %H:%M:%S')}"
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
    
    user = schedule.bucket.user
    
    # Use schedule_item's timezone if set, otherwise use schedule's timezone, then fall back to user's profile timezone
    item_timezone = item.timezone.presence || schedule.timezone.presence || user.timezone
    
    unless item_timezone.present?
      Rails.logger.warn "No timezone set for schedule item #{item.id} - using UTC"
    end
    
    current_time = item_timezone ? Time.current.in_time_zone(item_timezone) : Time.current
    puts "Checking schedule item #{item.id} (cron: #{item.schedule}, timezone: #{item_timezone || 'UTC'}, current time: #{current_time.strftime('%Y-%m-%d %H:%M:%S %Z')})"
    Rails.logger.info "Checking schedule item #{item.id} (cron: #{item.schedule}, timezone: #{item_timezone || 'UTC'}, current time: #{current_time.strftime('%Y-%m-%d %H:%M:%S %Z')})"
    
    # Check if schedule item is due based on cron expression, using item's timezone (or schedule/user's as fallback)
    unless cron_due?(item.schedule, item_timezone)
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
    
    puts "✓ Schedule item #{item.id} is due and ready to post (cron: #{item.schedule})"
    Rails.logger.info "✓ Schedule item #{item.id} is due and ready to post (cron: #{item.schedule})"
    true
  end
  
  def process_schedule_item(item, schedule)
    user = schedule.bucket.user
    
    # Check if user has active subscription
    unless user.account&.has_active_subscription?
      Rails.logger.warn "Cannot post schedule item #{item.id}: user #{user.id} (#{user.email}) does not have active subscription"
      puts "Cannot post schedule item #{item.id}: user #{user.id} (#{user.email}) does not have active subscription"
      return
    end
    
    bucket_image = item.bucket_image
    unless bucket_image
      Rails.logger.warn "Cannot post schedule item #{item.id}: bucket_image is missing"
      puts "Cannot post schedule item #{item.id}: bucket_image is missing"
      return
    end
    
    Rails.logger.info "Starting to post schedule item #{item.id} (bucket_image_id: #{bucket_image.id})"
    puts "Starting to post schedule item #{item.id} (bucket_image_id: #{bucket_image.id})"
    
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
    
    puts "Successfully posted schedule item #{item.id} (schedule #{schedule.id}) to social media"
    Rails.logger.info "Successfully posted schedule item #{item.id} (schedule #{schedule.id}) to social media"
  rescue => e
    Rails.logger.error "Failed to post schedule item #{item.id}: #{e.message}"
    raise
  end
end
