# OAuth Callback URLs - Corrected

## Analysis of OAuth Controller Code

After checking `app/controllers/api/v1/oauth_controller.rb`, here's what the code actually uses:

### ✅ Facebook - Uses Dynamic URL (No Env Var Needed)
- **Code uses**: `"#{request.base_url}/api/v1/oauth/facebook/callback"`
- **Production URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/facebook/callback`
- **Status**: Automatically correct - no env var needed for callback URL
- **Still need**: `FACEBOOK_APP_ID` and `FACEBOOK_APP_SECRET`

### ❌ LinkedIn - Uses Env Var with Old Fallback
- **Code uses**: `ENV['LINKEDIN_CALLBACK'] || (fallback to old URL)`
- **Fallback**: `https://social-rotation-frontend.onrender.com/linkedin/callback` (WRONG - this is frontend URL!)
- **Correct URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/linkedin/callback`
- **Action**: MUST set `LINKEDIN_CALLBACK` env var

### ❌ Google - Uses Env Var with Old Fallback
- **Code uses**: `ENV['GOOGLE_CALLBACK'] || (fallback to old URL)`
- **Fallback**: `https://social-rotation-frontend.onrender.com/google/callback` (WRONG - this is frontend URL!)
- **Correct URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback`
- **Action**: MUST set `GOOGLE_CALLBACK` env var

### ❌ Twitter - Uses Env Var with Old Fallback
- **Code uses**: `ENV['TWITTER_CALLBACK'] || (fallback to old URL)`
- **Fallback**: `https://social-rotation-frontend.onrender.com/twitter/callback` (WRONG - this is frontend URL!)
- **Correct URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback`
- **Action**: MUST set `TWITTER_CALLBACK` env var

### ❌ TikTok - Uses Env Var with Old Fallback
- **Code uses**: `ENV['TIKTOK_CALLBACK'] || (fallback to old URL)`
- **Fallback**: `https://social-rotation-frontend.onrender.com/tiktok/callback` (WRONG - this is frontend URL!)
- **Correct URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/tiktok/callback`
- **Action**: MUST set `TIKTOK_CALLBACK` env var

### ❌ YouTube - Uses Env Var with Old Fallback
- **Code uses**: `ENV['YOUTUBE_CALLBACK'] || (fallback to old URL)`
- **Fallback**: `https://social-rotation-frontend.onrender.com/youtube/callback` (WRONG - this is frontend URL!)
- **Correct URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback`
- **Action**: MUST set `YOUTUBE_CALLBACK` env var

## CORRECTED Environment Variables

Add these to DigitalOcean App Platform:

```
# LinkedIn
LINKEDIN_CLIENT_ID=86e3q5wfvamuqa
LINKEDIN_CLIENT_SECRET=BP8wbuFAJGCVIYDq
LINKEDIN_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/linkedin/callback

# Google
GOOGLE_CLIENT_ID=1050295806479-d29blhmka53vtmj3dgshp59arp8ic8al.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=wyZs7M4qFFvd1C1TVQGqvY27
GOOGLE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback

# Twitter
TWITTER_API_KEY=5PIs17xez9qVUKft2qYOec6uR
TWITTER_API_SECRET_KEY=wa4aaGQBK3AU75ji1eUBmNfCLO0IhotZD36faf3ZuX91WOnrqz
TWITTER_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback

# Facebook (no callback env var needed - uses dynamic URL)
FACEBOOK_APP_ID=your_facebook_app_id_here
FACEBOOK_APP_SECRET=your_facebook_app_secret_here

# TikTok
TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
TIKTOK_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/tiktok/callback

# YouTube
YOUTUBE_CLIENT_ID=your_youtube_client_id_here
YOUTUBE_CLIENT_SECRET=your_youtube_client_secret_here
YOUTUBE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback
```

## Important Notes

1. **All callback URLs point to BACKEND, not frontend** - The OAuth providers redirect to the backend, which then redirects to the frontend.

2. **Facebook is different** - It uses `request.base_url` dynamically, so it will automatically use the correct backend URL. No callback env var needed.

3. **All others need explicit callback URLs** - Without setting the `*_CALLBACK` env vars, they'll fall back to old/wrong URLs.

4. **Update OAuth App Settings** - After setting these env vars, you MUST also update the redirect URIs in each platform's developer console to match these backend URLs.

