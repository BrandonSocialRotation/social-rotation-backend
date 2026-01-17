class AddTimezoneToBucketSchedulesAndScheduleItems < ActiveRecord::Migration[7.1]
  def change
    add_column :bucket_schedules, :timezone, :string
    add_column :schedule_items, :timezone, :string
  end
end
