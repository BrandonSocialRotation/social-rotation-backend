# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientPortalDomain, type: :model do
  let(:account) { create(:account, is_reseller: true, top_level_domain: 'contentrotator.com') }
  let!(:subscription) { create(:subscription, account: account) }
  let(:client) do
    create(:user,
           account: account,
           account_id: account.id,
           is_account_admin: false,
           role: 'sub_account',
           client_portal_only: true)
  end

  it 'is valid for a subdomain of the account zone' do
    d = build(:client_portal_domain, user: client, account: account, hostname: 'acme.contentrotator.com')
    expect(d).to be_valid
  end

  it 'rejects a hostname outside the account zone' do
    d = build(:client_portal_domain, user: client, account: account, hostname: 'acme.postrotator.com')
    expect(d).not_to be_valid
    expect(d.errors[:hostname].join).to include('White label domain')
  end

  it 'rejects apex-only hostname' do
    d = build(:client_portal_domain, user: client, account: account, hostname: 'contentrotator.com')
    expect(d).not_to be_valid
  end
end
