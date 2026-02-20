# Instagram Account Diagnostics
# Helps diagnose why Instagram posting isn't working

namespace :instagram do
  desc "Diagnose Instagram account setup for a user by email"
  task :diagnose, [:email] => :environment do |t, args|
    email = args[:email]
    
    unless email.present?
      puts "Usage: rails instagram:diagnose[user@example.com]"
      exit 1
    end
    
    user = User.find_by(email: email)
    unless user
      puts "❌ User with email '#{email}' not found."
      exit 1
    end
    
    puts "\n" + "=" * 80
    puts "INSTAGRAM ACCOUNT DIAGNOSTICS"
    puts "=" * 80
    puts "User: #{user.name} (#{user.email})"
    puts "User ID: #{user.id}"
    puts "\n"
    
    # Check 1: Facebook connection
    puts "1. FACEBOOK CONNECTION"
    puts "-" * 80
    if user.fb_user_access_key.present?
      puts "✓ Facebook access token is present"
      puts "  Token length: #{user.fb_user_access_key.length} characters"
      puts "  Token preview: #{user.fb_user_access_key[0..20]}..."
    else
      puts "❌ NO Facebook access token found"
      puts "   → User must connect Facebook first"
      puts "\n" + "=" * 80
      exit 1
    end
    
    # Check 2: Instagram Business ID
    puts "\n2. INSTAGRAM BUSINESS ID"
    puts "-" * 80
    if user.instagram_business_id.present?
      puts "✓ Instagram Business ID is stored: #{user.instagram_business_id}"
    else
      puts "❌ NO Instagram Business ID found in database"
      puts "   → Instagram account may not be connected or may not be a business account"
    end
    
    # Check 3: Fetch Facebook Pages
    puts "\n3. FACEBOOK PAGES & INSTAGRAM ACCOUNTS"
    puts "-" * 80
    begin
      url = "https://graph.facebook.com/v18.0/me/accounts"
      params = {
        access_token: user.fb_user_access_key,
        fields: 'id,name,access_token,category,instagram_business_account{id,username,name,profile_picture_url}',
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      
      unless response.success?
        error_data = JSON.parse(response.body) rescue {}
        error_msg = error_data.dig('error', 'message') || 'Unknown error'
        error_code = error_data.dig('error', 'code')
        puts "❌ Failed to fetch Facebook pages"
        puts "   Error: #{error_msg} (Code: #{error_code})"
        puts "\n" + "=" * 80
        exit 1
      end
      
      data = JSON.parse(response.body)
      pages = data['data'] || []
      
      if pages.empty?
        puts "❌ NO Facebook Pages found"
        puts "   → User needs to create a Facebook Page or grant page access"
        puts "\n" + "=" * 80
        exit 1
      end
      
      puts "✓ Found #{pages.count} Facebook Page(s):"
      puts ""
      
      instagram_found = false
      pages.each_with_index do |page, index|
        puts "  Page #{index + 1}:"
        puts "    ID: #{page['id']}"
        puts "    Name: #{page['name']}"
        puts "    Category: #{page['category'] || 'N/A'}"
        
        if page['instagram_business_account']
          instagram_account = page['instagram_business_account']
          instagram_found = true
          puts "    ✓ HAS Instagram Business Account:"
          puts "      Instagram ID: #{instagram_account['id']}"
          puts "      Username: #{instagram_account['username'] || 'N/A'}"
          puts "      Name: #{instagram_account['name'] || 'N/A'}"
          
          # Check if this matches the stored Instagram ID
          if user.instagram_business_id == instagram_account['id']
            puts "      ✓ This matches the stored Instagram Business ID"
          elsif user.instagram_business_id.present?
            puts "      ⚠️  WARNING: This doesn't match stored ID (#{user.instagram_business_id})"
          end
        else
          puts "    ❌ NO Instagram Business Account linked"
        end
        puts ""
      end
      
      unless instagram_found
        puts "❌ NO Instagram Business Accounts found on any Facebook Pages"
        puts "   → Instagram account must be:"
        puts "     1. A Business or Creator account (not Personal)"
        puts "     2. Linked to a Facebook Page"
        puts "\n" + "=" * 80
        exit 1
      end
      
    rescue => e
      puts "❌ Error fetching Facebook pages: #{e.message}"
      puts "   #{e.backtrace.first}"
      puts "\n" + "=" * 80
      exit 1
    end
    
    # Check 4: Test Instagram API access
    puts "4. INSTAGRAM API ACCESS TEST"
    puts "-" * 80
    
    unless user.instagram_business_id.present?
      puts "⚠️  Skipping API test - no Instagram Business ID stored"
      puts "\n" + "=" * 80
      exit 1
    end
    
    begin
      # Find the page token for this Instagram account
      page_token = nil
      page_id = nil
      
      pages.each do |page|
        if page['instagram_business_account'] && page['instagram_business_account']['id'] == user.instagram_business_id
          page_token = page['access_token']
          page_id = page['id']
          break
        end
      end
      
      unless page_token
        puts "❌ Could not find page access token for Instagram account"
        puts "   → Instagram account may not be properly linked to a page"
        puts "\n" + "=" * 80
        exit 1
      end
      
      puts "✓ Found page access token"
      puts "  Page ID: #{page_id}"
      puts "  Token length: #{page_token.length} characters"
      
      # Try to get Instagram account details
      instagram_url = "https://graph.facebook.com/v18.0/#{user.instagram_business_id}"
      instagram_params = {
        access_token: page_token,
        fields: 'id,username,name,profile_picture_url,account_type'
      }
      
      puts "\n  Testing Instagram API access..."
      instagram_response = HTTParty.get(instagram_url, query: instagram_params)
      
      if instagram_response.success?
        instagram_data = JSON.parse(instagram_response.body)
        puts "✓ Instagram API access successful!"
        puts "  Username: #{instagram_data['username'] || 'N/A'}"
        puts "  Name: #{instagram_data['name'] || 'N/A'}"
        puts "  Account Type: #{instagram_data['account_type'] || 'N/A (should be BUSINESS or CREATOR)'}"
        
        if instagram_data['account_type']
          account_type = instagram_data['account_type'].upcase
          if ['BUSINESS', 'CREATOR'].include?(account_type)
            puts "  ✓ Account type is valid for posting (#{account_type})"
          else
            puts "  ❌ Account type is NOT valid: #{account_type}"
            puts "     → Must be BUSINESS or CREATOR, not PERSONAL"
          end
        else
          puts "  ⚠️  Account type not returned (may still work, but verify in Instagram app)"
        end
      else
        error_data = JSON.parse(instagram_response.body) rescue {}
        error_msg = error_data.dig('error', 'message') || 'Unknown error'
        error_code = error_data.dig('error', 'code')
        error_type = error_data.dig('error', 'type')
        
        puts "❌ Instagram API access FAILED"
        puts "   Error: #{error_msg}"
        puts "   Code: #{error_code}"
        puts "   Type: #{error_type}"
        
        if error_code == 10 || error_msg.include?('business account') || error_msg.include?('not a business account')
          puts "\n   → This account is NOT a Business or Creator account"
          puts "   → Convert to Business/Creator account in Instagram app:"
          puts "      Settings → Account → Switch to Professional Account"
        elsif error_code == 190 || error_msg.include?('Invalid OAuth')
          puts "\n   → Access token is invalid or expired"
          puts "   → User needs to reconnect Facebook/Instagram"
        end
      end
      
    rescue => e
      puts "❌ Error testing Instagram API: #{e.message}"
      puts "   #{e.backtrace.first}"
    end
    
    # Check 5: Test media creation (dry run)
    puts "\n5. POSTING CAPABILITY TEST"
    puts "-" * 80
    
    begin
      # Try to create a test media container (we'll delete it immediately)
      test_url = "https://graph.facebook.com/v18.0/#{user.instagram_business_id}/media"
      test_params = {
        access_token: page_token,
        image_url: 'https://via.placeholder.com/1080x1080.jpg', # Placeholder image
        caption: 'Test - This will be deleted'
      }
      
      puts "  Testing media creation endpoint..."
      test_response = HTTParty.post(test_url, body: test_params)
      test_data = JSON.parse(test_response.body)
      
      if test_response.success? && test_data['id']
        puts "✓ Media creation endpoint works!"
        puts "  Test container ID: #{test_data['id']}"
        puts "  → Account CAN create posts via API"
        
        # Try to delete the test container (if possible)
        begin
          delete_url = "https://graph.facebook.com/v18.0/#{test_data['id']}"
          HTTParty.delete(delete_url, query: { access_token: page_token })
        rescue
          # Ignore deletion errors
        end
      else
        error_msg = test_data.dig('error', 'message') || 'Unknown error'
        error_code = test_data.dig('error', 'code')
        
        puts "❌ Media creation FAILED"
        puts "   Error: #{error_msg}"
        puts "   Code: #{error_code}"
        
        if error_code == 10 || error_msg.include?('business account')
          puts "\n   → Account is NOT a Business/Creator account"
        elsif error_msg.include?('permission')
          puts "\n   → Missing required permissions"
          puts "   → Check Facebook App permissions in Meta for Developers"
        end
      end
      
    rescue => e
      puts "❌ Error testing posting capability: #{e.message}"
    end
    
    # Summary
    puts "\n" + "=" * 80
    puts "SUMMARY"
    puts "=" * 80
    
    if user.instagram_business_id.present? && instagram_found
      puts "✓ Instagram Business ID is stored"
      puts "✓ Instagram account found on Facebook Page"
      puts "\nIf posting still fails, check:"
      puts "  1. Account type in Instagram app (must be Business/Creator)"
      puts "  2. Facebook App permissions in Meta for Developers"
      puts "  3. Access token expiration (may need to reconnect)"
      puts "  4. Error logs when attempting to post"
    else
      puts "❌ Instagram account is not properly set up"
      puts "\nRequired steps:"
      puts "  1. Convert Instagram to Business/Creator account"
      puts "  2. Link Instagram to a Facebook Page"
      puts "  3. Reconnect Instagram in the app"
    end
    
    puts "\n" + "=" * 80
  end
end

