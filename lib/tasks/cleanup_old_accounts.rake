namespace :cleanup do
  desc "Find and optionally delete users created before payment-first flow (no active subscription)"
  task :old_accounts, [:delete] => :environment do |t, args|
    delete_mode = args[:delete] == 'true'
    
    puts "\n=== Finding Users Without Active Subscriptions ==="
    puts "=" * 80
    
    # Find users without active subscriptions
    users_without_subscriptions = User.left_joins(account: :subscription)
      .where(subscriptions: { id: nil })
      .or(User.left_joins(account: :subscription).where.not(subscriptions: { status: 'active' }))
      .distinct
    
    # Also find users with account_id = 0 (personal accounts that might not have subscriptions)
    personal_users = User.where(account_id: 0)
    
    all_suspect_users = (users_without_subscriptions + personal_users).uniq
    
    if all_suspect_users.empty?
      puts "No users found without active subscriptions."
    else
      puts "\nFound #{all_suspect_users.count} user(s) without active subscriptions:\n"
      
      all_suspect_users.each do |user|
        account = user.account_id && user.account_id != 0 ? Account.find_by(id: user.account_id) : nil
        subscription = account&.subscription
        
        puts "\nUser ID: #{user.id}"
        puts "  Email: #{user.email}"
        puts "  Name: #{user.name}"
        puts "  Account ID: #{user.account_id || 'none'}"
        puts "  Account Name: #{account&.name || 'none'}"
        puts "  Subscription: #{subscription ? subscription.status : 'none'}"
        puts "  Created: #{user.created_at}"
        puts "-" * 80
      end
      
      if delete_mode
        puts "\n⚠️  DELETION MODE ENABLED"
        puts "Type 'DELETE ALL' to confirm deletion of all #{all_suspect_users.count} users:"
        confirmation = STDIN.gets.chomp
        
        if confirmation == 'DELETE ALL'
          deleted_count = 0
          all_suspect_users.each do |user|
            puts "Deleting user #{user.id} (#{user.email})..."
            user.destroy
            deleted_count += 1
          end
          puts "\n✅ Deleted #{deleted_count} user(s)"
        else
          puts "\n❌ Deletion cancelled."
        end
      else
        puts "\n💡 To delete these users, run:"
        puts "   rake cleanup:old_accounts[true]"
      end
    end
  end

  desc "Delete a specific user by email"
  task :delete_user, [:email] => :environment do |t, args|
    email = args[:email]
    
    unless email.present?
      puts "Usage: rake cleanup:delete_user[email@example.com]"
      exit
    end
    
    user = User.find_by(email: email)
    unless user
      puts "❌ User with email '#{email}' not found."
      exit
    end
    
    puts "\nUser to delete:"
    puts "  ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Name: #{user.name}"
    puts "  Account ID: #{user.account_id}"
    puts "  Created: #{user.created_at}"
    puts "\nType 'DELETE' to confirm:"
    
    confirmation = STDIN.gets.chomp
    if confirmation == 'DELETE'
      user.destroy
      puts "\n✅ User deleted!"
    else
      puts "\n❌ Deletion cancelled."
    end
  end
end
