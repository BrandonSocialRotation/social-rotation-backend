# Trial Account Management Rake Tasks
# Create trial accounts that will be charged on a specific date

namespace :trial_accounts do
  desc "Create a trial account with specific plan and charge date"
  task :create, [:name, :email, :password, :plan_name, :charge_date] => :environment do |t, args|
    name = args[:name]
    email = args[:email]
    password = args[:password]
    plan_name = args[:plan_name]
    charge_date_str = args[:charge_date] # Format: YYYY-MM-DD
    
    if name.nil? || email.nil? || password.nil? || plan_name.nil? || charge_date_str.nil?
      puts "Usage: rails trial_accounts:create[\"Name\",\"email@example.com\",\"password\",\"Plan Name\",\"YYYY-MM-DD\"]"
      puts "Example: rails trial_accounts:create[\"Adam\",\"adam@hailoint.com\",\"test\",\"Agency Professional\",\"2025-02-15\"]"
      exit 1
    end
    
    # Parse charge date
    begin
      charge_date = Date.parse(charge_date_str)
    rescue ArgumentError
      puts "❌ Invalid date format. Use YYYY-MM-DD (e.g., 2025-02-15)"
      exit 1
    end
    
    # Find plan
    plan = Plan.find_by(name: plan_name)
    unless plan
      puts "❌ Plan '#{plan_name}' not found."
      puts "Available plans:"
      Plan.all.each { |p| puts "  - #{p.name} ($#{p.price_cents / 100.0}/month)" }
      exit 1
    end
    
    # Check if user already exists
    existing_user = User.find_by(email: email)
    if existing_user
      puts "❌ User with email '#{email}' already exists."
      puts "   User: #{existing_user.name} (ID: #{existing_user.id})"
      puts "   Account ID: #{existing_user.account_id}"
      exit 1
    end
    
    puts "\n=== Creating Trial Account ==="
    puts "Name: #{name}"
    puts "Email: #{email}"
    puts "Plan: #{plan.name} ($#{plan.price_cents / 100.0}/month)"
    puts "Charge Date: #{charge_date.strftime('%Y-%m-%d')}"
    
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
    
    # Create subscription with TRIALING status
    # Trial ends on charge_date, which is when they'll be charged
    subscription = Subscription.create!(
      account: account,
      plan: plan,
      status: Subscription::STATUS_TRIALING,
      stripe_customer_id: "trial_account_#{account.id}_#{Time.current.to_i}",
      stripe_subscription_id: nil, # Will be created when they add payment method
      current_period_start: Time.current,
      current_period_end: charge_date.end_of_day, # Trial ends on charge date
      trial_end: charge_date.end_of_day, # Trial end date
      cancel_at_period_end: false
    )
    puts "✓ Created trial subscription (trial until #{subscription.trial_end.strftime('%Y-%m-%d')})"
    
    # Update account with plan
    account.update!(plan: plan)
    
    puts "\n✅ Trial account created successfully!"
    puts "\nAccount Details:"
    puts "  Account ID: #{account.id}"
    puts "  User ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Plan: #{plan.name} ($#{plan.price_cents / 100.0}/month)"
    puts "  Subscription Status: #{subscription.status}"
    puts "  Trial End Date: #{subscription.trial_end.strftime('%Y-%m-%d')}"
    puts "  Will be charged on: #{charge_date.strftime('%Y-%m-%d')}"
    puts "\nUser can now log in with:"
    puts "  Email: #{email}"
    puts "  Password: #{password}"
  end
end

