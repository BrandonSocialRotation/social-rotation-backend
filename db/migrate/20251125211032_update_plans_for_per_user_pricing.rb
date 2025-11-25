class UpdatePlansForPerUserPricing < ActiveRecord::Migration[7.1]
  def change
    # Add per-user pricing fields
    add_column :plans, :base_price_cents, :integer, default: 0
    add_column :plans, :per_user_price_cents, :integer, default: 0
    add_column :plans, :per_user_price_after_10_cents, :integer, default: 0
    add_column :plans, :billing_period, :string, default: 'monthly' # 'monthly' or 'annual'
    add_column :plans, :supports_per_user_pricing, :boolean, default: false
    
    # Add billing period to subscriptions
    add_column :subscriptions, :billing_period, :string, default: 'monthly'
    add_column :subscriptions, :user_count_at_subscription, :integer # Store user count when subscription was created
    
    # Update existing Personal plan to use new pricing
    execute <<-SQL
      UPDATE plans 
      SET base_price_cents = 4900,
          per_user_price_cents = 1500,
          per_user_price_after_10_cents = 1000,
          supports_per_user_pricing = true,
          billing_period = 'monthly'
      WHERE plan_type = 'personal' AND name = 'Personal'
    SQL
  end
end
