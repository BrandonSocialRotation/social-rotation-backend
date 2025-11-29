class CreateOauthRequestTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :oauth_request_tokens do |t|
      t.string :oauth_token
      t.string :request_secret
      t.integer :user_id
      t.datetime :expires_at

      t.timestamps
    end
    add_index :oauth_request_tokens, :oauth_token, unique: true
    add_index :oauth_request_tokens, :expires_at
  end
end
