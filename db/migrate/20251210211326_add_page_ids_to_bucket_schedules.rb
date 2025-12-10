class AddPageIdsToBucketSchedules < ActiveRecord::Migration[7.1]
  def change
    add_column :bucket_schedules, :facebook_page_id, :string
    add_column :bucket_schedules, :linkedin_organization_urn, :string
  end
end
