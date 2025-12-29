# Rails Console Commands for Account Management

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
