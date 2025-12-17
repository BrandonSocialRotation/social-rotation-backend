class MarketItem < ApplicationRecord
  # Associations
  belongs_to :bucket
  belongs_to :front_image, class_name: 'Image', optional: true
  has_many :user_market_items, dependent: :destroy
  
  # Validations
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # Scopes
  scope :all_reseller, -> { where(visible: true) }
  
  # Methods from original PHP
  def has_hidden_user_market_item?(user_id)
    user_market_items.where(user_id: user_id, visible: false).exists?
  end
  
  def has_user_market_item?(user_id)
    user_market_items.where(user_id: user_id).exists?
  end
  
  def get_front_image_url
    return front_image.get_source_url if front_image
    
    if bucket&.bucket_images&.any?
      first_bucket_image = bucket.bucket_images.order(:friendly_name).first
      return first_bucket_image.image.get_source_url if first_bucket_image&.image
    end
    
    '/img/no_image_available.gif'
  end
  
  def get_front_image_friendly_name
    return front_image.friendly_name if front_image
    
    if bucket&.bucket_images&.any?
      first_bucket_image = bucket.bucket_images.order(:friendly_name).first
      return first_bucket_image.friendly_name if first_bucket_image
    end
    
    'N/A'
  end
end
