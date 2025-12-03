class AddAccountInfoToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :facebook_name, :string
    add_column :users, :google_account_name, :string
    add_column :users, :pinterest_username, :string
  end
end
