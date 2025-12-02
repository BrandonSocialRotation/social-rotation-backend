# Complete Google Cloud Setup Guide
## For Google My Business + YouTube

This guide will walk you through creating a new Google Cloud project and setting it up for both Google My Business and YouTube OAuth.

---

## Step 1: Create a New Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the **project dropdown** at the top (next to "Google Cloud")
3. Click **"New Project"**
4. Enter project details:
   - **Project name**: "Social Rotation" (or any name you prefer)
   - **Location**: No organization (or select your organization if you have one)
5. Click **"Create"**
6. Wait for the project to be created, then **select it** from the project dropdown

---

## Step 2: Enable Required APIs

You need to enable APIs for both Google My Business and YouTube.

### Enable Google My Business API

1. Go to **"APIs & Services"** → **"Library"** (in the left sidebar)
2. Search for **"My Business API"** or **"Google My Business API"**
3. If you find it, click on it and click **"Enable"**
4. **Note**: Google My Business API might not be available in the library. If you can't find it:
   - The API might be called **"Business Profile Performance API"** or **"My Business Account Management API"**
   - Try searching for those instead
   - If still not found, you can proceed - the OAuth scope will still work, but posting might require additional setup

### Enable YouTube Data API v3

1. Still in **"APIs & Services"** → **"Library"**
2. Search for **"YouTube Data API v3"**
3. Click on it and click **"Enable"**
4. This is required for YouTube OAuth and posting

---

## Step 3: Configure OAuth Consent Screen

1. Go to **"APIs & Services"** → **"OAuth consent screen"** (in the left sidebar)
2. Select **"External"** (unless you have a Google Workspace account)
3. Click **"Create"**

### Fill in App Information:

- **App name**: `Social Rotation`
- **User support email**: Your email address
- **App logo**: (Optional - you can skip this)
- **Application home page**: `https://my.socialrotation.app`
- **Application privacy policy link**: `https://my.socialrotation.app/privacy-policy`
- **Application terms of service link**: `https://my.socialrotation.app/terms-of-service`
- **Authorized domains**: `socialrotation.app` (add this if you have the domain)
- **Developer contact information**: Your email address

4. Click **"Save and Continue"**

### Add Scopes:

1. Click **"Add or Remove Scopes"**
2. Click **"Filter"** and select **"Manually add scopes"**
3. Add these scopes one by one:

   **For Google My Business:**
   ```
   https://www.googleapis.com/auth/business.manage
   ```

   **For YouTube:**
   ```
   https://www.googleapis.com/auth/youtube.upload
   https://www.googleapis.com/auth/youtube
   https://www.googleapis.com/auth/youtubepartner
   ```

4. Click **"Add to Table"** for each scope
5. Click **"Update"** at the bottom
6. Click **"Save and Continue"**

### Add Test Users (if in Testing mode):

1. Add your email address: `jbickler4@gmail.com`
2. Click **"Add Users"**
3. Click **"Save and Continue"**
4. Review the summary and click **"Back to Dashboard"**

**Note**: If your app is in "Testing" mode, only test users can sign in. To make it public, you'll need to submit for verification (can take several days).

---

## Step 4: Create OAuth 2.0 Credentials

1. Go to **"APIs & Services"** → **"Credentials"** (in the left sidebar)
2. Click **"+ CREATE CREDENTIALS"** at the top
3. Select **"OAuth client ID"**

### Configure OAuth Client:

- **Application type**: Select **"Web application"**
- **Name**: `Social Rotation Web Client`

### Authorized JavaScript origins:

Add these (one per line):
```
https://my.socialrotation.app
https://new-social-rotation-backend-qzyk8.ondigitalocean.app
```

### Authorized redirect URIs:

Add these (one per line):
```
https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback
https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback
```

**For local development** (optional):
```
http://localhost:3000/api/v1/oauth/google/callback
http://localhost:3000/api/v1/oauth/youtube/callback
```

4. Click **"Create"**

### Copy Your Credentials:

