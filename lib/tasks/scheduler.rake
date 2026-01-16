# Scheduler Rake Tasks
# Run with: rails scheduler:process or set up as a cron job to run every minute

namespace :scheduler do
  desc "Process all due scheduled posts"
  task process: :environment do
    puts "=" * 80
    puts "SCHEDULER STARTED: #{Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')} UTC"
    puts "=" * 80
    STDOUT.flush
    
    begin
      ProcessScheduledPostsJob.perform_now
      puts "=" * 80
      puts "SCHEDULER COMPLETED: #{Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')} UTC"
      puts "=" * 80
      STDOUT.flush
    rescue => e
      puts "=" * 80
      puts "SCHEDULER ERROR: #{e.class}: #{e.message}"
      puts e.backtrace.first(10).join("\n")
      puts "=" * 80
      STDOUT.flush
      raise
    end
  end
end
