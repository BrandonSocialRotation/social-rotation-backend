# Quick script to check LinkedIn connection status
# Run with: bundle exec rails runner check_linkedin.rb

user = User.find_by(email: ENV['CHECK_EMAIL'] || 'jbickler4@gmail.com')

if user
  puts "\n=== LinkedIn Connection Status for #{user.email} ==="
  puts "LinkedIn Access Token: #{user.linkedin_access_token.present? ? '✅ SAVED' : '❌ NOT SAVED'}"
  puts "Token Saved At: #{user.linkedin_access_token_time || 'Never'}"
  puts "Profile ID: #{user.linkedin_profile_id || 'Not fetched yet'}"
  puts "Token Preview: #{user.linkedin_access_token&.first(30)}..." if user.linkedin_access_token
  puts "\n✅ LinkedIn is connected and ready for posting!" if user.linkedin_access_token.present?
else
  puts "User not found"
end
