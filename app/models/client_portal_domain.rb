# frozen_string_literal: true

# Maps a hostname (agency white-label domain) to a client user account and optional branding.
class ClientPortalDomain < ApplicationRecord
  belongs_to :user
  belongs_to :account

  validates :hostname, presence: true, uniqueness: { case_sensitive: false }
  validate :user_belongs_to_account

  before_validation :normalize_hostname

  def display_name
    branding['app_name'].presence || branding[:app_name].presence || account&.name || 'Portal'
  end

  def branding_payload
    {
      app_name: branding['app_name'] || branding[:app_name],
      logo_url: branding['logo_url'] || branding[:logo_url],
      primary_color: branding['primary_color'] || branding[:primary_color],
      favicon_url: branding['favicon_url'] || branding[:favicon_url]
    }.compact
  end

  private

  def normalize_hostname
    self.hostname = hostname.to_s.downcase.strip.sub(/\Awww\./, '')
  end

  def user_belongs_to_account
    return if user_id.blank? || account_id.blank?
    return if user&.account_id == account_id

    errors.add(:user, 'must belong to the same account')
  end
end
