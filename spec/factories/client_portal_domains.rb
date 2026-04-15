# frozen_string_literal: true

FactoryBot.define do
  factory :client_portal_domain do
    transient do
      zone { 'contentrotator.com' }
    end

    hostname { "#{SecureRandom.hex(4)}.#{zone}" }
    association :user
    account { user.account }
    branding { {} }

    after(:build) do |domain, evaluator|
      next unless domain.account

      domain.account.top_level_domain = evaluator.zone if domain.account.top_level_domain.blank?
    end
  end
end
