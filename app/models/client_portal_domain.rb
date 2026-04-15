# frozen_string_literal: true

# Maps a hostname (agency white-label domain) to a client user account and optional branding.
class ClientPortalDomain < ApplicationRecord
  belongs_to :user
  belongs_to :account

  validates :hostname, presence: true, uniqueness: { case_sensitive: false }
  validate :user_belongs_to_account
  validate :hostname_under_company_registrar_zone

  before_validation :normalize_hostname

  def display_name
    resolved_branding_payload[:app_name].presence ||
      branding['app_name'].presence || branding[:app_name].presence ||
      account&.name || 'Portal'
  end

  def branding_payload
    {
      app_name: branding['app_name'] || branding[:app_name],
      logo_url: branding['logo_url'] || branding[:logo_url],
      primary_color: branding['primary_color'] || branding[:primary_color],
      favicon_url: branding['favicon_url'] || branding[:favicon_url]
    }.compact
  end

  # Agency account defaults (software title, logo on admin user) merged with per-hostname JSON in branding column.
  def resolved_branding_payload
    defaults = account&.agency_default_branding_hash || {}
    domain_overrides = branding_payload
    defaults.merge(domain_overrides) { |_key, base, over| over.present? ? over : base }
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

  # Hostname must be a subdomain of the agency's selected white-label zone (from your domain pool),
  # or — if the account has no zone yet — any allowed registrar zone.
  def hostname_under_company_registrar_zone
    return if hostname.blank?

    host = hostname.to_s.downcase.strip.sub(/\Awww\./, '')
    zone = account&.top_level_domain.to_s.strip.downcase.presence
    allowed = WhiteLabelRegistrar::DOMAINS

    if zone.present?
      unless allowed.include?(zone)
        errors.add(:hostname, 'uses an account zone that is not in the approved domain pool')
        return
      end
      unless host.end_with?(".#{zone}") && host != zone
        errors.add(:hostname, "must be a subdomain of your White label domain (#{zone}), e.g. client.#{zone}")
        return
      end
      prefix = host.delete_suffix(".#{zone}")
      errors.add(:hostname, 'must include a subdomain before the zone') if prefix.blank?
    elsif allowed.none? { |z| host.end_with?(".#{z}") && host != z && host.delete_suffix(".#{z}").present? }
      errors.add(:hostname, "must be a subdomain of one of: #{allowed.join(', ')}")
    end
  end
end
