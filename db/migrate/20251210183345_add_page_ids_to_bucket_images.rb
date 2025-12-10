class AddPageIdsToBucketImages < ActiveRecord::Migration[7.1]
  def change
    add_column :bucket_images, :facebook_page_id, :string
    add_column :bucket_images, :linkedin_organization_urn, :string
  end
end
