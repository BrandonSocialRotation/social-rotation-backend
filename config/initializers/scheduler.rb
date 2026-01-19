# Start scheduler thread that runs every minute
# This runs when Rails boots, regardless of Puma mode
Rails.application.config.after_initialize do
  Thread.new do
    # Wait a bit before starting to ensure Rails is fully loaded
    sleep 10
    
    Rails.logger.info "Starting scheduler thread..."
    
    loop do
      begin
        sleep 60  # Wait 60 seconds between runs
        Rails.logger.info "[Scheduler] Running scheduled posts check..."
        ProcessScheduledPostsJob.perform_now
      rescue => e
        Rails.logger.error "Scheduler thread error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end
  end
end

