FactoryBot.define do
  factory :subscription do
    association :account
    association :plan
    stripe_subscription_id { "sub_#{SecureRandom.hex(8)}" }
    stripe_customer_id { "cus_#{SecureRandom.hex(8)}" }
    status { Subscription::STATUS_ACTIVE }
    current_period_start { Time.current }
    current_period_end { 1.month.from_now }
    cancel_at_period_end { false }
  end
end
