# Temporary task to run timezone migration
# Usage: bundle exec rails migrate_timezone:run
namespace :migrate_timezone do
  desc "Run the timezone migration manually"
  task run: :environment do
    puts "Checking if timezone columns exist..."
    
    # Check if columns exist
    bucket_schedule_has_timezone = ActiveRecord::Base.connection.column_exists?(:bucket_schedules, :timezone)
    schedule_item_has_timezone = ActiveRecord::Base.connection.column_exists?(:schedule_items, :timezone)
    
    puts "BucketSchedule has timezone column: #{bucket_schedule_has_timezone}"
    puts "ScheduleItem has timezone column: #{schedule_item_has_timezone}"
    
    if bucket_schedule_has_timezone && schedule_item_has_timezone
      puts "✓ Timezone columns already exist!"
      exit 0
    end
    
    puts "Running migration..."
    ActiveRecord::Migration.run(:up, ActiveRecord::Base.connection.migration_context.migrations.find { |m| m.version == 20260117191643 })
    
    puts "✓ Migration complete!"
    
    # Verify
    bucket_schedule_has_timezone = ActiveRecord::Base.connection.column_exists?(:bucket_schedules, :timezone)
    schedule_item_has_timezone = ActiveRecord::Base.connection.column_exists?(:schedule_items, :timezone)
    puts "After migration - BucketSchedule has timezone: #{bucket_schedule_has_timezone}"
    puts "After migration - ScheduleItem has timezone: #{schedule_item_has_timezone}"
  end
end

