# frozen_string_literal: true

# Be sure to restart your server when you modify this file.
#
# Avoid CORS issues when API is called from the React frontend (dev + production).
# White-label: agencies use custom hostnames (e.g. https://subaccount.contentrotator.com).
# Add every public frontend origin that should call this API:
#   ALLOWED_FRONTEND_ORIGINS — comma-separated, e.g.
#     https://app.agency1.com,https://portal.agency2.com,https://sub.client.com
#   FRONTEND_URL — optional; can be one URL or comma-separated (same format).
# Production still allows any https://*.ondigitalocean.app for default DO app URLs.

# Read more: https://github.com/cyu/rack-cors

module CorsOrigins
  module_function

  def from_env(*keys)
    keys.flat_map { |key| split_origins(ENV[key]) }.uniq
  end

  def split_origins(raw)
    return [] if raw.blank?

    raw.to_s.split(',').filter_map do |piece|
      o = piece.to_s.strip.sub(%r{/+\z}, '')
      o.presence
    end
  end
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins_list = [
      'http://localhost:3001',
      'http://127.0.0.1:3001',
      'http://localhost:3002', # Additional port if 3001 is in use
      'http://127.0.0.1:3002',
      'https://social-rotation-frontend.onrender.com', # Old Render frontend
      'https://social-rotation-frontend.ondigitalocean.app', # DigitalOcean frontend (generic)
      'https://social-rotation-frontend-f4mwb.ondigitalocean.app', # Actual deployed frontend URL
      'https://my.socialrotation.app' # Custom domain
    ]

    origins_list.concat(CorsOrigins.from_env('FRONTEND_URL', 'ALLOWED_FRONTEND_ORIGINS'))

    # In development, allow any localhost port
    if Rails.env.development?
      origins_list << %r{\Ahttp://localhost:\d+\z}
      origins_list << %r{\Ahttp://127\.0\.0\.1:\d+\z}
    end

    # In production, allow any DigitalOcean App Platform subdomain
    if Rails.env.production?
      origins_list << %r{\Ahttps://.*\.ondigitalocean\.app\z}
      # Any subdomain under registrar pool zones (wildcard DNS + App domains) — no per-client env entry.
      WhiteLabelRegistrar::DOMAINS.each do |zone|
        origins_list << /\Ahttps:\/\/[^\/]+\.#{Regexp.escape(zone)}\z/
      end
    end

    origins origins_list

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: true
  end
end
