# Stripe Tier System Setup Guide

## Overview

The tier system supports two pricing models:
1. **Location-based**: Plans scale by number of locations (Single, 10 Locations, 30 Locations)
2. **User-seat-based**: Plans scale by number of user seats (Starter 5, Professional 15, Enterprise 50)

## Database Setup

Run migrations to create the plans and subscriptions tables:

```bash
rails db:migrate
rails db:seed  # Creates default plans
```

## Stripe Configuration

### 1. Get Stripe API Keys

1. Go to https://dashboard.stripe.com/apikeys
2. Copy your **Publishable Key** and **Secret Key**
3. Add to DigitalOcean environment variables:
   - `STRIPE_SECRET_KEY=sk_live_...` (or `sk_test_...` for testing)
   - `STRIPE_PUBLISHABLE_KEY=pk_live_...` (or `pk_test_...` for testing)

### 2. Create Products and Prices in Stripe

For each plan in your database, create a corresponding Stripe Product and Price:

1. Go to https://dashboard.stripe.com/products
2. Click "Add product"
3. Create products for each plan:
   - **Single Location** - $29/month
   - **10 Locations** - $99/month
   - **30 Locations** - $249/month
   - **Starter (5 Seats)** - $49/month
   - **Professional (15 Seats)** - $149/month
   - **Enterprise (50 Seats)** - $499/month

4. For each product:
   - Set billing period to "Monthly"
   - Copy the **Price ID** (starts with `price_...`)
   - Copy the **Product ID** (starts with `prod_...`)

### 3. Update Plans with Stripe IDs

Update each plan in your database with the Stripe Price ID and Product ID:

```ruby
# In Rails console
plan = Plan.find_by(name: "Single Location")
plan.update!(
  stripe_price_id: "price_xxxxx",
  stripe_product_id: "prod_xxxxx"
)
```

### 4. Set Up Webhook Endpoint

1. Go to https://dashboard.stripe.com/webhooks
2. Click "Add endpoint"
3. Set endpoint URL to: `https://your-backend-url.com/api/v1/subscriptions/webhook`
4. Select events to listen to:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Copy the **Signing secret** (starts with `whsec_...`)
6. Add to DigitalOcean environment variables:
   - `STRIPE_WEBHOOK_SECRET=whsec_...`

## API Endpoints

### Get Available Plans
```
GET /api/v1/plans
GET /api/v1/plans?plan_type=location_based
GET /api/v1/plans?plan_type=user_seat_based
```

### Create Checkout Session
```
POST /api/v1/subscriptions/checkout_session
Body: { plan_id: 1 }
Response: { checkout_session_id: "...", checkout_url: "https://..." }
```

### Get Current Subscription
```
GET /api/v1/subscriptions
Response: { subscription: {...} }
```

### Cancel Subscription
```
POST /api/v1/subscriptions/cancel
Response: { subscription: {...}, message: "..." }
```

## Frontend Integration

### 1. Display Plans

```typescript
// Fetch plans
const { data } = await api.get('/plans?plan_type=location_based');

// Display plan cards with:
// - Plan name and price
// - Features list
// - "Subscribe" button
```

### 2. Create Checkout Session

```typescript
const response = await api.post('/subscriptions/checkout_session', {
  plan_id: selectedPlanId
});

// Redirect to checkout URL
window.location.href = response.data.checkout_url;
```

### 3. Handle Success/Cancel

After Stripe checkout:
- **Success**: User is redirected to `/subscription/success?session_id=...`
- **Cancel**: User is redirected to `/subscription/cancel`

The webhook will automatically create the subscription in your database.

## Default Plans Created

### Location-Based Plans
- **Single Location**: $29/month - 1 location, 1 user, 10 buckets
- **10 Locations**: $99/month - 10 locations, 10 users, 100 buckets
- **30 Locations**: $249/month - 30 locations, 30 users, 300 buckets

### User-Seat-Based Plans
- **Starter (5 Seats)**: $49/month - 5 users, 50 buckets
- **Professional (15 Seats)**: $149/month - 15 users, 150 buckets
- **Enterprise (50 Seats)**: $499/month - 50 users, 500 buckets

## How It Works

1. **Account Creation**: New accounts don't have a plan initially
2. **Plan Selection**: Account admin selects a plan and creates checkout session
3. **Stripe Checkout**: User completes payment in Stripe
4. **Webhook**: Stripe sends webhook, subscription is created automatically
5. **Plan Limits**: Account limits are enforced based on plan
6. **Subscription Management**: Account admins can view/cancel subscriptions

## Testing

Use Stripe test mode:
- Test cards: https://stripe.com/docs/testing
- Use `sk_test_...` and `pk_test_...` keys
- Test webhooks using Stripe CLI: `stripe listen --forward-to localhost:3000/api/v1/subscriptions/webhook`

## Environment Variables Required

```
STRIPE_SECRET_KEY=sk_live_... or sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_live_... or pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
FRONTEND_URL=https://your-frontend-url.com
```

