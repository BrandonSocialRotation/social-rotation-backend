FactoryBot.define do
  factory :pending_registration do
    email { "test#{SecureRandom.hex(4)}@example.com" }
    name { "Test User" }
    password { "password123" }
    password_confirmation { "password123" }
    account_type { "personal" }
    company_name { nil }
    expires_at { 24.hours.from_now }
    stripe_session_id { "cs_test_#{SecureRandom.hex(8)}" }
  end

  factory :pending_registration_agency, parent: :pending_registration do
    account_type { "agency" }
    company_name { "Test Agency" }
  end
end
