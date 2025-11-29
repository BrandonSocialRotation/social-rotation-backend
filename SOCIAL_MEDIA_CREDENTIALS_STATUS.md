# Social Media Credentials Status

## Summary of Found Credentials

### ✅ LinkedIn - CONFIGURED
- **Client ID**: `86e3q5wfvamuqa`
- **Client Secret**: `BP8wbuFAJGCVIYDq`
- **Status**: Credentials found in DEPLOYMENT_CHECKLIST.md
- **Callback URL**: Needs to be set to `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/linkedin/callback`
- **Required Permissions**: 
  - `w_member_social` (Share on LinkedIn)
  - `r_liteprofile` (Basic profile)
  - `r_emailaddress` (Email address)

### ✅ Google - CONFIGURED
- **Client ID**: `1050295806479-d29blhmka53vtmj3dgshp59arp8ic8al.apps.googleusercontent.com`
- **Client Secret**: `wyZs7M4qFFvd1C1TVQGqvY27`
- **Status**: Credentials found in DEPLOYMENT_CHECKLIST.md
- **Callback URL**: Needs to be set to `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback`
- **Required Scopes**:
  - `https://www.googleapis.com/auth/business.manage` (Google My Business)
  - `https://www.googleapis.com/auth/youtube.upload` (YouTube - if using separate YouTube OAuth)
  - `https://www.googleapis.com/auth/youtube` (YouTube read/write)

### ⚠️ Twitter - PARTIALLY CONFIGURED
- **API Key** (Consumer Key): `5PIs17xez9qVUKft2qYOec6uR` (hardcoded fallback)
- **API Secret** (Consumer Secret): `wa4aaGQBK3AU75ji1eUBmNfCLO0IhotZD36faf3ZuX91WOnrqz` (hardcoded fallback)
- **Status**: Hardcoded in oauth_controller.rb as fallback values
- **Action Needed**: 
  - Verify these credentials are valid
  - Set as environment variables: `TWITTER_API_KEY` and `TWITTER_API_SECRET_KEY`
  - Update callback URL in Twitter app settings
- **Required Permissions**:
  - `tweet.read` (Read tweets)
  - `tweet.write` (Post tweets)
  - `users.read` (Read user profile)
  - `offline.access` (Refresh token)
- **Note**: Twitter posting service is not fully implemented (needs OAuth 1.0a signing)

### ❌ Facebook - NOT CONFIGURED
- **App ID**: Not found
- **App Secret**: Not found
- **Status**: Missing - needs to be set up
- **Required Environment Variables**:
  - `FACEBOOK_APP_ID`
  - `FACEBOOK_APP_SECRET`
- **Required Permissions**:
  - `pages_manage_posts` (Post to Facebook pages)
  - `pages_read_engagement` (Read page insights)
  - `instagram_basic` (Access Instagram basic info)
  - `instagram_content_publish` (Publish to Instagram)
  - `publish_video` (Publish videos)
- **Callback URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/facebook/callback`

### ❌ Instagram - NOT CONFIGURED (Uses Facebook)
- **Status**: Uses Facebook OAuth credentials
- **Requirements**: 
  - Facebook App must be connected to Instagram Business Account
  - User must have `instagram_business_id` stored in database
  - Requires Facebook page access token with Instagram permissions

### ❌ TikTok - NOT CONFIGURED
- **Client Key**: Not found
- **Client Secret**: Not found
- **Status**: Missing - needs to be set up
- **Required Environment Variables**:
  - `TIKTOK_CLIENT_KEY`
  - `TIKTOK_CLIENT_SECRET`
- **Callback URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/tiktok/callback`
- **Required Scopes**:
  - `user.info.basic` (Basic user info)
  - `video.upload` (Upload videos)
  - `video.publish` (Publish videos)

### ❌ YouTube - NOT CONFIGURED
- **Client ID**: Not found (separate from Google My Business)
- **Client Secret**: Not found
- **Status**: Missing - needs to be set up
- **Required Environment Variables**:
  - `YOUTUBE_CLIENT_ID`
  - `YOUTUBE_CLIENT_SECRET`
