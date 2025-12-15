class CreateBucketVideos < ActiveRecord::Migration[7.1]
  def change
    create_table :bucket_videos do |t|
      t.references :bucket, null: false, foreign_key: true
      t.references :video, null: false, foreign_key: true
      t.string :friendly_name
      t.text :description
      t.text :twitter_description
      t.integer :post_to
      t.boolean :use_watermark, default: false

      t.timestamps
    end
    
    add_index :bucket_videos, [:bucket_id, :video_id], unique: true
  end
end
