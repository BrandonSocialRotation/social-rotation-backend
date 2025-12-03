# Check Account Info in Database

Run this in Rails console (DigitalOcean console):

```ruby
# Find your user
user = User.find_by(email: 'jbickler4@gmail.com')

# Check what's stored
{
  facebook: {
    access_token: user.fb_user_access_key.present? ? 'present' : 'nil',
    name: user.respond_to?(:facebook_name) ? user.facebook_name : 'column_not_exists'
  },
  google: {
    refresh_token: user.google_refresh_token.present? ? 'present' : 'nil',
    account_name: user.respond_to?(:google_account_name) ? user.google_account_name : 'column_not_exists'
  },
  pinterest: {
    access_token: user.respond_to?(:pinterest_access_token) ? (user.pinterest_access_token.present? ? 'present' : 'nil') : 'column_not_exists',
    username: user.respond_to?(:pinterest_username) ? user.pinterest_username : 'column_not_exists'
  },
  twitter: {
    token: user.twitter_oauth_token.present? ? 'present' : 'nil',
    screen_name: user.twitter_screen_name
  },
  linkedin: {
    token: user.linkedin_access_token.present? ? 'present' : 'nil',
    profile_id: user.linkedin_profile_id
  }
}
```

## Quick Check Commands:

```ruby
# Check if columns exist
User.column_names.grep(/facebook|google|pinterest/)

# Check your user's data
u = User.find_by(email: 'jbickler4@gmail.com')
puts "Facebook name: #{u.try(:facebook_name) || 'nil'}"
puts "Google name: #{u.try(:google_account_name) || 'nil'}"
puts "Pinterest username: #{u.try(:pinterest_username) || 'nil'}"
```

