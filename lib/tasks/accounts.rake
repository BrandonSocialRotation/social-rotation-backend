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

  desc "Show account status for a user. Usage: rails accounts:status[email]"
  task :status, [:email] => :environment do |_t, args|
    email = args[:email].to_s.strip
    if email.blank?
      puts "Usage: rails accounts:status[email]"
      puts "Example: rails accounts:status[jjharrison1@yahoo.com]"
      exit 1
    end

    user = User.find_by(email: email)
    unless user
      puts "❌ No user found with email: #{email}"
      exit 1
    end

    puts "\n=== ACCOUNT STATUS: #{email} ==="
    puts "User ID: #{user.id}"
    puts "Name: #{user.name}"
    puts "Account ID: #{user.account_id.inspect}"
    puts "Is Account Admin: #{user.is_account_admin}"

    if user.account_id.nil? || user.account_id == 0
      puts "\n⚠️  NO ACCOUNT - User has account_id #{user.account_id.inspect}"
      puts "   This user may have paid but never got an account (webhook/checkout issue)."
      puts "   Fix: Create account + subscription, or have them re-register."
      exit 0
    end

    account = user.account
    unless account
      puts "\n❌ Account ID #{user.account_id} not found (orphaned user)"
      exit 1
    end

    puts "\nAccount: #{account.name} (ID: #{account.id})"
    puts "Plan: #{account.plan&.name || 'none'} (plan_id: #{account.plan_id})"

    sub = account.subscription
    unless sub
      puts "\n⚠️  NO SUBSCRIPTION - Account has no subscription"
      puts "   Fix: Create a subscription for this account."
      exit 0
    end

    puts "\nSubscription:"
    puts "  Status: #{sub.status}"
    puts "  Plan: #{sub.plan&.name}"
    puts "  Stripe Customer ID: #{sub.stripe_customer_id}"
    puts "  Stripe Subscription ID: #{sub.stripe_subscription_id}"
    puts "  Current Period End: #{sub.current_period_end}"
    puts "  Has Active Subscription?: #{account.has_active_subscription?}"

    if sub.plan&.name == "Free Access"
      puts "\n⚠️  ON FREE ACCESS PLAN"
      if sub.current_period_end && sub.current_period_end < Time.current
        puts "   Subscription EXPIRED: #{sub.current_period_end}"
        puts "   Fix: Extend current_period_end or upgrade to paid plan."
      else
        puts "   If they paid, they may be stuck - upgrade plan to paid."
      end
    end
    puts "\n"
  end

  desc "List accounts that might be stuck (Free plan, or paid but wrong status)"
  task stuck: :environment do
    puts "\n=== POTENTIALLY STUCK ACCOUNTS ==="
    puts ""

    # Users with account_id 0 or nil (no account)
    no_account = User.where(account_id: [nil, 0]).where.not(email: nil)
    if no_account.any?
      puts "Users with NO ACCOUNT (account_id 0 or nil):"
      no_account.each { |u| puts "  #{u.email} (ID: #{u.id})" }
      puts ""
    end

    # Accounts with Free Access plan
    free_plan = Plan.find_by(name: "Free Access")
    if free_plan
      Subscription.where(plan: free_plan).includes(account: :users).each do |sub|
        acc = sub.account
        user = acc.users.first
        expired = sub.current_period_end && sub.current_period_end < Time.current
        puts "FREE: #{user&.email || 'no user'} | Account #{acc.id} | #{sub.status} | Expired: #{expired} | End: #{sub.current_period_end}"
      end
      puts ""
    end

    # Accounts with Stripe but subscription status not active/trialing
    Subscription.where.not(stripe_customer_id: nil).where.not(status: [Subscription::STATUS_ACTIVE, Subscription::STATUS_TRIALING]).each do |sub|
      user = sub.account.users.first
      puts "NON-ACTIVE STRIPE: #{user&.email} | Account #{sub.account_id} | Status: #{sub.status} | Plan: #{sub.plan&.name}"
    end

    puts "\nDone."
  end

  desc "Upgrade plan for an account. Usage: rails accounts:upgrade_plan[email,plan_name]"
  task :upgrade_plan, [:email, :plan_name] => :environment do |_t, args|
    email = args[:email].to_s.strip
    plan_name = args[:plan_name].to_s.strip
    if email.blank? || plan_name.blank?
      puts "Usage: rails accounts:upgrade_plan[email,plan_name]"
      puts "Example: rails accounts:upgrade_plan[jjharrison1@yahoo.com,Personal]"
      puts "Plans: #{Plan.pluck(:name).join(', ')}"
      exit 1
    end

    user = User.find_by(email: email)
    unless user
      puts "❌ User not found: #{email}"
      exit 1
    end
    unless user.account_id.present? && user.account_id > 0
      puts "❌ User has no account (account_id: #{user.account_id})"
      exit 1
    end

    plan = Plan.find_by(name: plan_name)
    unless plan
      puts "❌ Plan not found: #{plan_name}"
      puts "Available: #{Plan.pluck(:name).join(', ')}"
      exit 1
    end

    account = user.account
    sub = account.subscription
    unless sub
      puts "❌ Account has no subscription"
      exit 1
    end

    old_plan = sub.plan&.name
    sub.update!(plan: plan)
    account.update!(plan: plan)

    puts "✅ Upgraded #{email} from #{old_plan} to #{plan.name}"
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
