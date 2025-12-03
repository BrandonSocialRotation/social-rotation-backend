class AddPinterestToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :pinterest_access_token, :string
    add_column :users, :pinterest_refresh_token, :string
  end
end
