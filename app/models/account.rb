class Account < ApplicationRecord
  # Associations
  has_many :users, dependent: :nullify
  has_one :account_feature, dependent: :destroy
  has_many :rss_feeds, dependent: :destroy
  belongs_to :plan, optional: true
  has_one :subscription, dependent: :destroy
  
  # Validations
  validates :name, presence: true
  validates :subdomain, uniqueness: { case_sensitive: true }, allow_nil: true
  
  # Callbacks
  after_create :create_default_features
  
  # Check if this account is a reseller
  def reseller?
    is_reseller
  end
  
  # Get all sub-accounts under this reseller
  def sub_accounts
    users.where.not(is_account_admin: true)
  end
  
  # Get account admins
  def admins
    users.where(is_account_admin: true)
  end
  
  # Check if account can add more users
  def can_add_user?
    return true if super_admin_account?
    
    # Use plan limits if available, otherwise fall back to account_feature
    max_users = (plan&.max_users rescue nil) || account_feature&.max_users || 1
    users.active.count < max_users
  end
  
  # Check if account can add more buckets
  def can_add_bucket?(user)
    return true if super_admin_account?
    
    # Use plan limits if available, otherwise fall back to account_feature
    max_buckets = (plan&.max_buckets rescue nil) || account_feature&.max_buckets || 10
    user.buckets.count < max_buckets
  end
  
  # Check if account has active subscription
  # For Free Access plans: Also checks if current_period_end has passed
  # For paid plans: Trusts Stripe subscription status (auto-renewed)
  def has_active_subscription?
    return false unless subscription
    return false unless subscription.active? rescue false
    
    # Additional check only for Free Access plans
    # Paid plans are managed by Stripe and auto-renew, so we trust the status
    is_free_plan = subscription.plan&.name == "Free Access"
    if is_free_plan && subscription.current_period_end
      return false if subscription.current_period_end < Time.current
    end
    
    true
  rescue => e
    Rails.logger.error "Error checking subscription: #{e.message}"
    false
  end
  
  # Get current subscription
  def current_subscription
    return nil unless subscription
    subscription if has_active_subscription?
  end
  
  # Check if account is super admin (account_id = 0)
  def super_admin_account?
    id == 0
  end
  
  private
  
  def create_default_features
    AccountFeature.create!(account: self) unless account_feature
  end
end
