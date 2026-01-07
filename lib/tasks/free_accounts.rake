# Free Account Management Rake Tasks
# Run with: rails free_accounts:create[name,email,password] or rails free_accounts:list

namespace :free_accounts do
  desc "Create a free account with active subscription"
  task :create, [:name, :email, :password] => :environment do |t, args|
    name = args[:name]
    email = args[:email]
    password = args[:password]
    
    if name.nil? || email.nil? || password.nil?
      puts "Usage: rails free_accounts:create[\"Name\",\"email@example.com\",\"password\"]"
      puts "Example: rails free_accounts:create[\"John Doe\",\"john@example.com\",\"SecurePass123!\"]"
      exit 1
    end
    
    # Find or create Free Access plan
    free_plan = Plan.find_by(name: "Free Access")
    unless free_plan
      puts "❌ Free Access plan not found. Creating it..."
      free_plan = Plan.create!(
        name: "Free Access",
        plan_type: 'personal',
        price_cents: 0,
        base_price_cents: 0,
        max_users: 1,
        max_buckets: 10,
        max_images_per_bucket: 100,
        features_hash: {
          'rss' => true,
          'marketplace' => false,
          'watermark' => true,
          'analytics' => true
        },
        status: false, # Hidden from public
        sort_order: 0
      )
      puts "✓ Created Free Access plan"
    end
    
    # Check if user already exists
    existing_user = User.find_by(email: email)
    if existing_user
      puts "❌ User with email '#{email}' already exists."
      puts "   User: #{existing_user.name} (ID: #{existing_user.id})"
      puts "   Account ID: #{existing_user.account_id}"
      exit 1
    end
    
    puts "\n=== Creating Free Account ==="
    puts "Name: #{name}"
    puts "Email: #{email}"
    
    # Create account
    account = Account.create!(
      name: "#{name}'s Account",
      status: true
    )
    puts "✓ Created account: #{account.name} (ID: #{account.id})"
    
    # Create user
    user = User.create!(
      name: name,
      email: email,
      password: password,
      password_confirmation: password,
      account_id: account.id,
      is_account_admin: true
    )
    puts "✓ Created user: #{user.name} (ID: #{user.id})"
    
    # Create subscription with Free plan
    subscription = Subscription.create!(
      account: account,
      plan: free_plan,
      status: Subscription::STATUS_ACTIVE,
      stripe_customer_id: "free_account_#{account.id}_#{Time.current.to_i}",
      stripe_subscription_id: nil, # No Stripe subscription for free accounts
      current_period_start: Time.current,
      current_period_end: 1.year.from_now, # Free for 1 year (can extend)
      cancel_at_period_end: false
    )
    puts "✓ Created free subscription (active until #{subscription.current_period_end.strftime('%Y-%m-%d')})"
    
    # Update account with plan
    account.update!(plan: free_plan)
    
    puts "\n✅ Free account created successfully!"
    puts "\nAccount Details:"
    puts "  Account ID: #{account.id}"
    puts "  User ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Subscription Status: #{subscription.status}"
    puts "  Free until: #{subscription.current_period_end.strftime('%Y-%m-%d')}"
    puts "\nUser can now log in with:"
    puts "  Email: #{email}"
    puts "  Password: #{password}"
  end
  
  desc "List all free accounts"
  task list: :environment do
    free_plan = Plan.find_by(name: "Free Access")
    
    if free_plan.nil?
      puts "No Free Access plan found."
      exit 0
    end
    
    free_subscriptions = Subscription.where(plan: free_plan).includes(:account, :plan)
    free_accounts = free_subscriptions.map(&:account).compact
    
    puts "\n=== Free Accounts ==="
    if free_accounts.empty?
      puts "No free accounts found."
    else
      free_accounts.each do |account|
        subscription = account.subscription
        user = account.users.first
        puts "\n  Account: #{account.name} (ID: #{account.id})"
        puts "    User: #{user&.name || 'No user'} (#{user&.email || 'N/A'})"
        puts "    Subscription Status: #{subscription&.status || 'None'}"
        if subscription&.current_period_end
          days_left = ((subscription.current_period_end - Time.current) / 86400).to_i
          puts "    Free until: #{subscription.current_period_end.strftime('%Y-%m-%d')} (#{days_left} days left)"
        end
      end
      puts "\nTotal: #{free_accounts.count} free account(s)"
    end
  end
  
  desc "Extend free access for an account"
  task :extend, [:email, :months] => :environment do |t, args|
    email = args[:email]
    months = (args[:months] || 12).to_i
    
    if email.nil?
      puts "Usage: rails free_accounts:extend[email@example.com,12]"
      puts "Example: rails free_accounts:extend[john@example.com,6] (extends by 6 months)"
      exit 1
    end
    
    user = User.find_by(email: email)
    if user.nil?
      puts "❌ User with email '#{email}' not found."
      exit 1
    end
    
    account = user.account
    if account.nil?
      puts "❌ User has no account."
      exit 1
    end
    
    subscription = account.subscription
    if subscription.nil?
      puts "❌ Account has no subscription."
      exit 1
    end
    
    free_plan = Plan.find_by(name: "Free Access")
    if subscription.plan != free_plan
      puts "⚠️  Account is not on Free Access plan (current: #{subscription.plan.name})"
      puts "   Extending anyway..."
    end
    
    new_end_date = [subscription.current_period_end || Time.current, Time.current].max + months.months
    subscription.update!(
      current_period_end: new_end_date,
      status: Subscription::STATUS_ACTIVE
    )
    
    puts "✓ Extended free access for #{user.name} (#{email})"
    puts "  New end date: #{new_end_date.strftime('%Y-%m-%d')}"
    puts "  Days remaining: #{((new_end_date - Time.current) / 86400).to_i} days"
  end
  
  desc "Create multiple free accounts from a CSV file"
  task :bulk_create, [:csv_file] => :environment do |t, args|
    csv_file = args[:csv_file]
    
    if csv_file.nil?
      puts "Usage: rails free_accounts:bulk_create[path/to/file.csv]"
      puts "\nCSV format (no header row needed):"
      puts "  name,email,password"
      puts "  John Doe,john@example.com,password123"
      puts "  Jane Smith,jane@example.com,password456"
      exit 1
    end
    
    unless File.exist?(csv_file)
      puts "❌ File not found: #{csv_file}"
      exit 1
    end
    
    require 'csv'
    
    free_plan = Plan.find_by(name: "Free Access")
    unless free_plan
      puts "Creating Free Access plan..."
      free_plan = Plan.create!(
        name: "Free Access",
        plan_type: 'personal',
        price_cents: 0,
        max_users: 1,
        max_buckets: 10,
        max_images_per_bucket: 100,
        status: false,
        sort_order: 0
      )
    end
    
    puts "\n=== Bulk Creating Free Accounts ==="
    created = 0
    skipped = 0
    errors = []
    
    CSV.foreach(csv_file) do |row|
      name, email, password = row[0], row[1], row[2]
      
      next if name.nil? || email.nil? || password.nil?
      
      if User.exists?(email: email)
        puts "⚠️  Skipping #{email} - already exists"
        skipped += 1
        next
      end
      
      begin
        account = Account.create!(name: "#{name}'s Account", status: true)
        user = User.create!(
          name: name,
          email: email,
          password: password,
          password_confirmation: password,
          account_id: account.id,
          is_account_admin: true
        )
        subscription = Subscription.create!(
          account: account,
          plan: free_plan,
          status: Subscription::STATUS_ACTIVE,
          stripe_customer_id: "free_account_#{account.id}_#{Time.current.to_i}",
          current_period_start: Time.current,
          current_period_end: 1.year.from_now,
          cancel_at_period_end: false
        )
        account.update!(plan: free_plan)
        
        puts "✓ Created: #{name} (#{email})"
        created += 1
      rescue => e
        puts "❌ Error creating #{email}: #{e.message}"
        errors << { email: email, error: e.message }
      end
    end
    
    puts "\n✅ Bulk creation complete!"
    puts "  Created: #{created}"
    puts "  Skipped: #{skipped}"
    puts "  Errors: #{errors.count}"
    
    if errors.any?
      puts "\nErrors:"
      errors.each { |e| puts "  #{e[:email]}: #{e[:error]}" }
    end
  end
end
