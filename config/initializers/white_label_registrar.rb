# frozen_string_literal: true

# Registrar zones your company owns — agencies pick one in White label settings.
# Client portal hostnames must live under the agency's selected zone (or any listed zone if none set).
# Keep in sync with social-rotation-frontend/src/pages/WhiteLabel.tsx TOP_LEVEL_DOMAIN_OPTIONS.
module WhiteLabelRegistrar
  DOMAINS = %w[
    contentrotation.com
    contentrotator.com
    postrotation.com
    postrotator.com
    secureorderforms.com
    secureorderformsdev.com
    socialrotation.app
    socialrotation.com
    socialrotation.dev
  ].freeze
end
