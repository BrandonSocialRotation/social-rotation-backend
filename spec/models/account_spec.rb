# Test suite for Account model
# Tests: Account associations, validations, callbacks, and custom methods
require 'rails_helper'

RSpec.describe Account, type: :model do
  # TEST: Account factory is valid
  describe 'factory' do
    it 'has a valid factory' do
      expect(create(:account)).to be_valid
    end
  end

  # TEST: Account associations are properly configured
  describe 'associations' do
    it { should have_many(:users).dependent(:nullify) }
    it { should have_one(:account_feature).dependent(:destroy) }
  end

  # TEST: Account validations work correctly
  describe 'validations' do
    it { should validate_presence_of(:name) }
    
    it 'validates uniqueness of subdomain when present' do
      account1 = create(:account, subdomain: 'test')
      account2 = build(:account, subdomain: 'test')
      expect(account2).not_to be_valid
      expect(account2.errors[:subdomain]).to be_present
    end
    
    it 'allows nil subdomain' do
      account1 = create(:account, subdomain: nil)
      account2 = build(:account, subdomain: nil)
      expect(account2).to be_valid
    end
  end

  # TEST: Callbacks create default account features
  describe 'callbacks' do
    it 'creates default account features after creation' do
      account = create(:account)
      expect(account.account_feature).to be_present
      expect(account.account_feature.max_users).to eq(50) # Updated default
    end
  end

  # TEST: #reseller? method returns correct boolean
  describe '#reseller?' do
    it 'returns true when is_reseller is true' do
      account = create(:account, is_reseller: true)
      expect(account.reseller?).to be true
    end

    it 'returns false when is_reseller is false' do
      account = create(:account, is_reseller: false)
      expect(account.reseller?).to be false
    end
  end

  # TEST: #sub_accounts returns only non-admin users
  describe '#sub_accounts' do
    let(:account) { create(:account) }
    let!(:admin1) { create(:user, account: account, is_account_admin: true) }
    let!(:sub1) { create(:user, account: account, is_account_admin: false) }
    let!(:sub2) { create(:user, account: account, is_account_admin: false) }

    it 'returns only non-admin users' do
      expect(account.sub_accounts).to contain_exactly(sub1, sub2)
      expect(account.sub_accounts).not_to include(admin1)
    end
  end

  # TEST: #admins returns only admin users
  describe '#admins' do
    let(:account) { create(:account) }
    let!(:admin1) { create(:user, account: account, is_account_admin: true) }
    let!(:admin2) { create(:user, account: account, is_account_admin: true) }
    let!(:sub1) { create(:user, account: account, is_account_admin: false) }

    it 'returns only admin users' do
      expect(account.admins).to contain_exactly(admin1, admin2)
      expect(account.admins).not_to include(sub1)
    end
  end

  # TEST: #can_add_user? checks max_users limit
  describe '#can_add_user?' do
    let(:account) { create(:account) }
    
    context 'when under max_users limit' do
      before { account.account_feature.update!(max_users: 2) }
      it 'returns true' do
        create(:user, account: account, status: 1)
        expect(account.can_add_user?).to be true
      end
    end

    context 'when at max_users limit' do
      before { account.account_feature.update!(max_users: 1) }
      it 'returns false' do
        create(:user, account: account, status: 1)
        expect(account.can_add_user?).to be false
      end
    end

    context 'when no account_feature exists' do
      before { account.account_feature.destroy }
      it 'returns true' do
        expect(account.can_add_user?).to be true
      end
    end
  end

  # TEST: #can_add_bucket? checks max_buckets limit
  describe '#can_add_bucket?' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    context 'when under max_buckets limit' do
      before { account.account_feature.update!(max_buckets: 2) }
      it 'returns true' do
        create(:bucket, user: user)
        expect(account.can_add_bucket?(user)).to be true
      end
    end

    context 'when at max_buckets limit' do
      before { account.account_feature.update!(max_buckets: 1) }
      it 'returns false' do
        create(:bucket, user: user)
        expect(account.can_add_bucket?(user)).to be false
      end
    end

    context 'when no account_feature exists' do
      before { account.account_feature.destroy }
      it 'returns true' do
        expect(account.can_add_bucket?(user)).to be true
      end
    end
  end
end