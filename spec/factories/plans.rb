FactoryBot.define do
  factory :plan do
    name { "MyString" }
    plan_type { "MyString" }
    stripe_price_id { "MyString" }
    stripe_product_id { "MyString" }
    price_cents { 1 }
    max_locations { 1 }
    max_users { 1 }
    max_buckets { 1 }
    max_images_per_bucket { 1 }
    features { "MyText" }
    status { false }
  end
end
