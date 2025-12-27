class PendingRegistration < ApplicationRecord
  # Use attr_accessor for password (not has_secure_password since we need to encrypt, not hash)
  attr_accessor :password, :password_confirmation

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :email_has_valid_domain
  validate :password_presence
  validate :password_confirmation_match
  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: %w[personal agency] }
  validates :company_name, presence: true, if: -> { account_type == 'agency' }
  validates :expires_at, presence: true

  before_validation :set_expires_at, on: :create
  before_save :encrypt_password

  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :active, -> { where('expires_at >= ?', Time.current) }

  # Custom validation to ensure email has a valid domain with TLD
  def email_has_valid_domain
    return if email.blank?
    
    parts = email.split('@')
    return if parts.length != 2
    
    domain = parts.last
    
    if domain.blank? || !domain.include?('.')
      errors.add(:email, 'must have a valid domain with top-level domain (e.g., example.com)')
      return
    end
    
    domain_parts = domain.split('.')
    
    if domain_parts.length < 2
      errors.add(:email, 'must have a valid domain with top-level domain (e.g., example.com)')
      return
    end
    
    tld = domain_parts.last
    if tld.length < 2
      errors.add(:email, 'must have a valid top-level domain (e.g., .com, .org, .io)')
    end
    
    domain_name = domain_parts[0]
    if domain_name.blank? || domain_name.length < 1
      errors.add(:email, 'must have a valid domain name')
    end
  end

  def expired?
    expires_at < Time.current
  end

  def create_user!
    # Decrypt password and create user
    decrypted_password = decrypt_password
    
    user = User.create!(
      email: email,
      name: name,
      password: decrypted_password,
      password_confirmation: decrypted_password,
      account_id: account_type == 'personal' ? 0 : nil,
      is_account_admin: account_type == 'agency',
      role: account_type == 'agency' ? 'reseller' : 'user'
    )
    
    user
  end

  private

  def set_expires_at
    self.expires_at ||= 24.hours.from_now
  end

  def password_presence
    if password.blank?
      errors.add(:password, "can't be blank")
    end
  end

  def password_confirmation_match
    if password.present? && password != password_confirmation
      errors.add(:password_confirmation, "doesn't match Password")
    end
  end

  def encrypt_password
    if password.present?
      # Use Rails encryption to encrypt password (can be decrypted)
      encryptor = ActiveSupport::MessageEncryptor.new(
        Rails.application.credentials.secret_key_base[0..31]
      )
      self.encrypted_password = encryptor.encrypt_and_sign(password)
    end
  end

  def decrypt_password
    return nil if encrypted_password.blank?
    
    begin
      encryptor = ActiveSupport::MessageEncryptor.new(
        Rails.application.credentials.secret_key_base[0..31]
      )
      encryptor.decrypt_and_verify(encrypted_password)
    rescue => e
      Rails.logger.error "Failed to decrypt password for pending registration #{id}: #{e.message}"
      nil
    end
  end
end
