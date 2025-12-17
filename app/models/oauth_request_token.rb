class OauthRequestToken < ApplicationRecord
  belongs_to :user
  
  validates :oauth_token, presence: true, uniqueness: true
  validates :request_secret, presence: true
  validates :user_id, presence: true
  validates :expires_at, presence: true
  
  # Clean up expired tokens (call this periodically)
  def self.cleanup_expired
    where('expires_at < ?', Time.current).delete_all
  end
  
  # Find and delete a token (returns the token data if found)
  def self.find_and_delete(oauth_token)
    return nil unless oauth_token.present?
    
    token = find_by(oauth_token: oauth_token)
    return nil unless token
    
    # Check if expired
    if token.expires_at < Time.current
      token.destroy
      return nil
    end
    
    # Return token data and delete
    data = {
      token: token.oauth_token,
      secret: token.request_secret,
      user_id: token.user_id
    }
    token.destroy
    data
  rescue => e
    Rails.logger.error "Error finding/deleting OAuth request token: #{e.message}"
    nil
  end
end
