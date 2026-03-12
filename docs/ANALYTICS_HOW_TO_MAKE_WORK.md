# How to Make Each Analytics Platform Work

Use **GET /api/v1/analytics/status** (logged in) to see current state. Then follow the steps below for the platform you want.

---

## 1. Instagram

**What you get:** Followers, likes, comments, saves, profile views, website clicks, engagement rate.

### Backend (server env)

| Variable | Required | Notes |
|----------|----------|--------|
| `FACEBOOK_APP_ID` | Yes | From [developers.facebook.com](https://developers.facebook.com) → Your App → Settings → Basic. |
| `FACEBOOK_APP_SECRET` | Yes | Same place. |

No separate Instagram app: the same Facebook app is used for Instagram Login.

### Meta (Facebook) app setup

1. **App type:** Create or use a **Consumer** or **Business** app (not “Personal”).
2. **Add products:**
   - **Facebook Login** (for the OAuth flow).
   - **Instagram Graph API** (for insights and posting).
3. **Instagram Basic Display** is *not* what we use; we use **Instagram Graph API** (Business/Creator accounts linked to a Page).
4. **Permissions:** In App Review (or in the OAuth request), the app asks for:
   - `instagram_basic`
   - `instagram_content_publish`
   - `instagram_manage_insights` ← **required for analytics**
   - `instagram_manage_messages`
   - `pages_show_list`
   - (For Facebook flow also: `pages_manage_posts`, `pages_read_engagement`, etc.)
5. **App Review:** If your app is in development mode, only test users can connect. For production, submit for **App Review** for the permissions above (especially `instagram_manage_insights`).
6. **Valid OAuth Redirect URIs:** Add your callback URL, e.g. `https://yourdomain.com/api/v1/oauth/instagram/callback` and `https://yourdomain.com/api/v1/oauth/facebook/callback`.

### User side

1. **Instagram account:** Must be **Business** or **Creator** (Settings → Account type).
2. **Facebook Page:** Create or use a Facebook Page and **link** it to that Instagram account (Instagram Settings → Account → Linked accounts → Facebook Page).
3. **In your app:** Connect **Instagram** (or **Facebook** first, then Instagram). The flow stores:
   - `fb_user_access_key` (user or page token)
   - `instagram_business_id` (the IG Business account id)
4. **Analytics:** Backend calls `me/accounts` with the user token, finds the Page that has `instagram_business_account.id == instagram_business_id`, and uses that Page’s `access_token` to call `/{ig-id}/insights`.

### If status says `no_page_token`

- The Facebook token doesn’t have a Page whose Instagram Business id matches the stored `instagram_business_id`.
- **Fix:** Have the user reconnect **Facebook** (and Instagram if you use that flow) so the token includes the correct Page. Ensure the Page is linked to the same IG Business account they use in the app.
- In **Meta for Developers**: ensure the app has **Instagram Graph API** and the correct permissions; re-approve if needed.

---

## 2. Twitter

**What you get:** Follower count, and (if within limits) likes, replies, retweets for tweets in the date range.

### Backend (server env)

| Variable | Required | Notes |
|----------|----------|--------|
| `TWITTER_API_KEY` | Yes | Same as “Consumer Key” in [developer.twitter.com](https://developer.twitter.com) → Project → App → Keys. |
| `TWITTER_API_SECRET_KEY` | Yes | Same as “Consumer Secret”. |

Optional: `TWITTER_CALLBACK` – full callback URL if different from default.

(Code also accepts `TWITTER_CONSUMER_KEY` / `TWITTER_CONSUMER_SECRET` as fallbacks.)

### Twitter Developer setup

1. **Project & App:** Create a project and app in the [Twitter Developer Portal](https://developer.twitter.com).
2. **App permissions:** At least **Read** (and **Read and Write** if you post). For analytics we use:
   - **Users** (Read) – to get `user_id` and `public_metrics` (followers).
   - **Tweets** (Read) – to get tweet metrics in the range.
3. **OAuth 2.0:** If you use OAuth 2.0, ensure the app has a **Callback URI** set (e.g. `https://yourdomain.com/api/v1/oauth/twitter/callback`). Our OAuth flow uses the callback to exchange the code for tokens.
4. **API tier:** **Free** tier has a small monthly cap (e.g. 100 tweets for tweet reads). If status works but overall analytics fail with “monthly limit”, you’ll need to wait for reset or use a higher tier (e.g. Basic).

### User side

1. In your app, **Connect Twitter** (Profile / connected accounts). That stores `twitter_oauth_token` and `twitter_oauth_token_secret`.
2. On first analytics load we call `/2/users/me` and store `twitter_user_id` if missing.
3. Then we call `/2/users/:id?user.fields=public_metrics` for followers and `/2/users/:id/tweets` for engagement (within tier limits).

### If status says `env_missing`

- Set `TWITTER_API_KEY` and `TWITTER_API_SECRET_KEY` (or the Consumer key/secret) in the server environment and restart the app.

### If you hit rate limit or monthly cap

- Response will include a message. Wait (e.g. 15 minutes for rate limit, or next month for cap) or upgrade the Twitter app’s access tier.

---

## 3. LinkedIn

**What you get:** Follower count for a **Company Page**. Post-level engagement would require Community Management API (not implemented here).

### Backend (server env)

| Variable | Required | Notes |
|----------|----------|--------|
| `LINKEDIN_CLIENT_ID` | Yes | From [linkedin.com/developers](https://www.linkedin.com/developers/) → Your App → Auth. |
| `LINKEDIN_CLIENT_SECRET` | Yes | Same. |
| `LINKEDIN_CALLBACK` | Optional | Callback URL if not default, e.g. `https://yourdomain.com/api/v1/oauth/linkedin/callback`. |

### LinkedIn app setup

1. Create an app at [LinkedIn Developers](https://www.linkedin.com/developers/).
2. **Products:** Add the products that grant **organization** access (e.g. **Share on LinkedIn**, or **Marketing Developer Platform** if you need more). Organization access is required for `organizationalEntityAcls` and Company Page follower count.
3. **Auth:** Under the app’s **Auth** tab, add the correct **Authorized redirect URLs** (e.g. `https://yourdomain.com/api/v1/oauth/linkedin/callback`).
4. **Scopes:** Our app requests `w_member_social`, `openid`, `profile`, `email`. For Company Page data, LinkedIn may require additional permissions/products; if `fetch_organizations` returns empty, the app may need access to organization-related APIs (check LinkedIn’s docs for the product you added).

### User side

1. **Company Page:** The LinkedIn account must have **admin** (or similar) access to at least one **Company Page**.
2. In your app, **Connect LinkedIn**. That stores `linkedin_access_token`.
3. Analytics calls `LinkedinService#fetch_organizations` to list pages, then uses `networkSizes` with `COMPANY_FOLLOWED_BY_MEMBER` for follower count.

### If status says `no_organization`

- The token doesn’t return any Company Pages (e.g. user has no Page access, or app doesn’t have the right product/scopes).
- **Fix:** User must connect a LinkedIn account that has a Company Page; ensure the LinkedIn app has the right product and redirect URL.

### If you get 403 (Community Management API)

- Follower count uses `networkSizes`, which may be available without Community Management. If LinkedIn returns an error about “Community Management API”, their docs may require that product for your use case; apply in the LinkedIn Developer Portal if needed.

---

## 4. Facebook

**What you get:** Nothing yet. Backend returns a placeholder: “Facebook analytics coming soon.”

### What’s there today

- **Connect:** Users can connect Facebook (`fb_user_access_key` is stored and used for Instagram and for posting).
- **Analytics:** No Facebook-specific metrics are implemented. Status will show `connected: true/false` and `status: 'placeholder'`.

### To add Facebook analytics later

- You’d need to call Meta’s Page Insights (or similar) APIs with the Page access token and add a section in the analytics controller + frontend. Same app (FACEBOOK_APP_ID / FACEBOOK_APP_SECRET) and same token flow can be reused.

---

## 5. Posts count

**What you get:** Total posts and posts in the last 7 and 30 days from your DB.

- **No external API.** Counts `BucketSendHistory` for the current user’s buckets.
- **Always works** as long as the user is logged in; no env or connection steps.

---

## Quick checklist

| Platform    | Server env                          | User action                    | Status if it still fails              |
|------------|--------------------------------------|--------------------------------|----------------------------------------|
| Instagram  | FACEBOOK_APP_ID, FACEBOOK_APP_SECRET | IG Business + Page linked; connect in app | no_page_token → reconnect FB/IG, check Page link and app permissions |
| Twitter    | TWITTER_API_KEY, TWITTER_API_SECRET_KEY | Connect Twitter in app         | env_missing → set env; rate/cap → wait or upgrade tier |
| LinkedIn   | LINKEDIN_CLIENT_ID, LINKEDIN_CLIENT_SECRET, (LINKEDIN_CALLBACK) | Connect LinkedIn; have Company Page | no_organization → Page access + app products |
| Facebook   | (same as Instagram)                  | Connect Facebook (for IG/post) | Analytics not implemented              |
| Posts count| —                                    | —                              | Always works                           |

After changing env or app settings, restart the app and have the user reconnect the account if needed, then call **GET /api/v1/analytics/status** again to confirm.
