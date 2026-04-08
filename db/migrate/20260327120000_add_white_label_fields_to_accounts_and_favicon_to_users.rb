# frozen_string_literal: true

class AddWhiteLabelFieldsToAccountsAndFaviconToUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.string :business_name
      t.string :software_title
      t.string :business_address
      t.string :business_city
      t.string :business_state
      t.string :business_country
      t.string :business_postal_code
    end

    add_column :users, :favicon_logo, :string
  end
end
