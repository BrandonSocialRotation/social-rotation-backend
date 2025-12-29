namespace :accounts do
  desc "List all accounts"
  task list: :environment do
    puts "\n=== ALL ACCOUNTS ==="
    puts "=" * 80
    
    accounts = Account.all.order(:id)
    
    if accounts.empty?
      puts "No accounts found."
    else
      accounts.each do |account|
        puts "\nID: #{account.id}"
        puts "  Name: #{account.name}"
        puts "  Reseller: #{account.is_reseller}"
        puts "  Status: #{account.status}"
        puts "  Plan ID: #{account.plan_id || 'none'}"
        puts "  Users: #{account.users.count}"
        puts "  Subscription: #{account.subscription ? account.subscription.id : 'none'}"
        puts "  Created: #{account.created_at}"
        puts "  Updated: #{account.updated_at}"
        puts "-" * 80
      end
      
      puts "\nTotal: #{accounts.count} accounts"
    end
  end

  desc "Delete all accounts (WARNING: This will delete all accounts and associated data)"
  task delete_all: :environment do
    count = Account.count
    puts "\n⚠️  WARNING: This will delete ALL #{count} accounts!"
    puts "This will also delete:"
    puts "  - All users associated with these accounts"
    puts "  - All subscriptions"
    puts "  - All account features"
    puts "  - All RSS feeds"
    puts "\nType 'DELETE ALL ACCOUNTS' to confirm:"
    
    confirmation = STDIN.gets.chomp
    if confirmation == 'DELETE ALL ACCOUNTS'
      puts "\nDeleting all accounts..."
      
      Account.find_each do |account|
        puts "Deleting account ID #{account.id} (#{account.name})..."
        account.destroy
      end
      
      puts "\n✅ All accounts deleted!"
      puts "Remaining accounts: #{Account.count}"
    else
      puts "\n❌ Deletion cancelled."
    end
  end

  desc "Delete a specific account by ID"
  task :delete, [:id] => :environment do |t, args|
    if args[:id].blank?
      puts "Usage: rake accounts:delete[ACCOUNT_ID]"
      exit
    end

    account = Account.find_by(id: args[:id])
    unless account
      puts "❌ Account with ID #{args[:id]} not found."
      exit
    end

    puts "\nAccount to delete:"
    puts "  ID: #{account.id}"
    puts "  Name: #{account.name}"
    puts "  Users: #{account.users.count}"
    puts "  Subscription: #{account.subscription ? 'Yes' : 'No'}"
    puts "\nType 'DELETE' to confirm:"
    
    confirmation = STDIN.gets.chomp
    if confirmation == 'DELETE'
      account.destroy
      puts "\n✅ Account deleted!"
    else
      puts "\n❌ Deletion cancelled."
    end
  end
end
