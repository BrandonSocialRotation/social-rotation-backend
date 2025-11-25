class UpdatePlansForPersonalAndAgency < ActiveRecord::Migration[7.1]
  def up
    # Delete old location-based and user-seat-based plans
    execute "DELETE FROM plans WHERE plan_type IN ('location_based', 'user_seat_based')"
    
    # Create Personal plan (using raw SQL to avoid model validations)
    personal_features = { 'rss' => true, 'marketplace' => false, 'watermark' => true, 'analytics' => true }.to_json
    execute <<-SQL
      INSERT INTO plans (name, plan_type, price_cents, max_locations, max_users, max_buckets, max_images_per_bucket, features, status, sort_order, created_at, updated_at)
      SELECT 'Personal', 'personal', 2900, 0, 1, 10, 100, '#{personal_features.gsub("'", "''")}', true, 1, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM plans WHERE name = 'Personal' AND plan_type = 'personal')
    SQL
    
    # Create Agency Starter
    agency_starter_features = { 'rss' => true, 'marketplace' => true, 'watermark' => true, 'analytics' => true }.to_json
    execute <<-SQL
      INSERT INTO plans (name, plan_type, price_cents, max_locations, max_users, max_buckets, max_images_per_bucket, features, status, sort_order, created_at, updated_at)
      SELECT 'Agency Starter', 'agency', 9900, 0, 5, 50, 500, '#{agency_starter_features.gsub("'", "''")}', true, 10, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM plans WHERE name = 'Agency Starter' AND plan_type = 'agency')
    SQL
    
    # Create Agency Professional
    agency_pro_features = { 'rss' => true, 'marketplace' => true, 'watermark' => true, 'analytics' => true, 'white_label' => true }.to_json
    execute <<-SQL
      INSERT INTO plans (name, plan_type, price_cents, max_locations, max_users, max_buckets, max_images_per_bucket, features, status, sort_order, created_at, updated_at)
      SELECT 'Agency Professional', 'agency', 24900, 0, 15, 150, 1500, '#{agency_pro_features.gsub("'", "''")}', true, 20, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM plans WHERE name = 'Agency Professional' AND plan_type = 'agency')
    SQL
    
    # Create Agency Enterprise
    agency_ent_features = { 'rss' => true, 'marketplace' => true, 'watermark' => true, 'analytics' => true, 'white_label' => true, 'ai_copywriting' => true, 'ai_image_gen' => true }.to_json
    execute <<-SQL
      INSERT INTO plans (name, plan_type, price_cents, max_locations, max_users, max_buckets, max_images_per_bucket, features, status, sort_order, created_at, updated_at)
      SELECT 'Agency Enterprise', 'agency', 49900, 0, 50, 500, 5000, '#{agency_ent_features.gsub("'", "''")}', true, 30, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM plans WHERE name = 'Agency Enterprise' AND plan_type = 'agency')
    SQL
  end
  
  def down
    # Revert: Delete personal and agency plans, restore old structure
    Plan.where(plan_type: ['personal', 'agency']).destroy_all
    # Note: Old plans would need to be recreated manually if needed
  end
end
