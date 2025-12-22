# Test suite for AccountFeature model
# Tests: associations, validations, default values
require 'rails_helper'

RSpec.describe AccountFeature, type: :model do
  # Test: AccountFeature factory creates a valid record
  describe 'factory' do
    it 'has a valid factory' do
      account_feature = build(:account_feature)
      expect(account_feature).to be_valid
    end
  end

  # Test: AccountFeature associations
  describe 'associations' do
    it { should belong_to(:account) }
  end

  # Test: AccountFeature validations
  describe 'validations' do
    it { should validate_presence_of(:account) }
    it { should validate_numericality_of(:max_users).is_greater_than(0) }
    it { should validate_numericality_of(:max_buckets).is_greater_than(0) }
    it { should validate_numericality_of(:max_images_per_bucket).is_greater_than(0) }
  end

  # Test: Default values are set correctly
  describe 'default values' do
    let(:account) { create(:account) }
    let(:account_feature) { account.account_feature }

    it 'sets default max_users to 50' do
      expect(account_feature.max_users).to eq(50)
    end

    it 'sets default max_buckets to 100' do
      expect(account_feature.max_buckets).to eq(100)
    end

    it 'sets default max_images_per_bucket to 1000' do
      expect(account_feature.max_images_per_bucket).to eq(1000)
    end

    it 'enables marketplace by default' do
      expect(account_feature.allow_marketplace).to be true
    end

    it 'enables RSS by default' do
      expect(account_feature.allow_rss).to be true
    end

    it 'enables integrations by default' do
      expect(account_feature.allow_integrations).to be true
    end

    it 'enables watermark by default' do
      expect(account_feature.allow_watermark).to be true
    end
  end

  # Test: Invalid numeric values are rejected
  describe 'numeric validations' do
    let(:account) { create(:account) }

    it 'rejects zero max_users' do
      account_feature = build(:account_feature, account: account, max_users: 0)
      expect(account_feature).not_to be_valid
      expect(account_feature.errors[:max_users]).to be_present
    end

    it 'rejects negative max_buckets' do
      account_feature = build(:account_feature, account: account, max_buckets: -1)
      expect(account_feature).not_to be_valid
      expect(account_feature.errors[:max_buckets]).to be_present
    end

    it 'rejects zero max_images_per_bucket' do
      account_feature = build(:account_feature, account: account, max_images_per_bucket: 0)
      expect(account_feature).not_to be_valid
      expect(account_feature.errors[:max_images_per_bucket]).to be_present
    end
  end

  describe '#effective_max_users' do
    let(:account) { create(:account) }
    let(:plan) { create(:plan, max_users: 20) }

    it 'returns plan max_users when plan exists' do
      account.update!(plan: plan)
      expect(account.account_feature.effective_max_users).to eq(20)
    end

    it 'returns account_feature max_users when no plan' do
      account.account_feature.update!(max_users: 50)
      expect(account.account_feature.effective_max_users).to eq(50)
    end
  end

  describe '#effective_max_buckets' do
    let(:account) { create(:account) }
    let(:plan) { create(:plan, max_buckets: 30) }

    it 'returns plan max_buckets when plan exists' do
      account.update!(plan: plan)
      expect(account.account_feature.effective_max_buckets).to eq(30)
    end

    it 'returns account_feature max_buckets when no plan' do
      account.account_feature.update!(max_buckets: 100)
      expect(account.account_feature.effective_max_buckets).to eq(100)
    end
  end

  describe '#effective_max_images_per_bucket' do
    let(:account) { create(:account) }
    let(:plan) { create(:plan, max_images_per_bucket: 500) }

    it 'returns plan max_images_per_bucket when plan exists' do
      account.update!(plan: plan)
      expect(account.account_feature.effective_max_images_per_bucket).to eq(500)
    end

    it 'returns account_feature max_images_per_bucket when no plan' do
      account.account_feature.update!(max_images_per_bucket: 1000)
      expect(account.account_feature.effective_max_images_per_bucket).to eq(1000)
    end
  end

  describe 'apply_plan_limits callback' do
    let(:plan) { create(:plan, max_users: 25, max_buckets: 50, max_images_per_bucket: 500, features: '{"marketplace": true, "rss": false}') }
    let(:account) { create(:account, plan: plan) }

    it 'applies plan limits to new account_feature' do
      feature = account.account_feature
      expect(feature.max_users).to eq(25)
      expect(feature.max_buckets).to eq(50)
      expect(feature.max_images_per_bucket).to eq(500)
    end

    it 'applies plan features to new account_feature' do
      feature = account.account_feature
      expect(feature.allow_marketplace).to be true
      expect(feature.allow_rss).to be false
    end

    it 'defaults RSS to true when not in plan features' do
      plan.update!(features: '{"marketplace": true}')
      account = create(:account, plan: plan)
      expect(account.account_feature.allow_rss).to be true
    end

    it 'handles plan with nil max_users' do
      plan.update!(max_users: nil)
      account.update!(plan: plan)
      new_feature = AccountFeature.new(account: account)
      # Should use default from set_defaults (50)
      expect(new_feature.max_users).to eq(50)
    end

    it 'handles plan with nil max_buckets' do
      # Use update_column to bypass validations
      plan.update_column(:max_buckets, nil)
      account.update!(plan: plan)
      new_feature = AccountFeature.new(account: account)
      # Should use default from set_defaults (100)
      expect(new_feature.max_buckets).to eq(100)
    end

    it 'handles plan features without marketplace key' do
      plan.update!(features: '{"rss": true}')
      account.update!(plan: plan)
      new_feature = AccountFeature.new(account: account)
      # Should use default (true) since marketplace key is not present
      expect(new_feature.allow_marketplace).to be true
    end

    it 'handles plan features with marketplace explicitly false' do
      plan.update!(features: '{"marketplace": false}')
      account.update!(plan: plan)
      new_feature = AccountFeature.new(account: account)
      expect(new_feature.allow_marketplace).to be false
    end
  end
end
