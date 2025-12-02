# Google My Business OAuth Setup Guide

This guide will walk you through setting up Google My Business API credentials for Social Rotation.

## Prerequisites
- A Google account
- Access to Google Cloud Console
- A Google My Business account

## Step 1: Create a Project in Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top
3. Click **"New Project"**
4. Enter a project name (e.g., "Social Rotation")
5. Click **"Create"**

## Step 2: Enable Google My Business API

1. In your project, go to **"APIs & Services"** > **"Library"**
2. Search for **"Google My Business API"**
3. Click on it and click **"Enable"**
4. Also search for and enable **"Google My Business Account Management API"** (if available)

## Step 3: Create OAuth 2.0 Credentials

1. Go to **"APIs & Services"** > **"Credentials"**
2. Click **"+ CREATE CREDENTIALS"** at the top
3. Select **"OAuth client ID"**
4. If prompted, configure the OAuth consent screen first:
   - **User Type**: Select **"External"** (unless you have a Google Workspace)
   - Click **"Create"**
   - **App name**: "Social Rotation"
   - **User support email**: Your email
   - **Developer contact information**: Your email
   - Click **"Save and Continue"**
   - **Scopes**: Click **"Add or Remove Scopes"**
     - Search for and add: `https://www.googleapis.com/auth/business.manage`
     - Click **"Update"** then **"Save and Continue"**
   - **Test users**: Add your own email address (for testing)
   - Click **"Save and Continue"** then **"Back to Dashboard"**

5. Now create the OAuth client:
   - **Application type**: Select **"Web application"**
   - **Name**: "Social Rotation Web Client"
   - **Authorized JavaScript origins**: 
     - Add: `https://my.socialrotation.app`
     - Add: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app` (your backend URL)
   - **Authorized redirect URIs**:
     - Add: `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback`
     - For local development: `http://localhost:3000/api/v1/oauth/google/callback`
   - Click **"Create"**

6. **Copy your credentials**:
   - **Client ID**: Copy this (starts with something like `123456789-abc...googleusercontent.com`)
   - **Client Secret**: Click **"Show"** and copy this (starts with `GOCSPX-...`)

## Step 4: Add Credentials to DigitalOcean

1. Go to your DigitalOcean App Platform dashboard
2. Select your backend app
3. Go to **"Settings"** > **"App-Level Environment Variables"**
4. Add the following environment variables:

   ```
   GOOGLE_CLIENT_ID=your_client_id_here
   GOOGLE_CLIENT_SECRET=your_client_secret_here
   GOOGLE_CALLBACK=https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback
   ```

5. Click **"Save"**

## Step 5: Request API Access (Important!)

Google My Business API requires approval for production use:

1. Go to **"APIs & Services"** > **"OAuth consent screen"**
2. If your app is in "Testing" mode, you'll need to:
   - Add test users (your email)
   - Or submit for verification to make it public
3. For production use, you may need to:
   - Complete the OAuth consent screen verification
   - Submit your app for review by Google
   - This process can take several days

## Step 6: Test the Connection

1. After deploying with the new environment variables:
2. Go to your Social Rotation app
3. Navigate to **Profile** > **Social Media Connections**
4. Click **"Connect Google My Business"**
5. You should be redirected to Google to authorize
6. After authorization, you'll be redirected back and the connection should be established

## Important Notes

- **Location ID**: After connecting, you'll need to select which Google My Business location to post to. This may require additional API calls to list the user's locations.
- **Refresh Token**: The app stores a refresh token to get new access tokens automatically. Make sure `access_type=offline` is set (which it is in the code).
- **API Quotas**: Google My Business API has rate limits. Check your quotas in the Google Cloud Console.

## Troubleshooting

### "Access Denied" or "Insufficient Permissions"
- Make sure you've enabled the Google My Business API
- Check that the scope `https://www.googleapis.com/auth/business.manage` is added to your OAuth consent screen
- Verify your test user email is added if the app is in testing mode

### "Redirect URI Mismatch"
- Double-check that the redirect URI in Google Cloud Console exactly matches:
  `https://new-social-rotation-backend-qzyk8.ondigitalocean.app/api/v1/oauth/google/callback`
- Make sure there are no trailing slashes or typos

### "Invalid Client"
- Verify your `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are correct in DigitalOcean
- Make sure you copied the full client ID (including the `.googleusercontent.com` part)

## Next Steps

After connecting Google My Business:
1. The app will need to fetch the user's locations
2. The user will need to select which location to post to
3. This location ID will be stored in the `user.location_id` field

