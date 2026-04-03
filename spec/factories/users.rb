FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
    timezone { "America/New_York" }
    watermark_logo { "logo.png" }
    watermark_scale { 100.0 }
    watermark_opacity { 30 }
    watermark_offset_x { 10 }
    watermark_offset_y { 10 }
    account_id { 0 }  # Super admin by default (no account)
    is_account_admin { false }
    status { 1 }
    role { 'user' }
    client_portal_only { false }
    fb_user_access_key { "fb_token_123" }
    instagram_business_id { "ig_business_123" }
    twitter_oauth_token { "twitter_token_123" }
    twitter_oauth_token_secret { "twitter_secret_123" }
    twitter_user_id { "twitter_user_123" }
    twitter_screen_name { "testuser" }
    linkedin_access_token { "linkedin_token_123" }
    linkedin_access_token_time { 1.hour.ago }
    linkedin_profile_id { "linkedin_profile_123" }
    google_refresh_token { "google_refresh_123" }
    location_id { "location_123" }
    post_to_instagram { true }
    twitter_url_oauth_token { "twitter_url_token_123" }
    twitter_url_oauth_token_secret { "twitter_url_secret_123" }
  end
end





