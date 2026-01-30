# This file should ensure all data is idempotent (can be run multiple times safely)

# Create default plans
puts "Creating default plans..."

# Personal plan (for individual users) - Per-user pricing
Plan.find_or_create_by(name: "Personal") do |plan|
  plan.plan_type = 'personal'
  plan.price_cents = 4900 # $49/month base (for display purposes)
  plan.base_price_cents = 4900 # $49/month base
  plan.per_user_price_cents = 1500 # $15/user for first 10 additional users
  plan.per_user_price_after_10_cents = 1000 # $10/user for users 11+
  plan.supports_per_user_pricing = true
  plan.billing_period = 'monthly' # Can be 'monthly' or 'annual'
  plan.max_locations = 0 # Not applicable for personal
  plan.max_users = 999 # Unlimited users (pricing is per-user)
  plan.max_buckets = 10
  plan.max_images_per_bucket = 100
  plan.features_hash = {
    'rss' => true,
    'marketplace' => false,
    'watermark' => true,
    'analytics' => true
  }
  plan.status = true
  plan.sort_order = 1
end

# Agency tier plans (based on max sub-accounts)
Plan.find_or_create_by(name: "Agency Starter") do |plan|
  plan.plan_type = 'agency'
  plan.price_cents = 9900 # $99/month
  plan.max_locations = 0 # Not applicable for agency
  plan.max_users = 5 # Max 5 sub-accounts
  plan.max_buckets = 50
  plan.max_images_per_bucket = 500
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true
  }
  plan.status = true
  plan.sort_order = 10
end

Plan.find_or_create_by(name: "Agency Growth") do |plan|
  plan.plan_type = 'agency'
  plan.price_cents = 19900 # $199/month
  plan.max_locations = 0
  plan.max_users = 10 # Max 10 sub-accounts
  plan.max_buckets = 100
  plan.max_images_per_bucket = 1000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => true,
    'ai_copywriting' => true,
    'ai_image_gen' => true
  }
  plan.status = true
  plan.sort_order = 15
end

Plan.find_or_create_by(name: "Agency Professional") do |plan|
  plan.plan_type = 'agency'
  plan.price_cents = 24900 # $249/month
  plan.max_locations = 0
  plan.max_users = 15 # Max 15 sub-accounts
  plan.max_buckets = 150
  plan.max_images_per_bucket = 1500
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => true
  }
  plan.status = true
  plan.sort_order = 20
end

Plan.find_or_create_by(name: "Agency Enterprise") do |plan|
  plan.plan_type = 'agency'
  plan.price_cents = 49900 # $499/month
  plan.max_locations = 0
  plan.max_users = 50 # Max 50 sub-accounts
  plan.max_buckets = 500
  plan.max_images_per_bucket = 5000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => true,
    'ai_copywriting' => true,
    'ai_image_gen' => true
  }
  plan.status = true
  plan.sort_order = 30
end

# Free plan (for free access accounts - not shown in public plans)
Plan.find_or_create_by(name: "Free Access") do |plan|
  plan.plan_type = 'personal'
  plan.price_cents = 0 # Free
  plan.base_price_cents = 0
  plan.per_user_price_cents = 0
  plan.per_user_price_after_10_cents = 0
  plan.supports_per_user_pricing = false
  plan.billing_period = 'monthly'
  plan.max_locations = 0
  plan.max_users = 1
  plan.max_buckets = 10
  plan.max_images_per_bucket = 100
  plan.features_hash = {
    'rss' => true,
    'marketplace' => false,
    'watermark' => true,
    'analytics' => true
  }
  plan.status = false # Hidden from public plans
  plan.sort_order = 0
end

puts "✅ Default plans created!"
