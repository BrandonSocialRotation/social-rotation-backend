# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow requests from React frontend (development and production)
        origins_list = [
          "http://localhost:3001",
          "http://127.0.0.1:3001",
          "http://localhost:3002",  # Additional port if 3001 is in use
          "http://127.0.0.1:3002",
          "https://social-rotation-frontend.onrender.com",  # Old Render frontend
          "https://social-rotation-frontend.ondigitalocean.app",  # DigitalOcean frontend (generic)
          "https://social-rotation-frontend-f4mwb.ondigitalocean.app",  # Actual deployed frontend URL
          "https://my.socialrotation.app"  # Custom domain
        ]
    origins_list << ENV['FRONTEND_URL'] if ENV['FRONTEND_URL'].present?
    
    # In development, allow any localhost port
    if Rails.env.development?
      origins_list << /http:\/\/localhost:\d+/
      origins_list << /http:\/\/127\.0\.0\.1:\d+/
    end
    
    # In production, allow any DigitalOcean App Platform subdomain
    if Rails.env.production?
      origins_list << /https:\/\/.*\.ondigitalocean\.app/
    end
    
    origins origins_list

    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
