# This file should ensure all data is idempotent (can be run multiple times safely)

# Create default plans
puts "Creating default plans..."

# Personal plan (for individual users)
Plan.find_or_create_by(name: "Personal") do |plan|
  plan.plan_type = 'personal'
  plan.price_cents = 2900 # $29/month
  plan.max_locations = 0 # Not applicable for personal
  plan.max_users = 1
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

puts "✅ Default plans created!"
