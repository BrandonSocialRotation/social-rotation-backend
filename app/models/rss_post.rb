# RSS Post Model
# Represents a single post/article from an RSS feed
# Can be reviewed, edited, and scheduled for social media posting
class RssPost < ApplicationRecord
  # ASSOCIATIONS
  belongs_to :rss_feed
  
  # VALIDATIONS
  validates :title, presence: true
  validates :published_at, presence: true
  validates :rss_feed_id, presence: true
  
  # SCOPES
  scope :viewed, -> { where(is_viewed: true) }
  scope :unviewed, -> { where(is_viewed: false) }
  scope :recent, -> { where('published_at > ?', 1.day.ago).order(published_at: :desc) }
  scope :with_images, -> { where.not(image_url: [nil, '']) }
  
  # METHODS
  
  # Get a truncated version of the description for previews
  def short_description(limit = 150)
    return '' if description.blank?
    if description.length > limit
      # Limit is the total length including "...", so take limit-3 chars
      "#{description[0, limit - 3]}..."
    else
      description
    end
  end
  
  # Get a truncated version of the title for previews
  def short_title(limit = 100)
    return '' if title.blank?
    if title.length > limit
      # Limit is the total length including "...", so take limit-3 chars
      "#{title[0, limit - 3]}..."
    else
      title
    end
  end
  
  # Check if this post has an image
  def has_image?
    image_url.present? && image_url != ''
  end
  
  # Get the image URL or a placeholder
  def display_image_url
    return image_url if has_image?
    '/img/no_image_available.gif'
  end
  
  # Mark this post as viewed (reviewed/edited/scheduled)
  def mark_as_viewed!
    update!(is_viewed: true)
  end
  
  # Get formatted published date
  def formatted_published_at
    published_at.strftime('%B %d, %Y at %I:%M %p')
  end
  
  # Get relative time (e.g., "2 hours ago")
  def relative_published_at
    time_ago_in_words(published_at) + ' ago'
  end
  
  # Check if this post is recent (within last 7 days)
  def recent?
    published_at > 7.days.ago
  end
  
  # Get content for social media posting
  # Combines title and description in a social-friendly format
  def social_media_content
    content_parts = []
    content_parts << title if title.present?
    content_parts << short_description(200) if description.present?
    content_parts.join(' - ')
  end
  
  private
  
  # Helper method for time calculations
  def time_ago_in_words(time)
    distance = Time.current - time
    case distance
    when 0..1.minute
      'less than a minute'
    when 1.minute..59.minutes
      "#{distance.to_i / 1.minute} minutes"
    when 1.hour..23.hours
      "#{distance.to_i / 1.hour} hours"
    when 1.day..29.days
      "#{distance.to_i / 1.day} days"
    else
      "#{distance.to_i / 1.month} months"
    end
  end
end
