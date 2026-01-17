# How to Check Scheduler Logs

## Method 1: DigitalOcean Dashboard (Recommended)

1. Go to https://cloud.digitalocean.com/apps
2. Click on your app (social-rotation-backend)
3. Click on "Runtime Logs" tab
4. Filter by searching for: `scheduler` or `Processing scheduled posts`
5. You should see logs every minute like:
   ```
   === Processing scheduled posts at 2026-01-15 22:25:00 UTC ===
   Checking cron: 25 17 15 1 * | user timezone: America/Denver | Server UTC: ... | User Local: ...
   ```

## Method 2: Check CRON Job Logs

1. Go to DigitalOcean → App Platform → Your App
2. Click on "Jobs" tab
3. Find the "scheduler" job (runs every minute: `*/1 * * * *`)
4. Click on it to see its logs
5. Check if it's running and what errors (if any) it's showing

## Method 3: Test Manually

1. Go to your Schedule page in the app
2. Click "Test Scheduler Now" button
3. Check the logs immediately - you'll see what the scheduler checked

## What to Look For

**Good logs:**
```
=== Processing scheduled posts at 2026-01-15 22:25:00 UTC ===
Found 1 total schedules to check
Checking cron: 25 17 15 1 * | user timezone: America/Denver | ...
Cron minute match: 25 is within 5 minutes of 25 (diff: 0, ...)
✓ Cron match: 25 17 15 1 * matches current time ...
Successfully posted schedule item X to social media
```

**Problem logs:**
```
No schedules found, exiting
```
or
```
Cron day mismatch: scheduled day 15 != current day 16
```
or
```
User X has no timezone set - using UTC for schedule Y
```

## Troubleshooting

- **No scheduler logs at all?** → CRON job might not be running. Check DigitalOcean Jobs tab.
- **Day mismatch?** → Server clock might be wrong (showing wrong date)
- **No timezone set?** → User needs to set timezone in Profile settings
- **Scheduler not matching?** → Check the detailed logs to see why (day/hour/minute mismatch)

