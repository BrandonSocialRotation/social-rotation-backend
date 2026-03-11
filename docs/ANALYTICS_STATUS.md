# Analytics – What’s Implemented and Why It Might Not Work

## Check status in the app

**GET /api/v1/analytics/status** (authenticated) returns per-platform diagnostics:

- **instagram** – connected, status (`working` / `no_page_token` / `error` / `not_connected`), message  
- **twitter** – connected, status (`ready` / `env_missing` / `not_connected`), message  
- **linkedin** – connected, status (`working` / `no_organization` / `error` / `not_connected`), message  
- **facebook** – connected, status `placeholder`, message  
- **posts_count** – status `working`, total_posts (always from your DB)

Use this to see what’s working and what’s not without guessing.

---

## By platform

### Instagram

- **Needs:** User has **Instagram Business/Creator** linked to a **Facebook Page**; backend has `instagram_business_id` and `fb_user_access_key`.
- **What we do:** Meta Graph API – insights (likes, comments, saves, profile_views, website_clicks) and follower count. We get a Page access token that has the IG Business account, then call `/{ig-business-id}/insights`.
- **Common failures:**
  - **not_connected** – User didn’t connect Facebook and/or Instagram, or IG isn’t linked to a Page.
  - **no_page_token** – No Page in the token’s account matches `instagram_business_id` (e.g. wrong Page, token from another app/user).
  - **error** – Token expired, permissions missing (e.g. `instagram_manage_insights`), or Meta API error (check logs).

### Twitter

- **Needs:** User has Twitter connected (`twitter_oauth_token`, `twitter_oauth_token_secret`). Server has **TWITTER_API_KEY** and **TWITTER_API_SECRET_KEY** (or TWITTER_CONSUMER_KEY / TWITTER_CONSUMER_SECRET).
- **What we do:** Twitter API v2 – `/2/users/me` and `/2/users/:id` for `public_metrics` (followers), then `/2/users/:id/tweets` with `public_metrics` for likes/replies/retweets in the range.
- **Common failures:**
  - **not_connected** – User hasn’t connected Twitter.
  - **env_missing** – Env vars not set on the server.
  - **Rate limit (429)** – Too many requests; wait or upgrade to Basic.
  - **Monthly cap** – Free tier has a small tweet cap (e.g. 100 tweets/month for tweet metrics); message in response.

### LinkedIn

- **Needs:** User has LinkedIn connected with an account that has access to at least one **Company Page**.
- **What we do:** We call `LinkedinService#fetch_organizations`, then use `networkSizes` with `COMPANY_FOLLOWED_BY_MEMBER` for follower count. We don’t have post-level engagement unless you have Community Management API access.
- **Common failures:**
  - **not_connected** – User hasn’t connected LinkedIn.
  - **no_organization** – No Company Page, or token doesn’t have access to any.
  - **error** – 403/401 often means “Community Management API” or permissions; message in response.

### Facebook

- **Status:** Placeholder only. “Facebook analytics coming soon.” No real metrics yet.

### Posts count

- **Source:** Your DB only – counts `BucketSendHistory` for the user’s buckets. No external API.
- **Always works** as long as the user is logged in and has buckets.

---

## Endpoints

| Endpoint | Purpose |
|----------|--------|
| GET /api/v1/analytics/status | **Use this first** – diagnostics for all platforms. |
| GET /api/v1/analytics/instagram/summary?range=7d | Instagram summary (or zeros if not working). |
| GET /api/v1/analytics/instagram/timeseries?metric=likes&range=7d | Instagram time series. |
| GET /api/v1/analytics/platform/:platform?range=7d | One platform; instagram = real, facebook/twitter/linkedin = real or placeholder. |
| GET /api/v1/analytics/overall?range=7d | Aggregated metrics for connected platforms. |
| GET /api/v1/analytics/posts_count | Total and last 7d/30d sent posts. |

All require authentication.
