class CreatePlans < ActiveRecord::Migration[7.1]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :plan_type, null: false # 'location_based' or 'user_seat_based'
      t.string :stripe_price_id
      t.string :stripe_product_id
      t.integer :price_cents, default: 0
      t.integer :max_locations, default: 1 # For location-based plans
      t.integer :max_users, default: 1 # For user-seat-based plans
      t.integer :max_buckets, default: 10
      t.integer :max_images_per_bucket, default: 100
      t.text :features # JSON string of enabled features
      t.boolean :status, default: true
      t.integer :sort_order, default: 0 # For display ordering

      t.timestamps
    end
    
    add_index :plans, :plan_type
    add_index :plans, :status
    add_index :plans, :stripe_price_id, unique: true
  end
end
