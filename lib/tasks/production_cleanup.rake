namespace :production do
  desc "Delete a user by email (for cleaning up old test accounts)"
  task :delete_user_by_email, [:email] => :environment do |t, args|
    email = args[:email]
    
    unless email.present?
      puts "Usage: RAILS_ENV=production bundle exec rake production:delete_user_by_email[email@example.com]"
      exit 1
    end
    
    user = User.find_by(email: email)
    unless user
      puts "❌ User with email '#{email}' not found."
      exit 1
    end
    
    puts "\n⚠️  WARNING: This will delete the user and all associated data!"
    puts "\nUser details:"
    puts "  ID: #{user.id}"
    puts "  Email: #{user.email}"
    puts "  Name: #{user.name}"
    puts "  Account ID: #{user.account_id || 'none'}"
    puts "  Created: #{user.created_at}"
    
    # Check for related data
    bucket_count = user.buckets.count
    video_count = user.videos.count
    puts "  Buckets: #{bucket_count}"
    puts "  Videos: #{video_count}"
    
    puts "\nType 'DELETE' to confirm:"
    confirmation = STDIN.gets.chomp
    
    if confirmation == 'DELETE'
      user.destroy
      puts "\n✅ User '#{email}' deleted successfully!"
    else
      puts "\n❌ Deletion cancelled."
    end
  end

  desc "List all users with a specific email pattern (for finding test accounts)"
  task :find_users, [:pattern] => :environment do |t, args|
    pattern = args[:pattern] || '%test%'
    
    users = User.where("email LIKE ?", pattern).order(:created_at)
    
    if users.empty?
      puts "No users found matching pattern: #{pattern}"
    else
      puts "\nFound #{users.count} user(s) matching '#{pattern}':\n"
      puts "=" * 80
      
      users.each do |user|
        account = user.account_id && user.account_id != 0 ? Account.find_by(id: user.account_id) : nil
        subscription = account&.subscription
        
        puts "\nID: #{user.id}"
        puts "  Email: #{user.email}"
        puts "  Name: #{user.name}"
        puts "  Account ID: #{user.account_id || 'none'}"
        puts "  Account: #{account ? account.name : 'none'}"
        puts "  Subscription: #{subscription ? subscription.status : 'none'}"
        puts "  Created: #{user.created_at}"
        puts "-" * 80
      end
    end
  end
end
