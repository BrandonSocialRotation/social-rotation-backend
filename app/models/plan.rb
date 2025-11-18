# Plan Model
# Represents a subscription plan with location-based or user-seat-based pricing
class Plan < ApplicationRecord
  # Associations
  has_many :subscriptions, dependent: :restrict_with_error
  has_many :accounts, dependent: :nullify
  
  # Validations
  validates :name, presence: true
  validates :plan_type, presence: true, inclusion: { in: %w[location_based user_seat_based] }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :max_locations, numericality: { greater_than: 0 }, if: -> { plan_type == 'location_based' }
  validates :max_users, numericality: { greater_than: 0 }, if: -> { plan_type == 'user_seat_based' }
  validates :max_buckets, numericality: { greater_than: 0 }
  validates :max_images_per_bucket, numericality: { greater_than: 0 }
  
  # Scopes
  scope :active, -> { where(status: true) }
  scope :location_based, -> { where(plan_type: 'location_based') }
  scope :user_seat_based, -> { where(plan_type: 'user_seat_based') }
  scope :ordered, -> { order(:sort_order, :price_cents) }
  
  # Plan types
  PLAN_TYPES = {
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
  
  # Get display name with price
  def display_name
    "#{name} - #{formatted_price}/month"
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
