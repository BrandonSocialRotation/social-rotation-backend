# Updates Stripe subscription when sub-accounts (seats) are added or removed.
# - On add: charge prorated amount for the new seat for the rest of the period.
# - On remove: apply lower price at next period end (no refund for current period).
class SubscriptionSeatService
  class Error < StandardError; end

  # Call before creating a sub-account. Updates Stripe subscription to charge for the new seat (prorated).
  # Raises SubscriptionSeatService::Error if account has no per-user subscription or Stripe fails.
  # @param account [Account]
  def self.charge_for_new_seat(account)
    new(account).charge_for_new_seat
  end

  # Call when deleting a sub-account. Updates Stripe so the lower price applies at period end (no refund).
  # @param account [Account] account that will have one fewer user after the delete
  def self.apply_removed_seat_at_period_end(account)
    new(account).apply_removed_seat_at_period_end
  end

  def initialize(account)
    @account = account
    @subscription = account.subscription
  end

  def charge_for_new_seat
    return true unless requires_seat_update?

    sub = fetch_stripe_subscription
    current_count = @account.users.count
    new_count = current_count + 1

    validate_can_add_seat!(new_count)

    price_cents = @subscription.plan.calculate_price_for_users(new_count, billing_period)
    new_stripe_price = create_stripe_price_for_user_count(new_count, price_cents)
    item_id = sub.items.data.first.id

    Stripe::Subscription.update(
      @subscription.stripe_subscription_id,
      items: [{ id: item_id, price: new_stripe_price.id }],
      proration_behavior: 'create_prorations'
    )

    @subscription.update_column(:user_count_at_subscription, new_count)
    true
  end

  # Call after destroying a sub-account. Uses current user count (already reduced).
  def apply_removed_seat_at_period_end
    return true unless requires_seat_update?

    sub = fetch_stripe_subscription
    new_count = [@account.users.count, 1].max

    price_cents = @subscription.plan.calculate_price_for_users(new_count, billing_period)
    new_stripe_price = create_stripe_price_for_user_count(new_count, price_cents)
    item_id = sub.items.data.first.id

    Stripe::Subscription.update(
      @subscription.stripe_subscription_id,
      items: [{ id: item_id, price: new_stripe_price.id }],
      proration_behavior: 'none'
    )

    @subscription.update_column(:user_count_at_subscription, new_count)
    true
  end

  private

  def requires_seat_update?
    return false unless @subscription
    return false unless @subscription.plan
    return false unless @subscription.stripe_subscription_id.present?
    return false unless @subscription.plan.respond_to?(:supports_per_user_pricing) && @subscription.plan.supports_per_user_pricing

    true
  end

  def billing_period
    @subscription.respond_to?(:billing_period) && @subscription.billing_period.present? ? @subscription.billing_period : 'monthly'
  end

  def fetch_stripe_subscription
    Stripe::Subscription.retrieve(
      @subscription.stripe_subscription_id,
      expand: ['items.data']
    )
  rescue Stripe::StripeError => e
    raise Error, "Stripe error: #{e.message}"
  end

  def validate_can_add_seat!(new_count)
    max = @subscription.plan.respond_to?(:max_users) ? @subscription.plan.max_users : nil
    return unless max && new_count > max

    raise Error, "Maximum users (#{max}) for your plan would be exceeded"
  end

  def create_stripe_price_for_user_count(user_count, price_cents)
    Stripe::Price.create(
      unit_amount: price_cents,
      currency: 'usd',
      recurring: {
        interval: billing_period == 'annual' ? 'year' : 'month'
      },
      product_data: {
        name: "#{@subscription.plan.name} (#{user_count} user#{user_count != 1 ? 's' : ''})"
      }
    )
  rescue Stripe::StripeError => e
    raise Error, "Stripe price error: #{e.message}"
  end
end
