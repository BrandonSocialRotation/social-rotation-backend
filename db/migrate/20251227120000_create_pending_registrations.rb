class CreatePendingRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :pending_registrations do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.text :encrypted_password, null: false  # Encrypted (not hashed) so we can decrypt when creating user
      t.string :account_type, null: false
      t.string :company_name
      t.datetime :expires_at, null: false
      t.string :stripe_session_id

      t.timestamps
    end

    add_index :pending_registrations, :email, unique: true
    add_index :pending_registrations, :stripe_session_id
    add_index :pending_registrations, :expires_at
  end
end