- **Callback URL**: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback`
- **Required Scopes**:
  - `https://www.googleapis.com/auth/youtube.upload` (Upload videos)
  - `https://www.googleapis.com/auth/youtube` (Full YouTube access)

## Current Environment Variables in Production

Based on your earlier message, you have these set:
```
DIGITAL_OCEAN_SPACES_KEY = SAGDZELGX2GCZDRXZWWU
DIGITAL_OCEAN_SPACES_SECRET = nYlc9IKq7eEp4vKYXPwTy4GKlL8rRxEsI47b63HX3M4
DIGITAL_OCEAN_SPACES_NAME = se1
DIGITAL_OCEAN_SPACES_REGION = sfo2
DIGITAL_OCEAN_SPACES_ENDPOINT = https://sfo2.digitaloceanspaces.com
FRONTEND_URL = https://social-rotation-frontend-f4mwb.ondigitalocean.app
RAILS_ENV = production
DATABASE_URL = postgresql://dev-db-045706:AVNS_E0jlkRdP0Xw4fK4H8Hf@...
JWT_SECRET_KEY = 847fc25a54ac41c893fccb0ff1ca8dd1f56a289dcce78eeb0a18ca8cf8710712
RAILS_MASTER_KEY = bde311022ba14c8486488df1462a8cbc
```

## Missing Environment Variables to Add

Add these to DigitalOcean App Platform environment variables:

```
# LinkedIn (already have credentials)
LINKEDIN_CLIENT_ID=86e3q5wfvamuqa
LINKEDIN_CLIENT_SECRET=BP8wbuFAJGCVIYDq
LINKEDIN_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/linkedin/callback

# Google (already have credentials)
GOOGLE_CLIENT_ID=1050295806479-d29blhmka53vtmj3dgshp59arp8ic8al.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=wyZs7M4qFFvd1C1TVQGqvY27
GOOGLE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback

# Twitter (verify hardcoded values work)
TWITTER_API_KEY=5PIs17xez9qVUKft2qYOec6uR
TWITTER_API_SECRET_KEY=wa4aaGQBK3AU75ji1eUBmNfCLO0IhotZD36faf3ZuX91WOnrqz
TWITTER_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback

# Facebook (NEED TO CREATE)
FACEBOOK_APP_ID=your_facebook_app_id_here
FACEBOOK_APP_SECRET=your_facebook_app_secret_here

# TikTok (NEED TO CREATE)
TIKTOK_CLIENT_KEY=your_tiktok_client_key_here
TIKTOK_CLIENT_SECRET=your_tiktok_client_secret_here
TIKTOK_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/tiktok/callback

# YouTube (NEED TO CREATE - or reuse Google if same project)
YOUTUBE_CLIENT_ID=your_youtube_client_id_here
YOUTUBE_CLIENT_SECRET=your_youtube_client_secret_here
YOUTUBE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback
```

## Next Steps

1. **Verify LinkedIn & Google credentials work**
   - Test OAuth flow in production
   - Update callback URLs in respective developer consoles

2. **Set up Facebook/Instagram**
   - Create Facebook App at https://developers.facebook.com/apps
   - Request required permissions
   - Get App ID and App Secret
   - Connect Instagram Business Account

3. **Verify/Update Twitter credentials**
   - Test if hardcoded credentials are valid
   - Update Twitter app callback URLs
   - Complete Twitter posting implementation (OAuth 1.0a)

4. **Set up TikTok**
   - Create TikTok app at https://developers.tiktok.com/
   - Get Client Key and Secret
   - Configure callback URL

5. **Set up YouTube** (if separate from Google)
   - Create OAuth client in Google Cloud Console
   - Enable YouTube Data API v3
   - Get Client ID and Secret

## Testing Checklist

For each platform, test:
- [ ] OAuth login flow works
- [ ] Access token is saved to database
- [ ] Posting functionality works
- [ ] Error handling for expired tokens
- [ ] Token refresh (where applicable)

