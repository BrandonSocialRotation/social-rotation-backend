# frozen_string_literal: true

FactoryBot.define do
  factory :client_portal_domain do
    hostname { "#{SecureRandom.hex(4)}.example.test" }
    association :user
    account { user.account }
    branding { {} }
  end
end
