# This file should ensure all data is idempotent (can be run multiple times safely)

# Create default plans
puts "Creating default plans..."

# Location-based plans
Plan.find_or_create_by(name: "Single Location") do |plan|
  plan.plan_type = 'location_based'
  plan.price_cents = 2900 # $29/month
  plan.max_locations = 1
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

Plan.find_or_create_by(name: "10 Locations") do |plan|
  plan.plan_type = 'location_based'
  plan.price_cents = 9900 # $99/month
  plan.max_locations = 10
  plan.max_users = 10
  plan.max_buckets = 100
  plan.max_images_per_bucket = 1000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => false
  }
  plan.status = true
  plan.sort_order = 2
end

Plan.find_or_create_by(name: "30 Locations") do |plan|
  plan.plan_type = 'location_based'
  plan.price_cents = 24900 # $249/month
  plan.max_locations = 30
  plan.max_users = 30
  plan.max_buckets = 300
  plan.max_images_per_bucket = 5000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => true,
    'priority_support' => true
  }
  plan.status = true
  plan.sort_order = 3
end

# User-seat-based plans
Plan.find_or_create_by(name: "Starter (5 Seats)") do |plan|
  plan.plan_type = 'user_seat_based'
  plan.price_cents = 4900 # $49/month
  plan.max_users = 5
  plan.max_locations = 1 # Not applicable for seat-based, but set default
  plan.max_buckets = 50
  plan.max_images_per_bucket = 500
  plan.features_hash = {
    'rss' => true,
    'marketplace' => false,
    'watermark' => true,
    'analytics' => true
  }
  plan.status = true
  plan.sort_order = 4
end

Plan.find_or_create_by(name: "Professional (15 Seats)") do |plan|
  plan.plan_type = 'user_seat_based'
  plan.price_cents = 14900 # $149/month
  plan.max_users = 15
  plan.max_locations = 1 # Not applicable for seat-based, but set default
  plan.max_buckets = 150
  plan.max_images_per_bucket = 2000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => false
  }
  plan.status = true
  plan.sort_order = 5
end

Plan.find_or_create_by(name: "Enterprise (50 Seats)") do |plan|
  plan.plan_type = 'user_seat_based'
  plan.price_cents = 49900 # $499/month
  plan.max_users = 50
  plan.max_locations = 1 # Not applicable for seat-based, but set default
  plan.max_buckets = 500
  plan.max_images_per_bucket = 10000
  plan.features_hash = {
    'rss' => true,
    'marketplace' => true,
    'watermark' => true,
    'analytics' => true,
    'white_label' => true,
    'priority_support' => true,
    'api_access' => true
  }
  plan.status = true
  plan.sort_order = 6
end

puts "✅ Default plans created!"
