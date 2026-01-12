require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on DigitalOcean Spaces (see config/storage.yml for options).
  config.active_storage.service = :digitalocean
  storage_host = ENV['ACTIVE_STORAGE_URL'].presence ||
                 ENV['DO_SPACES_CDN_HOST'].presence ||
                 ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'].presence ||
                 "https://new-social-rotation-backend-qzyk8.ondigitalocean.app"

  config.active_storage.default_url_options = { host: storage_host }

  configure_asset_host = ENV['CONFIGURE_ASSET_HOST']
  if configure_asset_host.blank? || configure_asset_host.casecmp('false') != 0
    config.asset_host = storage_host
  end

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "rebrand_social_rotation_production"

  config.action_mailer.perform_caching = false

  # Configure SMTP for email delivery
  # Set environment variables: SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD
  # For SendGrid: smtp.sendgrid.net, port 587
  # For Mailgun: smtp.mailgun.org, port 587
  # For Gmail: smtp.gmail.com, port 587
  # For cPanel: mail.yourdomain.com, port 465 (SSL) or 587 (STARTTLS)
  if ENV['SMTP_HOST'].present?
    smtp_port = ENV['SMTP_PORT']&.to_i || 587
    # Port 465 uses SSL/TLS directly, port 587 uses STARTTLS
    use_ssl = smtp_port == 465
    
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV['SMTP_HOST'],
      port: smtp_port,
      domain: ENV['SMTP_DOMAIN'] || 'socialrotation.com',
      user_name: ENV['SMTP_USERNAME'],
      password: ENV['SMTP_PASSWORD'],
      authentication: ENV['SMTP_AUTH']&.to_sym || :plain,
      enable_starttls_auto: !use_ssl && ENV['SMTP_STARTTLS'] != 'false',
      enable_ssl: use_ssl,
      openssl_verify_mode: 'none' # Some cPanel setups need this
    }
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.default_url_options = { host: ENV['FRONTEND_URL']&.gsub(/^https?:\/\//, '') || 'my.socialrotation.app', protocol: 'https' }
  else
    # Fallback to log delivery if SMTP not configured
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: 'localhost',
      port: 25
    }
    config.action_mailer.raise_delivery_errors = false
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Temporarily disabled for DigitalOcean App Platform debugging
  # TODO: Re-enable with proper configuration once routing is confirmed working
  config.hosts.clear # Allow all hosts (for debugging - NOT for production)
  
  # Allow requests from DigitalOcean App Platform (use regex for wildcard matching)
  # config.hosts << /.*\.ondigitalocean\.app$/ # Allow all DigitalOcean App Platform subdomains
  # config.hosts << /.*\.onrender\.com$/ # Allow all Render subdomains (legacy)
  # config.hosts << "localhost" if ENV['RAILS_ENV'] == 'development'
  
  # Skip DNS rebinding protection for health check endpoints and all API routes.
  # Temporarily disable all host checks for debugging
  config.host_authorization = { exclude: ->(request) { true } }
end
