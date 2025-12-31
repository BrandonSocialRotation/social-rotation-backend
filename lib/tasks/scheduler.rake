# Scheduler Rake Tasks
# Run with: rails scheduler:process or set up as a cron job to run every minute

namespace :scheduler do
  desc "Process all due scheduled posts"
  task process: :environment do
    puts "Processing scheduled posts..."
    ProcessScheduledPostsJob.perform_now
    puts "Scheduled posts processing completed."
  end
end
