class AddPlanIdToAccounts < ActiveRecord::Migration[7.1]
  def change
    # Add plan_id column (nullable since existing accounts won't have plans)
    add_reference :accounts, :plan, null: true, foreign_key: true
    
    # Note: We don't set a default plan for existing accounts
    # They can select a plan through the subscription flow
  end
end
