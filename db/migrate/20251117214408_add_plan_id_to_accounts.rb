class AddPlanIdToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_reference :accounts, :plan, null: true, foreign_key: true
  end
end