A popup will appear with your credentials:
- **Client ID**: Copy this (looks like `123456789-abc...googleusercontent.com`)
- **Client Secret**: Click **"Show"** and copy this (looks like `GOCSPX-...`)

**Important**: Save these somewhere safe - you'll need them for DigitalOcean!

---

## Step 5: Add Credentials to DigitalOcean

1. Go to your DigitalOcean App Platform dashboard
2. Select your **backend app** (the Rails app)
3. Go to **"Settings"** → **"App-Level Environment Variables"**
4. Add the following environment variables:

### For Google My Business:

```
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here
GOOGLE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback
```

### For YouTube:

```
YOUTUBE_CLIENT_ID=your_client_id_here (same as GOOGLE_CLIENT_ID)
YOUTUBE_CLIENT_SECRET=your_client_secret_here (same as GOOGLE_CLIENT_SECRET)
YOUTUBE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback
```

**Note**: You can use the **same Client ID and Secret** for both Google My Business and YouTube - they're from the same OAuth client!

5. Click **"Save"**
6. DigitalOcean will automatically redeploy your app

---

## Step 6: Test the Connection

Wait a few minutes for DigitalOcean to redeploy, then:

### Test Google My Business:

1. Go to your app: `https://my.socialrotation.app`
2. Log in
3. Go to **Profile** → **Social Media Connections**
4. Click **"Connect Google My Business"**
5. You should be redirected to Google to authorize
6. After authorization, you'll be redirected back

### Test YouTube:

1. Still in **Profile** → **Social Media Connections**
2. Click **"Connect YouTube"**
3. You should be redirected to Google to authorize
4. After authorization, you'll be redirected back

---

## Troubleshooting

### "redirect_uri_mismatch" Error

- Make sure the redirect URIs in Google Cloud Console **exactly match** what's in DigitalOcean
- No trailing slashes!
- Check that you're using `https://` (not `http://`)

### "Access blocked" or "Invalid request"

- Make sure your app is in "Testing" mode and you've added your email as a test user
- Or submit your app for verification to make it public

### "API not enabled" Error

- Go back to **"APIs & Services"** → **"Library"**
- Make sure **YouTube Data API v3** is enabled
- For Google My Business, the API might not be in the library - that's OK, the OAuth scope should still work

### Can't find "Google My Business API" in Library

- This is common - Google has been transitioning this API
- The OAuth scope `https://www.googleapis.com/auth/business.manage` should still work
- You might need to enable it through a different method or it might be automatically available
- Try the connection anyway - if it fails, we can troubleshoot

---

## Next Steps After Connection

### Google My Business:

After connecting, you'll need to:
1. Fetch the user's Google My Business locations
2. Let the user select which location to post to
3. Store the `location_id` on the user record

### YouTube:

After connecting, you should be able to:
1. Post videos to the user's YouTube channel
2. The refresh token will be stored automatically

---

## Summary Checklist

- [ ] Created new Google Cloud project
- [ ] Enabled YouTube Data API v3
- [ ] Configured OAuth consent screen with all required scopes
- [ ] Added test user (your email)
- [ ] Created OAuth 2.0 Client ID
- [ ] Added all redirect URIs to OAuth client
- [ ] Copied Client ID and Secret
- [ ] Added all environment variables to DigitalOcean
- [ ] Waited for DigitalOcean to redeploy
- [ ] Tested Google My Business connection
- [ ] Tested YouTube connection

---

## Quick Reference: Environment Variables for DigitalOcean

```
GOOGLE_CLIENT_ID=123456789-abc...googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-...
GOOGLE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback

YOUTUBE_CLIENT_ID=123456789-abc...googleusercontent.com (same as GOOGLE_CLIENT_ID)
YOUTUBE_CLIENT_SECRET=GOCSPX-... (same as GOOGLE_CLIENT_SECRET)
YOUTUBE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/youtube/callback
```

**Remember**: Use the **same Client ID and Secret** for both Google My Business and YouTube!

