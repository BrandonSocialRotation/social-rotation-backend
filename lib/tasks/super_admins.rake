# Super Admin Management Rake Tasks
# Run with: rails super_admins:set[email1,email2,email3] or rails super_admins:list

namespace :super_admins do
  desc "Set users as super admins (bypass subscription checks)"
  task :set, [:emails] => :environment do |t, args|
    emails = args[:emails]&.split(',')&.map(&:strip) || []
    
    if emails.empty?
      puts "Usage: rails super_admins:set[email1@example.com,email2@example.com,email3@example.com]"
      puts "Or provide emails as comma-separated list"
      exit 1
    end
    
    puts "\n=== Setting Super Admin Status ==="
    emails.each do |email|
      user = User.find_by(email: email)
      
      if user.nil?
        puts "❌ User with email '#{email}' not found. Skipping..."
        next
      end
      
      if user.account_id == 0
        puts "✓ User '#{user.name}' (#{email}) is already a super admin"
      else
        old_account_id = user.account_id
        user.update!(account_id: 0)
        puts "✓ Set user '#{user.name}' (#{email}) as super admin (was account_id: #{old_account_id})"
      end
    end
    
    puts "\n✅ Super admin setup complete!"
    puts "\nNote: Super admins (account_id = 0) bypass all subscription checks and have free access forever."
  end
  
  desc "List all super admin users"
  task list: :environment do
    super_admins = User.where(account_id: 0)
    
    puts "\n=== Super Admin Users ==="
    if super_admins.empty?
      puts "No super admin users found."
    else
      super_admins.each do |user|
        puts "  • #{user.name} (#{user.email})"
        puts "    Created: #{user.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
        puts "    Account ID: #{user.account_id}"
        puts ""
      end
      puts "Total: #{super_admins.count} super admin(s)"
    end
  end
  
  desc "Remove super admin status from a user"
  task :remove, [:email] => :environment do |t, args|
    email = args[:email]
    
    if email.nil?
      puts "Usage: rails super_admins:remove[email@example.com]"
      exit 1
    end
    
    user = User.find_by(email: email)
    
    if user.nil?
      puts "❌ User with email '#{email}' not found."
      exit 1
    end
    
    if user.account_id != 0
      puts "⚠️  User '#{user.name}' (#{email}) is not a super admin (account_id: #{user.account_id})"
      exit 1
    end
    
    # Set to nil so they need to create/join an account
    user.update!(account_id: nil)
    puts "✓ Removed super admin status from '#{user.name}' (#{email})"
    puts "⚠️  Note: User will now need to subscribe to access the app."
  end
  
  desc "Set specific users as super admins (Jackson, Michael, Brandon)"
  task set_founders: :environment do
    # Update these emails with the actual email addresses
    founder_emails = {
      'Jackson' => ENV['JACKSON_EMAIL'] || 'jackson@example.com',
      'Michael' => ENV['MICHAEL_EMAIL'] || 'michael@example.com',
      'Brandon' => ENV['BRANDON_EMAIL'] || 'brandon@example.com'
    }
    
    puts "\n=== Setting Founders as Super Admins ==="
    
    founder_emails.each do |name, email|
      user = User.find_by(email: email)
      
      if user.nil?
        puts "❌ User '#{name}' with email '#{email}' not found."
        puts "   Please create the account first or update the email in this task."
        next
      end
      
      if user.account_id == 0
        puts "✓ #{name} (#{email}) is already a super admin"
      else
        user.update!(account_id: 0)
        puts "✓ Set #{name} (#{email}) as super admin"
      end
    end
    
    puts "\n✅ Founder super admin setup complete!"
  end
  
  desc "Create or set master admin accounts (Jackson, Brandon, Michael)"
  task set_master_admins: :environment do
    master_accounts = {
      'Jackson' => {
        email: 'jbickler4@gmail.com',
        name: 'Jackson Bickler',
        password: ENV['JACKSON_PASSWORD'] || 'TempMasterPass123!'
      },
      'Brandon' => {
        email: 'bwolfe317@gmail.com',
        name: 'Brandon Wolfe',
        password: ENV['BRANDON_PASSWORD'] || 'TempMasterPass123!'
      },
      'Michael' => {
        email: 'modonnell1915@gmail.com',
        name: 'Michael O\'Donnell',
        password: ENV['MICHAEL_PASSWORD'] || 'TempMasterPass123!'
      }
    }
    
    puts "\n=== Setting Up Master Admin Accounts ==="
    
    master_accounts.each do |name, info|
      user = User.find_by(email: info[:email])
      
      if user.nil?
        puts "\n📝 Creating new account for #{name} (#{info[:email]})..."
        
        # Create user with account_id = 0 (super admin)
        user = User.create!(
          name: info[:name],
          email: info[:email],
          password: info[:password],
          password_confirmation: info[:password],
          account_id: 0  # Super admin - bypasses all subscription checks
        )
        
        puts "✓ Created #{name} as super admin"
        puts "  Email: #{info[:email]}"
        puts "  Password: #{info[:password]}"
        puts "  ⚠️  User should change password on first login"
      else
        puts "\n📝 Updating existing account for #{name} (#{info[:email]})..."
        
        if user.account_id == 0
          puts "✓ #{name} is already a super admin"
        else
          old_account_id = user.account_id
          user.update!(account_id: 0)
          puts "✓ Set #{name} as super admin (was account_id: #{old_account_id})"
        end
        
        # Update password if provided via ENV
        if ENV["#{name.upcase}_PASSWORD"].present?
          user.update!(password: ENV["#{name.upcase}_PASSWORD"], password_confirmation: ENV["#{name.upcase}_PASSWORD"])
          puts "  ✓ Password updated"
        end
      end
    end
    
    puts "\n✅ Master admin setup complete!"
    puts "\nAll three accounts have free access forever (account_id = 0)"
    puts "They bypass all subscription checks and can use all features."
  end
  
  desc "Add Cory and Profjwells as super admins"
  task add_new_admins: :environment do
    new_admins = [
      'cory@socialrotation.com',
      'profjwells@gmail.com'
    ]
    
    puts "\n=== Adding New Super Admins ==="
    
    new_admins.each do |email|
      user = User.find_by(email: email)
      
      if user.nil?
        puts "❌ User with email '#{email}' not found. They need to create an account first."
        next
      end
      
      if user.account_id == 0
        puts "✓ User '#{user.name}' (#{email}) is already a super admin"
      else
        old_account_id = user.account_id
        user.update!(account_id: 0)
        puts "✓ Set user '#{user.name}' (#{email}) as super admin (was account_id: #{old_account_id})"
      end
    end
    
    puts "\n✅ New super admin setup complete!"
  end
end
