# frozen_string_literal: true

class AddClientPortalToUsersAndDomains < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :client_portal_only, :boolean, default: false, null: false

    create_table :client_portal_domains do |t|
      t.string :hostname, null: false
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.jsonb :branding, default: {}, null: false
      t.timestamps
    end

    add_index :client_portal_domains, :hostname, unique: true
  end
end
