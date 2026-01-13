class AddIsGlobalToBuckets < ActiveRecord::Migration[7.1]
  def change
    add_column :buckets, :is_global, :boolean, default: false, null: false
  end
end
