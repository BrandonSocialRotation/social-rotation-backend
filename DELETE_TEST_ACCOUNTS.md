# How to Delete Test Accounts

## Method 1: Rails Console (Easiest)

1. Go to your DigitalOcean backend console
2. Run: `bundle exec rails console`
3. Use these commands:

### Delete a user by email:
```ruby
user = User.find_by(email: 'test@example.com')
if user
  # Delete associated account if user is account admin
  if user.account && user.is_account_admin
    account = user.account
    # Delete subscription if exists
    account.subscription&.destroy
    # Delete account (this will also delete the user due to dependent: :destroy)
    account.destroy
  else
    # Just delete the user
    user.destroy
  end
  puts "User and account deleted successfully"
else
  puts "User not found"
end
```

### List all users to see what to delete:
```ruby
User.all.each do |u|
  puts "#{u.id}: #{u.email} - #{u.name} (Account ID: #{u.account_id})"
end
```

### Delete multiple users at once:
```ruby
emails_to_delete = ['test1@example.com', 'test2@example.com']
emails_to_delete.each do |email|
  user = User.find_by(email: email)
  if user
    if user.account && user.is_account_admin
      user.account.subscription&.destroy
      user.account.destroy
    else
      user.destroy
    end
    puts "Deleted: #{email}"
  end
end
```

## Method 2: Admin Endpoint (Future Use)

There's an admin endpoint at `/api/v1/user_info/delete_test_account` that requires super admin access.

