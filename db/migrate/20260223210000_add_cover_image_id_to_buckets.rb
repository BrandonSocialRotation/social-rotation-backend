# frozen_string_literal: true

class AddCoverImageIdToBuckets < ActiveRecord::Migration[7.1]
  def change
    add_reference :buckets, :cover_image, null: true, foreign_key: { to_table: :images }
  end
end
