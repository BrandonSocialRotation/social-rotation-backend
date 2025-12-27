require 'rails_helper'

# User Model Tests
# Validates: associations, validations, password security, and watermark path generation
RSpec.describe User, type: :model do
  
  # TEST: User associations are properly configured
  # Verify user has many buckets and videos, both destroy on user deletion
  describe 'associations' do
    # Should belong to account (optional)
    it { should belong_to(:account).optional }
    # Should have many buckets that are destroyed when user is deleted
    it { should have_many(:buckets).dependent(:destroy) }
    # Should have many videos that are destroyed when user is deleted
    it { should have_many(:videos).dependent(:destroy) }
  end

  # TEST: User validations work correctly
  # Verify email and name are required, email is unique
  describe 'validations' do
    # Email field must be present
    it { should validate_presence_of(:email) }
    # Name field must be present
    it { should validate_presence_of(:name) }
    # Email must be unique across all users
    it { should validate_uniqueness_of(:email) }

    # TEST: Email domain validation
    describe 'email domain validation' do
      it 'accepts valid email with proper domain and TLD' do
        user = build(:user, email: 'test@example.com')
        expect(user).to be_valid
      end

      it 'accepts email with subdomain' do
        user = build(:user, email: 'test@mail.example.com')
        expect(user).to be_valid
      end

      it 'accepts email with different TLDs' do
        user = build(:user, email: 'test@example.org')
        expect(user).to be_valid
        user.email = 'test@example.io'
        expect(user).to be_valid
        user.email = 'test@example.co.uk'
        expect(user).to be_valid
      end

      it 'rejects email without domain' do
        user = build(:user, email: 'test@')
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include('must have a valid domain with top-level domain (e.g., example.com)')
      end

      it 'rejects email without TLD' do
        user = build(:user, email: 'test@example')
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include('must have a valid domain with top-level domain (e.g., example.com)')
      end

      it 'rejects email with single character TLD' do
        user = build(:user, email: 'test@example.c')
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include('must have a valid top-level domain (e.g., .com, .org, .io)')
      end

      it 'rejects email with empty domain name' do
        user = build(:user, email: 'test@.com')
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include('must have a valid domain name')
      end

      it 'rejects email with multiple @ symbols' do
        user = build(:user, email: 'test@@example.com')
        # This is caught by URI::MailTo::EMAIL_REGEXP format validation first
        expect(user).not_to be_valid
      end
    end
  end

  # TEST: Password authentication using bcrypt
  # Verify user can set password and authenticate correctly
  describe 'password security' do
    # Test: Create user with password, verify authentication works
    # Should authenticate with correct password, reject incorrect password
    it 'has secure password' do
      # Create new user with email and name
      user = User.new(email: 'test@example.com', name: 'Test User')
      # Set password and confirmation (required by has_secure_password)
      user.password = 'password123'
      user.password_confirmation = 'password123'
      user.save!

      # Correct password should return the user object
      expect(user.authenticate('password123')).to eq(user)
      # Wrong password should return false
      expect(user.authenticate('wrong_password')).to be_falsey
    end
  end

  # TEST: Watermark path generation methods
  # Verify all watermark path methods generate correct URLs/paths
  describe 'watermark methods' do
    # Create test user with watermark logo
    let(:user) { create(:user, watermark_logo: 'test_logo.png') }

    # Test: All watermark path methods generate valid paths with correct structure
    it 'generates watermark paths correctly' do
      # Preview path should be standard URL
      expect(user.get_watermark_preview).to eq('/user/standard_preview')
      # Digital Ocean path should include CDN URL
      expect(user.get_digital_ocean_watermark_path).to include('se1.sfo2.digitaloceanspaces.com')
      # Local storage path should include /storage/ directory
      expect(user.get_watermark_logo).to include('/storage/')
    end

    # Test: When watermark logo is nil, methods return empty strings
    # Prevents errors when user hasn't uploaded a watermark
    it 'handles missing watermark logo' do
      # Remove watermark logo
      user.watermark_logo = nil
      # Should return empty string for Digital Ocean path
      expect(user.get_digital_ocean_watermark_path).to eq('')
      # Should return empty string for local storage path
      expect(user.get_watermark_logo).to eq('')
    end
  end

  # TEST: Reseller and account admin methods
  # Verify role-based methods return correct values
  describe 'account/reseller methods' do
    # Test: super_admin? returns true when account_id is 0
    describe '#super_admin?' do
      it 'returns true when account_id is 0' do
        user = create(:user, account_id: 0)
        expect(user.super_admin?).to be true
      end

      it 'returns false when account_id is not 0' do
        user = create(:user, account_id: 1)
        expect(user.super_admin?).to be false
      end
    end

    # Test: account_admin? returns value of is_account_admin
    describe '#account_admin?' do
      it 'returns true when is_account_admin is true' do
        user = create(:user, is_account_admin: true)
        expect(user.account_admin?).to be true
      end

      it 'returns false when is_account_admin is false' do
        user = create(:user, is_account_admin: false)
        expect(user.account_admin?).to be false
      end
    end

    # Test: reseller? returns true only when user is admin of reseller account
    describe '#reseller?' do
      it 'returns true when user is admin of reseller account' do
        account = create(:account, is_reseller: true)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.reseller?).to be true
      end

      it 'returns false when user is not an admin' do
        account = create(:account, is_reseller: true)
        user = create(:user, account: account, is_account_admin: false)
        expect(user.reseller?).to be false
      end

      it 'returns false when account is not a reseller' do
        account = create(:account, is_reseller: false)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.reseller?).to be false
      end

      it 'returns false when user has no account' do
        user = create(:user, account: nil, is_account_admin: true)
        expect(user.reseller?).to be false
      end
    end

    # Test: can_access_marketplace? checks super_admin or account feature
    describe '#can_access_marketplace?' do
      it 'returns true for super admin' do
        user = create(:user, account_id: 0)
        expect(user.can_access_marketplace?).to be true
      end

      it 'returns true when account feature allows marketplace' do
        account = create(:account)
        account.account_feature.update!(allow_marketplace: true)
        user = create(:user, account: account)
        expect(user.can_access_marketplace?).to be true
      end

      it 'returns false when account feature disallows marketplace' do
        account = create(:account)
        account.account_feature.update!(allow_marketplace: false)
        user = create(:user, account: account)
        expect(user.can_access_marketplace?).to be false
      end
    end

    # Test: can_create_marketplace_item? checks super_admin or reseller
    describe '#can_create_marketplace_item?' do
      it 'returns true for super admin' do
        user = create(:user, account_id: 0)
        expect(user.can_create_marketplace_item?).to be true
      end

      it 'returns true for reseller' do
        account = create(:account, is_reseller: true)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.can_create_marketplace_item?).to be true
      end

      it 'returns false for regular user' do
        account = create(:account, is_reseller: false)
        user = create(:user, account: account, is_account_admin: false)
        expect(user.can_create_marketplace_item?).to be false
      end
    end

    # Test: can_create_sub_account? checks reseller status
    describe '#can_create_sub_account?' do
      it 'returns true for reseller' do
        account = create(:account, is_reseller: true)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.can_create_sub_account?).to be true
      end

      it 'returns false for non-reseller' do
        account = create(:account, is_reseller: false)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.can_create_sub_account?).to be false
      end
    end

    # Test: account_users returns users in same account
    describe '#account_users' do
      let(:account) { create(:account) }
      let!(:user1) { create(:user, account: account) }
      let!(:user2) { create(:user, account: account) }
      let!(:other_user) { create(:user, account: create(:account)) }

      it 'returns all users in the same account' do
        expect(user1.account_users).to contain_exactly(user1, user2)
        expect(user1.account_users).not_to include(other_user)
      end

      it 'returns empty relation when account_id is 0' do
        user = create(:user, account_id: 0)
        expect(user.account_users).to be_empty
      end
    end

    # Test: active scope returns only active users
    describe '.active scope' do
      let!(:active_user) { create(:user, status: 1) }
      let!(:inactive_user) { create(:user, status: 0) }

      it 'returns only users with status 1' do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user)
      end
    end

    # Test: watermark path methods
    describe 'watermark path methods' do
      let(:user) { create(:user, watermark_logo: 'test_logo.png') }

      describe '#get_watermark_preview' do
        it 'returns standard preview path' do
          expect(user.get_watermark_preview).to eq('/user/standard_preview')
        end
      end

      describe '#get_relative_digital_ocean_watermark_path' do
        it 'returns correct relative path' do
          expected_path = "#{Rails.env}/#{user.id}/watermarks/test_logo.png"
          expect(user.get_relative_digital_ocean_watermark_path).to eq(expected_path)
        end
      end

      describe '#get_digital_ocean_watermark_path' do
        it 'returns full CDN URL when watermark exists' do
          expected_url = "https://se1.sfo2.digitaloceanspaces.com/#{Rails.env}/#{user.id}/watermarks/test_logo.png"
          expect(user.get_digital_ocean_watermark_path).to eq(expected_url)
        end

        it 'returns empty string when no watermark' do
          user.update!(watermark_logo: nil)
          expect(user.get_digital_ocean_watermark_path).to eq('')
        end
      end

      describe '#get_watermark_logo' do
        it 'returns local storage path when watermark exists' do
          expected_path = "/storage/#{Rails.env}/#{user.id}/watermarks/test_logo.png"
          expect(user.get_watermark_logo).to eq(expected_path)
        end

        it 'returns empty string when no watermark' do
          user.update!(watermark_logo: nil)
          expect(user.get_watermark_logo).to eq('')
        end
      end

      describe '#get_absolute_watermark_logo_directory' do
        it 'returns absolute directory path when watermark exists' do
          expected_path = Rails.root.join("public/storage/#{Rails.env}/#{user.id}").to_s
          expect(user.get_absolute_watermark_logo_directory).to eq(expected_path)
        end

        it 'returns empty string when no watermark' do
          user.update!(watermark_logo: nil)
          expect(user.get_absolute_watermark_logo_directory).to eq('')
        end
      end

      describe '#get_absolute_watermark_scaled_logo_directory' do
        it 'returns scaled directory path when watermark exists' do
          expected_path = Rails.root.join("public/storage/#{Rails.env}/#{user.id}/watermarks_scaled").to_s
          expect(user.get_absolute_watermark_scaled_logo_directory).to eq(expected_path)
        end

        it 'returns empty string when no watermark' do
          user.update!(watermark_logo: nil)
          expect(user.get_absolute_watermark_scaled_logo_directory).to eq('')
        end
      end

      describe '#get_absolute_watermark_logo_path' do
        it 'returns absolute file path when watermark exists' do
          expected_path = Rails.root.join("public/storage/#{Rails.env}/#{user.id}/watermarks/test_logo.png").to_s
          expect(user.get_absolute_watermark_logo_path).to eq(expected_path)
        end

        it 'returns empty string when no watermark' do
          user.update!(watermark_logo: nil)
          expect(user.get_absolute_watermark_logo_path).to eq('')
        end
      end
    end

    describe '#can_manage_rss_feeds?' do
      it 'returns true for super admin' do
        user = create(:user, account_id: 0)
        expect(user.can_manage_rss_feeds?).to be true
      end

      it 'returns true for reseller' do
        account = create(:account, is_reseller: true)
        user = create(:user, account: account, is_account_admin: true)
        expect(user.can_manage_rss_feeds?).to be true
      end

      it 'returns false for regular user' do
        account = create(:account, is_reseller: false)
        user = create(:user, account: account, is_account_admin: false)
        expect(user.can_manage_rss_feeds?).to be false
      end
    end

    describe '#can_access_rss_feeds?' do
      it 'returns true for super admin' do
        user = create(:user, account_id: 0)
        expect(user.can_access_rss_feeds?).to be true
      end

      it 'returns true when account feature allows RSS' do
        account = create(:account)
        account.account_feature.update!(allow_rss: true)
        user = create(:user, account: account)
        expect(user.can_access_rss_feeds?).to be true
      end

      it 'returns false when account feature disallows RSS' do
        account = create(:account)
        account.account_feature.update!(allow_rss: false)
        user = create(:user, account: account)
        expect(user.can_access_rss_feeds?).to be false
      end

      it 'returns true when account_id is nil' do
        user = create(:user, account_id: nil)
        expect(user.can_access_rss_feeds?).to be true
      end

      it 'returns false when account exists but account_feature is nil' do
        account = create(:account)
        account.account_feature.destroy
        # Ensure account_id is not 0 (super admin) and not nil
        user = create(:user, account: account)
        user.update_column(:account_id, account.id) # Use update_column to bypass callbacks
        user.reload
        # Ensure user is not a super admin
        expect(user.account_id).not_to eq(0)
        expect(user.account_id).not_to be_nil
        # When account_feature is nil, the safe navigation returns nil, so it falls back to account_id.nil? check
        # But account exists, so it should return false
        expect(user.can_access_rss_feeds?).to be false
      end
    end
  end
end