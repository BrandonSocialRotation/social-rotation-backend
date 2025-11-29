# 🐦 Twitter OAuth Setup Guide

Complete step-by-step guide to set up Twitter (X) OAuth for Social Rotation.

## 📋 Prerequisites

- A Twitter/X account
- Access to Twitter Developer Portal
- Your backend URL: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app`
- Your frontend URL: `https://my.socialrotation.app`

---

## Step 1: Create Twitter Developer Account

1. Go to **https://developer.twitter.com/**
2. Click **"Sign up"** or **"Sign in"** with your Twitter account
3. If signing up:
   - Fill out the developer application form
   - Explain your use case: "Social media management tool for scheduling and posting content"
   - Accept the terms and conditions
   - Verify your email address

---

## Step 2: Create a Twitter App

1. Once logged in, go to **https://developer.twitter.com/en/portal/dashboard**
2. Click **"Create Project"** (if you don't have one)
   - Project name: **"Social Rotation"**
   - Use case: Select **"Making a bot"** or **"Exploring the API"**
   - Project description: "Social media management platform for scheduling posts"
   - Click **"Next"**
   - Accept terms and click **"Create Project"**

3. Click **"Create App"** (within your project)
   - App name: **"Social Rotation"** (or any unique name)
   - App environment: Select **"Development"** (you can upgrade later)
   - Click **"Create App"**

---

## Step 3: Get API Keys and Secrets

1. In your app dashboard, go to **"Keys and tokens"** tab
2. You'll see:
   - **API Key** (also called Consumer Key)
   - **API Key Secret** (also called Consumer Secret)
3. **IMPORTANT**: Click **"Generate"** or **"Regenerate"** for:
   - **Access Token and Secret** (if not already generated)
   - **Bearer Token** (optional, not needed for OAuth 1.0a)

4. **Copy these values** (you won't be able to see them again):
   - ✅ **API Key** → This is your `TWITTER_API_KEY`
   - ✅ **API Key Secret** → This is your `TWITTER_API_SECRET_KEY`

⚠️ **Security Note**: Keep these secrets safe! Never commit them to git.

---

## Step 4: Configure OAuth Settings

1. In your app dashboard, go to **"Settings"** tab
2. Scroll down to **"User authentication settings"**
3. Click **"Set up"** or **"Edit"**

4. Configure OAuth settings:
   - **App permissions**: Select **"Read and write"** (needed for posting)
   - **Type of App**: Select **"Web App, Automated App or Bot"**
   - **App info**:
     - **Callback URI / Redirect URL**: 
       ```
       https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback
       ```
     - **Website URL**: 
       ```
       https://my.socialrotation.app
       ```
   - **Terms of Service URL**: (optional, can use your website)
   - **Privacy Policy URL**: (optional, can use your website)

5. Click **"Save"**

---

## Step 5: Enable Required Permissions

1. Go to **"User authentication settings"** (if not already there)
2. Under **"App permissions"**, make sure you have:
   - ✅ **Read and write** (required for posting tweets with images)

3. If you need to request elevated access:
   - Go to **"Settings"** → **"User authentication settings"**
   - Click **"Request elevated access"** if available
   - Fill out the form explaining your use case
   - Wait for approval (can take a few days)

---

## Step 6: Add Environment Variables to DigitalOcean

1. Go to your DigitalOcean App Platform dashboard
2. Navigate to your backend app: **"Rebrand-Social-rotation"**
3. Go to **"Settings"** → **"App-Level Environment Variables"**
4. Click **"Edit"** or **"Add Variable"**

5. Add these environment variables:

   ```
   TWITTER_API_KEY=your_api_key_here
   TWITTER_API_SECRET_KEY=your_api_secret_here
   TWITTER_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback
   ```

   Replace `your_api_key_here` and `your_api_secret_here` with the actual values from Step 3.

6. Click **"Save"**

---

## Step 7: Verify Your Setup

### Test OAuth Connection:

1. Go to your app: **https://my.socialrotation.app**
2. Log in and go to **Profile** page
3. Click **"Connect X"** (Twitter/X button)
4. A popup should open with Twitter OAuth
5. Authorize the app
6. You should be redirected back with a success message
7. The button should change to **"Change X Account"**

### Test Posting:

1. Create a bucket with an image
2. Schedule a post or use "Post Now"
3. Select **Twitter/X** as one of the platforms
4. The post should appear on your Twitter account

---

## 🔧 Troubleshooting

### Issue: "Twitter authentication failed"
- **Check**: API Key and Secret are correct in DigitalOcean environment variables
- **Check**: OAuth callback URL matches exactly in Twitter app settings
- **Check**: App permissions are set to "Read and write"

### Issue: "Failed to upload media to Twitter"
- **Check**: User has connected their Twitter account (OAuth tokens are stored)
- **Check**: App has "Read and write" permissions
- **Check**: Image file size is under Twitter's limits (5MB for images)

### Issue: "OAuth callback not working"
- **Check**: Callback URL in Twitter app settings matches exactly:
  ```
  https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback
  ```
- **Check**: No trailing slashes or extra characters
- **Check**: Using HTTPS (not HTTP) in production

### Issue: "Insufficient permissions"
- **Solution**: Request elevated access in Twitter Developer Portal
- **Solution**: Make sure app permissions are set to "Read and write"

---

## 📝 Environment Variables Summary

Add these to your DigitalOcean App Platform:

```bash
# Twitter OAuth Credentials
TWITTER_API_KEY=your_api_key_from_twitter
TWITTER_API_SECRET_KEY=your_api_secret_from_twitter
TWITTER_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/twitter/callback
```

---

## 🔒 Security Best Practices

1. ✅ Never commit API keys to git
2. ✅ Use environment variables for all secrets
3. ✅ Rotate keys if they're ever exposed
4. ✅ Use different keys for development and production
5. ✅ Regularly review app permissions in Twitter Developer Portal

---

## 📚 Additional Resources

- [Twitter Developer Portal](https://developer.twitter.com/)
- [Twitter API v2 Documentation](https://developer.twitter.com/en/docs/twitter-api)
- [OAuth 1.0a Guide](https://developer.twitter.com/en/docs/authentication/oauth-1-0a)
- [Twitter Media Upload Guide](https://developer.twitter.com/en/docs/twitter-api/v1/media/upload-media)

---

## ✅ Checklist

- [ ] Created Twitter Developer account
- [ ] Created Twitter app
- [ ] Copied API Key and Secret
- [ ] Configured OAuth callback URL in Twitter app
- [ ] Set app permissions to "Read and write"
- [ ] Added environment variables to DigitalOcean
- [ ] Tested OAuth connection
- [ ] Tested posting to Twitter

---

**Need Help?** Check the backend logs in DigitalOcean for detailed error messages.

