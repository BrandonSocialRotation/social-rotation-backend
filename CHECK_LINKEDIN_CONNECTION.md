# How to Check if LinkedIn Account is Saved

## Method 1: Via Browser Console (Easiest)

1. Open your browser's Developer Tools (F12)
2. Go to the Console tab
3. Run this command:

```javascript
fetch('https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/user_info', {
  headers: {
    'Authorization': `Bearer ${localStorage.getItem('token') || sessionStorage.getItem('token')}`
  }
}).then(r => r.json()).then(data => {
  console.log('LinkedIn Status:', {
    connected: data.user.linkedin_connected,
    hasToken: !!data.user.linkedin_access_token,
    tokenTime: data.user.linkedin_access_token_time,
    profileId: data.user.linkedin_profile_id
  });
});
```

## Method 2: Via Rails Console (Backend)

SSH into your DigitalOcean backend and run:

```bash
# Connect to Rails console
bundle exec rails console

# Then run:
user = User.find_by(email: 'your-email@example.com')
puts "LinkedIn Access Token: #{user.linkedin_access_token.present? ? 'SAVED' : 'NOT SAVED'}"
puts "Token Saved At: #{user.linkedin_access_token_time}"
puts "Profile ID: #{user.linkedin_profile_id}"
puts "Token (first 20 chars): #{user.linkedin_access_token&.first(20)}..." if user.linkedin_access_token
```

## Method 3: Check the API Response Directly

Visit this URL in your browser (you'll need to be logged in):
```
https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/user_info
```

Look for:
- `"linkedin_connected": true` in the user object
- The presence of `linkedin_access_token` (though the token itself won't be shown for security)

## What to Look For

✅ **Success indicators:**
- `linkedin_connected: true` in the API response
- Button shows "Change LinkedIn Account" instead of "Connect LinkedIn"
- Status shows "Connected" in green

❌ **If not saved:**
- `linkedin_connected: false`
- Button still shows "Connect LinkedIn"
- No `linkedin_access_token` in database

## Testing Posting

Once confirmed, you can test posting by:
1. Going to the Schedule page
2. Creating a scheduled post
3. Selecting LinkedIn as one of the platforms
4. The system will use the stored `linkedin_access_token` to post

