namespace :accounts do
  desc "Create a free agency account at highest tier (Agency Enterprise). Usage: rails accounts:create_free_agency[email] or rails accounts:create_free_agency[email,name,password]"
  task :create_free_agency, [:email, :name, :password] => :environment do |_t, args|
    email = args[:email].to_s.strip
    if email.blank?
      puts "Usage: rails accounts:create_free_agency[email]"
      puts "       rails accounts:create_free_agency[email,name,password]"
      puts "Example: rails accounts:create_free_agency[btantillo@gmail.com]"
      exit 1
    end

    if User.exists?(email: email)
      puts "❌ User with email '#{email}' already exists."
      exit 1
    end

    plan = Plan.find_by(name: "Agency Enterprise")
    unless plan
      puts "❌ Plan 'Agency Enterprise' not found."
      exit 1
    end

    name = args[:name].to_s.strip.presence || email.split('@').first.titleize
    password = args[:password].to_s.presence || SecureRandom.alphanumeric(16)

    account = Account.create!(
      name: "#{name}'s Agency",
      is_reseller: true,
      status: true
    )
    user = User.create!(
      name: name,
      email: email,
      password: password,
      password_confirmation: password,
      account_id: account.id,
      is_account_admin: true,
      role: 'reseller',
      status: 1
    )
    Subscription.create!(
      account: account,
      plan: plan,
      status: Subscription::STATUS_ACTIVE,
      stripe_customer_id: "comp_#{email.parameterize}_#{account.id}",
      stripe_subscription_id: nil,
      billing_period: 'monthly',
      user_count_at_subscription: 1,
      current_period_start: Time.current,
      current_period_end: 10.years.from_now,
      cancel_at_period_end: false
    )
    account.update!(plan: plan)

    puts "✅ Created free Agency Enterprise account for #{email}"
    puts "   Account ID: #{account.id}"
    puts "   User ID: #{user.id}"
    puts "   Plan: Agency Enterprise (50 sub-accounts, 500 buckets, etc.)"
    puts "   Login: #{email} / #{password}"
    puts "   (They should change password after first login.)"
  end

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
