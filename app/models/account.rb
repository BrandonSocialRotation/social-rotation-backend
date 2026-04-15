class Account < ApplicationRecord
  # Super admins use users.account_id = 0 with no row here historically — that breaks white label / FKs.
  # This id is the shared "platform" account for super-admin agency settings (white label, client portal domains).
  SUPER_ADMIN_ACCOUNT_ID = 0

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
    id == SUPER_ADMIN_ACCOUNT_ID
  end

  # Ensures the platform account exists for users with account_id 0 (super admins).
  # Never call find(0) in a rescue path — if create fails, find raises RecordNotFound → 500.
  def self.ensure_platform_account_for_super_admins!
    acc = find_by(id: SUPER_ADMIN_ACCOUNT_ID)
    return acc if acc

    create!(
      id: SUPER_ADMIN_ACCOUNT_ID,
      name: 'Platform administrator',
      is_reseller: true
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[PlatformAccount] create race/invalid: #{e.class}: #{e.message}"
    find_by(id: SUPER_ADMIN_ACCOUNT_ID)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error "[PlatformAccount] DB error: #{e.message}"
    find_by(id: SUPER_ADMIN_ACCOUNT_ID)
  end

  # Default branding for client portal / public branding API — from agency White label settings + admin user assets.
  # Domain-specific ClientPortalDomain#branding JSON overrides these per hostname.
  def agency_default_branding_hash
    admin = users.where(is_account_admin: true).order(:id).first
    title = has_attribute?(:software_title) ? software_title : nil
    biz = has_attribute?(:business_name) ? business_name : nil
    {
      app_name: title.presence || biz.presence || name,
      logo_url: admin&.get_watermark_logo.presence,
      favicon_url: (admin&.respond_to?(:favicon_logo) && admin&.favicon_logo.present?) ? admin.get_favicon_logo : nil,
      primary_color: nil
    }.compact.symbolize_keys
  end

  private
  
  def create_default_features
    AccountFeature.create!(account: self) unless account_feature
  end
end
