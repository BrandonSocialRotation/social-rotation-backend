# Plan Model
# Represents a subscription plan with location-based or user-seat-based pricing
class Plan < ApplicationRecord
  # Associations
  has_many :subscriptions, dependent: :restrict_with_error
  has_many :accounts, dependent: :nullify
  
  # Validations
  validates :name, presence: true
  validates :plan_type, presence: true, inclusion: { in: %w[personal agency location_based user_seat_based] }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :max_locations, numericality: { greater_than: 0 }, if: -> { plan_type == 'location_based' }
  validates :max_users, numericality: { greater_than: 0 }, if: -> { plan_type == 'user_seat_based' || plan_type == 'agency' }
  validates :max_buckets, numericality: { greater_than: 0 }
  validates :max_images_per_bucket, numericality: { greater_than: 0 }
  
  # Scopes
  scope :active, -> { where(status: true) }
  scope :personal, -> { where(plan_type: 'personal') }
  scope :agency, -> { where(plan_type: 'agency') }
  scope :location_based, -> { where(plan_type: 'location_based') }
  scope :user_seat_based, -> { where(plan_type: 'user_seat_based') }
  scope :ordered, -> { order(:sort_order, :price_cents) }
  
  # Plan types
  PLAN_TYPES = {
    personal: 'personal',
    agency: 'agency',
    location_based: 'location_based',
    user_seat_based: 'user_seat_based'
  }.freeze
  
  # Get plan features as hash
  def features_hash
    return {} if features.blank?
    JSON.parse(features)
  rescue JSON::ParserError
    {}
  end
  
  # Set plan features from hash
  def features_hash=(hash)
    self.features = hash.to_json
  end
  
  # Check if feature is enabled
  def feature_enabled?(feature_name)
    features_hash[feature_name.to_s] == true
  end
  
  # Get formatted price
  def price_dollars
    price_cents / 100.0
  end
  
  # Get price formatted as string
  def formatted_price
    "$#{format('%.2f', price_dollars)}"
  end
  
  # Calculate price based on user count (for per-user pricing plans)
  def calculate_price_for_users(user_count, billing_period = 'monthly')
    # Check if column exists (for backwards compatibility during migration)
    return price_cents unless has_attribute?(:supports_per_user_pricing) && supports_per_user_pricing
    
    # Base price
    total = base_price_cents || 0
    
    # First user is included in base, so we charge for additional users
    additional_users = [user_count - 1, 0].max
    
    if additional_users > 0
      # First 10 additional users at per_user_price_cents
      users_at_regular_price = [additional_users, 10].min
      total += users_at_regular_price * (per_user_price_cents || 0)
      
      # Users after 10 at per_user_price_after_10_cents
      if additional_users > 10
        users_at_discounted_price = additional_users - 10
        total += users_at_discounted_price * (per_user_price_after_10_cents || 0)
      end
    end
    
    # Apply annual discount (2 months free = pay for 10 months, get 12)
    # For annual, multiply monthly price by 10 to get annual total
    if billing_period == 'annual'
      total = (total * 10).round
    end
    
    total
  end
  
  # Get formatted price for user count
  def formatted_price_for_users(user_count, billing_period = 'monthly')
    price = calculate_price_for_users(user_count, billing_period)
    period = billing_period == 'annual' ? 'year' : 'month'
    "$#{format('%.2f', price / 100.0)}/#{period}"
  end
  
  # Get display name with price
  def display_name
    # Check if column exists (for backwards compatibility during migration)
    if has_attribute?(:supports_per_user_pricing) && supports_per_user_pricing
      billing = has_attribute?(:billing_period) ? billing_period : 'monthly'
      "#{name} - Starting at #{formatted_price}/#{billing == 'annual' ? 'year' : 'month'}"
    else
      "#{name} - #{formatted_price}/month"
    end
  end
  
  # Check if plan is personal
  def personal?
    plan_type == 'personal'
  end
  
  # Check if plan is agency
  def agency?
    plan_type == 'agency'
  end
  
  # Check if plan is location-based
  def location_based?
    plan_type == 'location_based'
  end
  
  # Check if plan is user-seat-based
  def user_seat_based?
    plan_type == 'user_seat_based'
  end
end
