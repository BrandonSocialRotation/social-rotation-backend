namespace :users do
  desc "Delete users by email (keeps jbickler4@gmail.com)"
  task :delete_except_jbickler => :environment do
    keep_email = 'jbickler4@gmail.com'
    
    # Find all users except the one to keep
    users_to_delete = User.where.not(email: keep_email)
    
    if users_to_delete.empty?
      puts "No users to delete (only #{keep_email} exists)"
      exit 0
    end
    
    puts "\n⚠️  WARNING: This will delete #{users_to_delete.count} user(s)!"
    puts "\nUsers to be deleted:"
    users_to_delete.each do |user|
      account = user.account_id && user.account_id != 0 ? Account.find_by(id: user.account_id) : nil
      subscription = account&.subscription
      
      puts "  - ID: #{user.id}, Email: #{user.email}, Name: #{user.name}"
      puts "    Account ID: #{user.account_id || 'none'}, Subscription: #{subscription ? subscription.status : 'none'}"
    end
    
    puts "\nUser to keep:"
    keep_user = User.find_by(email: keep_email)
    if keep_user
      account = keep_user.account_id && keep_user.account_id != 0 ? Account.find_by(id: keep_user.account_id) : nil
      subscription = account&.subscription
      puts "  - ID: #{keep_user.id}, Email: #{keep_user.email}, Name: #{keep_user.name}"
      puts "    Account ID: #{keep_user.account_id || 'none'}, Subscription: #{subscription ? subscription.status : 'none'}"
    else
      puts "  - NOT FOUND! Aborting to prevent deleting all users."
      exit 1
    end
    
    puts "\nType 'DELETE' to confirm:"
    confirmation = STDIN.gets.chomp
    
    if confirmation == 'DELETE'
      deleted_count = 0
      users_to_delete.each do |user|
        begin
          user.destroy
          deleted_count += 1
          puts "✅ Deleted user: #{user.email} (ID: #{user.id})"
        rescue => e
          puts "❌ Failed to delete user #{user.email}: #{e.message}"
        end
      end
      
      puts "\n✅ Successfully deleted #{deleted_count} user(s)!"
      puts "Remaining users: #{User.count}"
    else
      puts "\n❌ Deletion cancelled."
    end
  end
end
