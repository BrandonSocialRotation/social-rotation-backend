FactoryBot.define do
  factory :plan do
    name { Faker::Company.name }
    plan_type { "personal" }
    stripe_price_id { "price_#{SecureRandom.hex(8)}" }
    stripe_product_id { "prod_#{SecureRandom.hex(8)}" }
    price_cents { 1000 }
    max_locations { 1 }
    max_users { 1 }
    max_buckets { 10 }
    max_images_per_bucket { 100 }
    features { {}.to_json }
    status { true }
  end
end
