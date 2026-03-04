class AddPinterestBoardIdToBucketSchedules < ActiveRecord::Migration[7.1]
  def change
    add_column :bucket_schedules, :pinterest_board_id, :string
  end
end
