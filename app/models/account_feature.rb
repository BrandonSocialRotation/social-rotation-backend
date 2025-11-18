class AccountFeature < ApplicationRecord
  belongs_to :account
  
  # Validations
  validates :account, presence: true
  validates :max_users, numericality: { greater_than: 0 }
  validates :max_buckets, numericality: { greater_than: 0 }
  validates :max_images_per_bucket, numericality: { greater_than: 0 }
  
  # Default values for new account features
  after_initialize :set_defaults, if: :new_record?
  after_initialize :apply_plan_limits, if: :new_record?
  
  # Get effective max_users (from plan if available, otherwise from account_feature)
  def effective_max_users
    account.plan&.max_users || max_users
  end
  
  # Get effective max_buckets (from plan if available, otherwise from account_feature)
  def effective_max_buckets
    account.plan&.max_buckets || max_buckets
  end
  
  # Get effective max_images_per_bucket (from plan if available, otherwise from account_feature)
  def effective_max_images_per_bucket
    account.plan&.max_images_per_bucket || max_images_per_bucket
  end
  
  private
  
  def set_defaults
    self.allow_marketplace ||= false
    self.allow_rss ||= true  # Enable RSS by default for all accounts
    self.max_users ||= 1
    self.max_buckets ||= 10
    self.max_images_per_bucket ||= 100
  end
  
  # Apply plan limits if account has a plan
  def apply_plan_limits
    return unless account&.plan
    
    plan = account.plan
    self.max_users = plan.max_users if plan.max_users.present?
    self.max_buckets = plan.max_buckets if plan.max_buckets.present?
    self.max_images_per_bucket = plan.max_images_per_bucket if plan.max_images_per_bucket.present?
    
    # Apply plan features
    plan_features = plan.features_hash
    self.allow_marketplace = plan_features['marketplace'] == true if plan_features.key?('marketplace')
    self.allow_rss = plan_features['rss'] != false # Default to true unless explicitly disabled
  end
end
