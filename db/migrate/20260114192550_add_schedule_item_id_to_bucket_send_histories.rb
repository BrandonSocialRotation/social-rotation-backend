class AddScheduleItemIdToBucketSendHistories < ActiveRecord::Migration[7.1]
  def change
    add_reference :bucket_send_histories, :schedule_item, null: true, foreign_key: true
  end
end
