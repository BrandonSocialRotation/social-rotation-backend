# Instagram & Facebook – Simple Step-by-Step (Make It Work)

One Meta (Facebook) app is used for both. **Instagram** analytics work when the steps below are done. **Facebook** analytics are not built yet (placeholder only); these steps get Facebook + Instagram *connected* and Instagram *insights* working.

---

## Part A: Create the Meta app (one-time)

1. Go to **https://developers.facebook.com** and log in.
2. Click **My Apps** → **Create App** → choose **Consumer** or **Business** (not “Personal”).
3. Pick a name and create the app.
4. In the app dashboard, open **Settings → Basic**.
   - Copy **App ID** → you’ll use this as `FACEBOOK_APP_ID`.
   - Copy **App Secret** → you’ll use this as `FACEBOOK_APP_SECRET`.
5. In the left menu, click **Add Product**.
   - Add **Facebook Login** (if not already there).
   - Add **Instagram Graph API** (this is what we use for Instagram Business/Creator and insights).
6. Under **Facebook Login → Settings**:
   - In **Valid OAuth Redirect URIs** add:
     - `https://YOUR-DOMAIN.com/api/v1/oauth/facebook/callback`
     - `https://YOUR-DOMAIN.com/api/v1/oauth/instagram/callback`
   - Replace `YOUR-DOMAIN.com` with your real domain (e.g. `api.yourapp.com`).
   - Save.
7. Under **App Review → Permissions and Features** (or **App Review → Requests**):
   - Request these if they’re not “Approved” yet:
     - `instagram_basic`
     - `instagram_manage_insights` ← **needed for analytics**
     - `instagram_content_publish`
     - `pages_show_list`
     - `pages_manage_posts`
     - `pages_read_engagement`
   - In development mode, only test users can connect; for everyone, submit for **App Review** and get these approved.

---

## Part B: Set env vars on your server

8. On the server (or in `.env` / your config), set:
   - `FACEBOOK_APP_ID` = the App ID from step 4.
   - `FACEBOOK_APP_SECRET` = the App Secret from step 4.
9. Restart the app so it picks up the new env.

---

## Part C: Link Instagram to a Facebook Page (each user)

10. The user must use an **Instagram Business or Creator** account (not Personal).
    - In Instagram: **Settings → Account → Switch to Professional Account** if needed.
11. They need a **Facebook Page**.
    - Create one at **facebook.com/pages/create** if they don’t have one.
12. **Link the Page to Instagram:**
    - Instagram → **Settings → Account → Linked accounts → Facebook**.
    - Log in to Facebook if asked and choose the Page to link.
13. In **your app**, the user clicks **Connect Facebook** and/or **Connect Instagram** (depending on your UI) and completes the login. Don’t skip permissions.

---

## Part D: Check that it works

14. Call **GET /api/v1/analytics/status** (while logged in as that user).
15. Look at **instagram**:
    - `status: "working"` and a message like “Instagram Business linked; insights API ready” = it works.
    - `status: "no_page_token"` = the token doesn’t have the Page that’s linked to this IG account. Have the user **disconnect and reconnect Facebook (and Instagram)** and try again.
    - `status: "not_connected"` = connect Facebook and Instagram in the app.

---

## Summary checklist

- [ ] Meta app created (Consumer or Business).
- [ ] **Instagram Graph API** and **Facebook Login** products added.
- [ ] Redirect URIs set for `/api/v1/oauth/facebook/callback` and `/api/v1/oauth/instagram/callback`.
- [ ] Permissions requested (and approved if not in dev mode), including **instagram_manage_insights**.
- [ ] `FACEBOOK_APP_ID` and `FACEBOOK_APP_SECRET` set on server; app restarted.
- [ ] User’s Instagram is Business/Creator and linked to a Facebook Page.
- [ ] User connected Facebook and/or Instagram in your app.
- [ ] **GET /api/v1/analytics/status** shows Instagram `status: "working"`.

**Facebook analytics:** Not implemented yet; the same app and connection are used for posting and for Instagram. When you add Facebook Page insights later, you’ll use the same env and tokens.
