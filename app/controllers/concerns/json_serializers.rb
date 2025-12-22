module JsonSerializers
  extend ActiveSupport::Concern

  def rss_feed_json(feed)
    {
      id: feed.id,
      url: feed.url,
      name: feed.name,
      description: feed.description,
      is_active: feed.is_active,
      status: feed.status,
      health_status: feed.health_status,
      last_fetched_at: feed.last_fetched_at,
      last_successful_fetch_at: feed.last_successful_fetch_at,
      fetch_failure_count: feed.fetch_failure_count,
      last_fetch_error: feed.last_fetch_error,
      posts_count: feed.rss_posts.count,
      unviewed_posts_count: feed.unviewed_posts.count,
      created_at: feed.created_at,
      updated_at: feed.updated_at,
      account: feed.account ? { id: feed.account.id, name: feed.account.name } : nil,
      created_by: { id: feed.user.id, name: feed.user.name, email: feed.user.email }
    }
  end

  def rss_post_json(post)
    {
      id: post.id,
      title: post.title,
      description: post.description,
      content: post.content,
      image_url: post.image_url,
      original_url: post.original_url,
      published_at: post.published_at,
      is_viewed: post.is_viewed,
      short_title: post.short_title,
      short_description: post.short_description,
      has_image: post.has_image?,
      display_image_url: post.display_image_url,
      social_media_content: post.social_media_content,
      formatted_published_at: post.formatted_published_at,
      relative_published_at: post.relative_published_at,
      recent: post.recent?,
      created_at: post.created_at,
      updated_at: post.updated_at
    }
  end

  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      plan_type: plan.plan_type,
      price_cents: plan.price_cents,
      price_dollars: plan.price_dollars,
      formatted_price: plan.formatted_price,
      max_locations: plan.max_locations,
      max_users: plan.max_users,
      max_buckets: plan.max_buckets,
      max_images_per_bucket: plan.max_images_per_bucket,
      features: plan.features_hash,
      stripe_price_id: plan.stripe_price_id,
      stripe_product_id: plan.stripe_product_id,
      display_name: plan.display_name,
      supports_per_user_pricing: plan.has_attribute?(:supports_per_user_pricing) ? (plan.supports_per_user_pricing || false) : false,
      base_price_cents: plan.has_attribute?(:base_price_cents) ? (plan.base_price_cents || 0) : 0,
      per_user_price_cents: plan.has_attribute?(:per_user_price_cents) ? (plan.per_user_price_cents || 0) : 0,
      per_user_price_after_10_cents: plan.has_attribute?(:per_user_price_after_10_cents) ? (plan.per_user_price_after_10_cents || 0) : 0,
      billing_period: plan.has_attribute?(:billing_period) ? (plan.billing_period || 'monthly') : 'monthly'
    }
  end

  def subscription_json(subscription)
    plan_data = subscription.plan ? {
      id: subscription.plan.id,
      name: subscription.plan.name,
      plan_type: subscription.plan.plan_type
    } : nil
    
    {
      id: subscription.id,
      plan: plan_data,
      status: subscription.status,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      days_remaining: subscription.days_remaining,
      active: subscription.active?,
      will_cancel: subscription.will_cancel?
    }
  rescue => e
    Rails.logger.error "Error in subscription_json: #{e.message}"
    {
      id: subscription.id,
      plan: nil,
      status: subscription.status || 'unknown',
      error: 'Failed to load subscription details'
    }
  end
end
