class CreateScheduleItems < ActiveRecord::Migration[7.1]
  def change
    create_table :schedule_items do |t|
      t.references :bucket_schedule, null: false, foreign_key: true
      t.references :bucket_image, null: false, foreign_key: true
      t.string :schedule, null: false  # Cron expression for this specific item
      t.text :description
      t.text :twitter_description
      t.integer :position, default: 0  # Order within the schedule

      t.timestamps
    end
    
    add_index :schedule_items, [:bucket_schedule_id, :position]
  end
end
