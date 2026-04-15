# frozen_string_literal: true

# Public endpoint: branding for a hostname (login page / white-label shell). No auth.
class Api::V1::ClientPortal::BrandingController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :require_active_subscription!, only: [:show]

  # GET /api/v1/client_portal/branding?hostname=client.example.com
  def show
    host = params[:hostname].presence || request.host
    normalized = normalize_host(host)
    domain = ClientPortalDomain.find_by('LOWER(hostname) = ?', normalized)

    return render json: { error: 'Not found' }, status: :not_found unless domain

    render json: {
      hostname: domain.hostname,
      branding: domain.resolved_branding_payload,
      app_name: domain.display_name
    }
  end

  private

  def normalize_host(host)
    host.to_s.downcase.strip.sub(/\Awww\./, '')
  end
end
