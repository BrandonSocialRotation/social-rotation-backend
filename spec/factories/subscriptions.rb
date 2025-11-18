FactoryBot.define do
  factory :subscription do
    account { nil }
    stripe_subscription_id { "MyString" }
    stripe_customer_id { "MyString" }
    plan { nil }
    status { "MyString" }
    current_period_start { "2025-11-17 14:43:38" }
    current_period_end { "2025-11-17 14:43:38" }
    cancel_at_period_end { false }
  end
end
