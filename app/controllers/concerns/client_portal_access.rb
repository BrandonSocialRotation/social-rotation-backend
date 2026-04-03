# frozen_string_literal: true

# Enforces read-only "client portal" for agency sub-accounts (scheduled + content visibility only).
# Include this module, then register in ApplicationController *after* authenticate_user!:
#   before_action :enforce_client_portal_restrictions!
module ClientPortalAccess
  extend ActiveSupport::Concern

  private

  def enforce_client_portal_restrictions!
    return unless current_user&.client_portal_only?
    return if client_portal_allowed_request?

    render json: {
      error: 'Forbidden',
      message: 'This feature is not available for client portal accounts. Contact your agency for changes.',
      code: 'client_portal_restricted'
    }, status: :forbidden
  end

  # GET / POST / PATCH / DELETE allowed for client portal (whitelist).
  def client_portal_allowed_request?
    c = controller_path
    a = action_name

    case c
    when 'api/v1/auth'
      %w[login logout refresh forgot_password reset_password].include?(a)
    when 'api/v1/user_info'
      # Read-only for portal clients — profile changes go through the agency.
      # facebook_pages: used by dashboard Facebook page picker for analytics only.
      %w[show support facebook_pages].include?(a)
    when 'api/v1/analytics'
      %w[instagram_summary instagram_timeseries platform_analytics overall posts_count status].include?(a)
    when 'api/v1/bucket_schedules'
      %w[index show history].include?(a)
    when 'api/v1/client_portal/branding'
      %w[show]
    else
      false
    end
  end
end
