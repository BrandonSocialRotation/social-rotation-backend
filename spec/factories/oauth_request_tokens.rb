FactoryBot.define do
  factory :oauth_request_token do
    association :user
    oauth_token { SecureRandom.hex(32) }
    request_secret { SecureRandom.hex(32) }
    expires_at { 1.hour.from_now }
  end
end
