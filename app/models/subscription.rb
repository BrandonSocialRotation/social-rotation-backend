# Subscription Model
# Tracks Stripe subscriptions for accounts
class Subscription < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :plan
  
  # Validations
  validates :status, presence: true
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true
  validates :stripe_customer_id, presence: true
  
  # Scopes
  scope :active, -> { where(status: [STATUS_ACTIVE, STATUS_TRIALING]) }
  scope :trialing, -> { where(status: 'trialing') }
  scope :canceled, -> { where(status: 'canceled') }
  scope :past_due, -> { where(status: 'past_due') }
  
  # Status constants
  STATUS_ACTIVE = 'active'
  STATUS_TRIALING = 'trialing'
  STATUS_CANCELED = 'canceled'
  STATUS_PAST_DUE = 'past_due'
  STATUS_UNPAID = 'unpaid'
  STATUS_INCOMPLETE = 'incomplete'
  STATUS_INCOMPLETE_EXPIRED = 'incomplete_expired'
  
  # Check if subscription is active
  # For Free Access plans: Must have active status AND not be past the end date
  # For paid plans: Trust Stripe status (current_period_end is auto-updated by Stripe webhooks)
  def active?
    return false unless status == STATUS_ACTIVE || status == STATUS_TRIALING
    
    # Only check expiration date for Free Access plans
    # Paid plans have Stripe subscriptions that auto-renew, so we trust the status
    is_free_plan = plan&.name == "Free Access"
    
    if is_free_plan && current_period_end
      # For free plans, check if end date has passed
      return current_period_end >= Time.current
    end
    
    # For paid plans or plans without end date, trust the status
    true
  end
  
  # Check if subscription is canceled
  def canceled?
    status == STATUS_CANCELED
  end
  
  # Check if subscription is past due
  def past_due?
    status == STATUS_PAST_DUE
  end
  
  # Check if subscription is in trial
  def trialing?
    status == STATUS_TRIALING
  end
  
  # Check if subscription will cancel at period end
  def will_cancel?
    cancel_at_period_end? && active?
  end
  
  # Get days remaining in current period
  def days_remaining
    return 0 unless current_period_end
    seconds_remaining = (current_period_end - Time.current).to_i
    days = seconds_remaining / 86400 # 86400 seconds in a day
    [days, 0].max
  end
  
  # Check if subscription is expired
  def expired?
    return false unless current_period_end
    current_period_end < Time.current && !active?
  end
end
