# Rails Console Commands for Account Management

## Create account and connect to existing Stripe (no charge/refund)

Use this when the customer already has a Stripe subscription and you only need to create the app account and link it.

**Option A – One command (no brackets).** Run from the app directory. Uses env vars so `rails trial_accounts:create_and_connect_env` is recognized:

```bash
NAME="Mellorya Bullard" EMAIL="drwynndc@gmail.com" PASSWORD="ChangeMe123" PLAN="Agency Enterprise" STRIPE_CUSTOMER_ID="cus_MHXm3Y16YjSBwM" STRIPE_SUBSCRIPTION_ID="sub_1LYygtDjghj5sy3y4FVHO1bT" bin/rails trial_accounts:create_and_connect_env
```

Change the quoted values for each new customer. Deploy the latest code so this task exists on the server.

**Option B – From Rails console (always works, no task needed).** Run `rails console`, then paste:

```ruby
email = "drwynndc@gmail.com"
name = "Mellorya Bullard"
password = "ChangeMe123"
plan_name = "Agency Enterprise"
stripe_customer_id = "cus_MHXm3Y16YjSBwM"
stripe_subscription_id = "sub_1LYygtDjghj5sy3y4FVHO1bT"

plan = Plan.find_by(name: plan_name)
raise "Plan not found" unless plan
raise "User exists" if User.exists?(email: email)

account = Account.create!(name: "#{name}'s Account", status: true)
user = User.create!(name: name, email: email, password: password, password_confirmation: password, account_id: account.id, is_account_admin: true)
subscription = Subscription.create!(account: account, plan: plan, status: "trialing", stripe_customer_id: nil, stripe_subscription_id: nil, billing_period: "monthly")
account.update!(plan: plan)

stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
subscription.update!(stripe_customer_id: stripe_customer_id, stripe_subscription_id: stripe_subscription_id, status: stripe_sub.status, current_period_start: Time.at(stripe_sub.current_period_start), current_period_end: Time.at(stripe_sub.current_period_end), trial_end: stripe_sub.trial_end ? Time.at(stripe_sub.trial_end) : nil, cancel_at_period_end: stripe_sub.cancel_at_period_end)
puts "Done. #{email} can log in."
```

Change the variables at the top for each new customer.

---

## View All Accounts

```ruby
# List all accounts with details
Account.all.each do |account|
  puts "ID: #{account.id}"
  puts "  Name: #{account.name}"
  puts "  Reseller: #{account.is_reseller}"
  puts "  Status: #{account.status}"
  puts "  Plan ID: #{account.plan_id}"
  puts "  Users: #{account.users.count}"
  puts "  Subscription: #{account.subscription ? account.subscription.status : 'none'}"
  puts "  Created: #{account.created_at}"
  puts "-" * 80
end

# Count total accounts
puts "Total accounts: #{Account.count}"
```

## View Account Details

```ruby
# Find account by ID
account = Account.find(1)

# See all details
account.inspect

# See users in this account
account.users.each { |u| puts "#{u.id}: #{u.email} (#{u.name})" }

# See subscription
account.subscription

# See account features
account.account_feature
```

## Delete Individual Account

```ruby
# Find the account
account = Account.find(1)  # Replace 1 with the account ID

# Check what will be deleted
puts "Account: #{account.name}"
puts "Users: #{account.users.count}"
puts "Subscription: #{account.subscription ? 'Yes' : 'No'}"
puts "RSS Feeds: #{account.rss_feeds.count}"

# Delete the account (cascade will handle related records)
account.destroy

# Verify deletion
Account.find_by(id: 1)  # Should return nil
```

## Delete Account by Name

```ruby
# Find account by name
account = Account.find_by(name: "Test Agency")

# Delete it
account&.destroy
```

## Delete All Accounts

```ruby
# First, see what you're about to delete
Account.all.each do |account|
  puts "Account ID #{account.id}: #{account.name} (#{account.users.count} users)"
end

puts "\nTotal accounts to delete: #{Account.count}"

# Delete all accounts
Account.destroy_all

# Or use delete_all (faster, but doesn't run callbacks)
# Account.delete_all

# Verify all deleted
puts "Remaining accounts: #{Account.count}"
```

## Delete Account and Related Users

```ruby
# If you want to delete account AND all its users
account = Account.find(1)

# Delete users first (optional - account destroy will nullify account_id)
account.users.destroy_all

# Then delete account
account.destroy
```

## Find Accounts Without Active Subscriptions

```ruby
# Find accounts that don't have active subscriptions
accounts_without_subscriptions = Account.left_joins(:subscription)
  .where(subscriptions: { id: nil })
  .or(Account.left_joins(:subscription).where.not(subscriptions: { status: 'active' }))
  .distinct

accounts_without_subscriptions.each do |account|
  puts "ID: #{account.id}, Name: #{account.name}, Subscription: #{account.subscription ? account.subscription.status : 'none'}"
end
```

## Delete Accounts Without Active Subscriptions

```ruby
# Find and delete accounts without active subscriptions
accounts_without_subscriptions = Account.left_joins(:subscription)
  .where(subscriptions: { id: nil })
  .or(Account.left_joins(:subscription).where.not(subscriptions: { status: 'active' }))
  .distinct

puts "Found #{accounts_without_subscriptions.count} accounts without active subscriptions"

# Delete them
accounts_without_subscriptions.destroy_all
```

## View All Users (to see which accounts they belong to)

```ruby
# List all users with their account info
User.all.each do |user|
  account_info = user.account_id ? "Account ID: #{user.account_id}" : "No account"
  puts "User ID: #{user.id}, Email: #{user.email}, #{account_info}"
end
```

## Quick One-Liners

```ruby
# Count accounts
Account.count

# List account IDs and names
Account.pluck(:id, :name)

# Delete account by ID
Account.find(1).destroy

# Delete all accounts
Account.destroy_all
```
