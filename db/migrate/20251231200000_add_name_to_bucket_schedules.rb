class AddNameToBucketSchedules < ActiveRecord::Migration[7.1]
  def change
    add_column :bucket_schedules, :name, :string
  end
end
