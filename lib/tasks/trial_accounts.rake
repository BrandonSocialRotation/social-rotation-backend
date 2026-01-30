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
    
    # Create Stripe customer and subscription
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    
    unless Stripe.api_key.present?
      puts "❌ STRIPE_SECRET_KEY not configured. Cannot create Stripe subscription."
      puts "   Account created but subscription is not connected to Stripe."
      puts "   User will need to add payment method through the app."
      exit 1
    end
    
    begin
      # Create Stripe customer
      stripe_customer = Stripe::Customer.create({
        email: email,
        name: name,
        metadata: {
          account_id: account.id.to_s,
          user_id: user.id.to_s,
          trial_account: 'true'
        }
      })
      puts "✓ Created Stripe customer: #{stripe_customer.id}"
      
      # Create Stripe price for the plan
      stripe_price = if plan.stripe_price_id.present?
        # Use existing price
        Stripe::Price.retrieve(plan.stripe_price_id)
      else
        # Create new price
        Stripe::Price.create({
          unit_amount: plan.price_cents,
          currency: 'usd',
          recurring: {
            interval: 'month',
          },
          product_data: {
            name: plan.name
          }
        })
      end
      
      # Calculate trial end timestamp
      trial_end_timestamp = charge_date.end_of_day.to_i
      
      # Create Stripe subscription with trial period
      # Note: Subscription will be in 'incomplete' status until payment method is added
      stripe_subscription = Stripe::Subscription.create({
        customer: stripe_customer.id,
        items: [{ price: stripe_price.id }],
        trial_end: trial_end_timestamp,
        payment_behavior: 'default_incomplete', # Requires payment method to be added
        payment_settings: {
          save_default_payment_method: 'on_subscription'
        },
        metadata: {
          account_id: account.id.to_s,
          plan_id: plan.id.to_s,
          trial_account: 'true'
        }
      })
      puts "✓ Created Stripe subscription: #{stripe_subscription.id}"
      puts "  Status: #{stripe_subscription.status}"
      puts "  Trial ends: #{Time.at(trial_end_timestamp).strftime('%Y-%m-%d %H:%M:%S')}"
      
      # Create local subscription record
      subscription = Subscription.create!(
        account: account,
        plan: plan,
        status: stripe_subscription.status, # Will be 'incomplete' until payment method added
        stripe_customer_id: stripe_customer.id,
        stripe_subscription_id: stripe_subscription.id,
        current_period_start: Time.at(stripe_subscription.current_period_start),
        current_period_end: Time.at(stripe_subscription.current_period_end),
        trial_end: Time.at(stripe_subscription.trial_end),
        cancel_at_period_end: false,
        billing_period: 'monthly'
      )
      puts "✓ Created local subscription record"
      
    rescue Stripe::StripeError => e
      puts "❌ Stripe error: #{e.message}"
      puts "   Account created but subscription is not connected to Stripe."
      puts "   User will need to add payment method through the app."
      
      # Create subscription without Stripe connection as fallback
      subscription = Subscription.create!(
        account: account,
        plan: plan,
        status: Subscription::STATUS_TRIALING,
        stripe_customer_id: "trial_account_#{account.id}_#{Time.current.to_i}",
        stripe_subscription_id: nil,
        current_period_start: Time.current,
        current_period_end: charge_date.end_of_day,
        trial_end: charge_date.end_of_day,
        cancel_at_period_end: false
      )
    end
    
    # Update account with plan
    account.update!(plan: plan)
    
    puts "\n✅ Trial account created successfully!"
    puts "\nAccount Details:"
    puts "  Account ID: #{account.id}"
    puts "  User ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Plan: #{plan.name} ($#{plan.price_cents / 100.0}/month)"
    puts "  Subscription Status: #{subscription.status}"
    puts "  Stripe Customer ID: #{subscription.stripe_customer_id}"
    puts "  Stripe Subscription ID: #{subscription.stripe_subscription_id || 'N/A (needs payment method)'}"
    puts "  Trial End Date: #{subscription.trial_end.strftime('%Y-%m-%d')}"
    puts "  Will be charged on: #{charge_date.strftime('%Y-%m-%d')}"
    
    if subscription.stripe_subscription_id.present?
      puts "\n⚠️  IMPORTANT:"
      puts "  The subscription is connected to Stripe but requires a payment method."
      puts "  User must add a payment method through the app before #{charge_date.strftime('%Y-%m-%d')}."
      puts "  Once payment method is added, Stripe will automatically charge on the trial end date."
      puts "  If payment fails, the account will stop working (status: past_due)."
    else
      puts "\n⚠️  WARNING:"
      puts "  Subscription is NOT connected to Stripe."
      puts "  User must add payment method through the app to enable automatic charging."
    end
    
    puts "\nUser can now log in with:"
    puts "  Email: #{email}"
    puts "  Password: #{password}"
  end
  
  desc "Connect an existing trial account to Stripe"
  task :connect_stripe, [:email] => :environment do |t, args|
    email = args[:email]
    
    if email.nil?
      puts "Usage: rails trial_accounts:connect_stripe[\"email@example.com\"]"
      exit 1
    end
    
    user = User.find_by(email: email)
    unless user
      puts "❌ User with email '#{email}' not found."
      exit 1
    end
    
    account = user.account
    unless account
      puts "❌ User has no account."
      exit 1
    end
    
    subscription = account.subscription
    unless subscription
      puts "❌ Account has no subscription."
      exit 1
    end
    
    if subscription.stripe_subscription_id.present?
      puts "✓ Account already connected to Stripe"
      puts "  Stripe Customer ID: #{subscription.stripe_customer_id}"
      puts "  Stripe Subscription ID: #{subscription.stripe_subscription_id}"
      exit 0
    end
    
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    unless Stripe.api_key.present?
      puts "❌ STRIPE_SECRET_KEY not configured."
      exit 1
    end
    
    plan = subscription.plan
    charge_date = subscription.trial_end || subscription.current_period_end
    
    begin
      # Create Stripe customer
      stripe_customer = Stripe::Customer.create({
        email: user.email,
        name: user.name,
        metadata: {
          account_id: account.id.to_s,
          user_id: user.id.to_s,
          trial_account: 'true'
        }
      })
      puts "✓ Created Stripe customer: #{stripe_customer.id}"
      
      # Create Stripe price for the plan
      stripe_price = if plan.stripe_price_id.present?
        Stripe::Price.retrieve(plan.stripe_price_id)
      else
        Stripe::Price.create({
          unit_amount: plan.price_cents,
          currency: 'usd',
          recurring: {
            interval: 'month',
          },
          product_data: {
            name: plan.name
          }
        })
      end
      
      # Calculate trial end timestamp
      trial_end_timestamp = charge_date.to_i
      
      # Create Stripe subscription with trial period
      stripe_subscription = Stripe::Subscription.create({
        customer: stripe_customer.id,
        items: [{ price: stripe_price.id }],
        trial_end: trial_end_timestamp,
        payment_behavior: 'default_incomplete',
        payment_settings: {
          save_default_payment_method: 'on_subscription'
        },
        metadata: {
          account_id: account.id.to_s,
          plan_id: plan.id.to_s,
          trial_account: 'true'
        }
      })
      puts "✓ Created Stripe subscription: #{stripe_subscription.id}"
      
      # Update local subscription
      subscription.update!(
        stripe_customer_id: stripe_customer.id,
        stripe_subscription_id: stripe_subscription.id,
        status: stripe_subscription.status,
        current_period_start: Time.at(stripe_subscription.current_period_start),
        current_period_end: Time.at(stripe_subscription.current_period_end),
        trial_end: Time.at(stripe_subscription.trial_end)
      )
      
      puts "\n✅ Account connected to Stripe successfully!"
      puts "  Stripe Customer ID: #{stripe_customer.id}"
      puts "  Stripe Subscription ID: #{stripe_subscription.id}"
      puts "  Status: #{stripe_subscription.status}"
      puts "\n⚠️  User must add a payment method through the app before the trial ends."
      
    rescue Stripe::StripeError => e
      puts "❌ Stripe error: #{e.message}"
      exit 1
    end
  end
end

