require 'rails_helper'

RSpec.describe PendingRegistration, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:account_type) }
    it { should validate_inclusion_of(:account_type).in_array(%w[personal agency]) }
    
    it 'validates company_name presence for agency accounts' do
      pending = build(:pending_registration, account_type: 'agency', company_name: nil)
      expect(pending).not_to be_valid
      expect(pending.errors[:company_name]).to be_present
    end

    it 'allows company_name to be nil for personal accounts' do
      pending = build(:pending_registration, account_type: 'personal', company_name: nil)
      expect(pending).to be_valid
    end

    it 'validates email format' do
      pending = build(:pending_registration, email: 'invalid-email')
      expect(pending).not_to be_valid
    end

    it 'validates email domain' do
      pending = build(:pending_registration, email: 'test@invalid')
      expect(pending).not_to be_valid
      expect(pending.errors[:email]).to include('must have a valid domain with top-level domain (e.g., example.com)')
    end

    it 'validates password presence' do
      pending = build(:pending_registration, password: nil)
      expect(pending).not_to be_valid
      expect(pending.errors[:password]).to include("can't be blank")
    end

    it 'validates password confirmation match' do
      pending = build(:pending_registration, password: 'password123', password_confirmation: 'different')
      expect(pending).not_to be_valid
      expect(pending.errors[:password_confirmation]).to include("doesn't match Password")
    end
  end

  describe 'scopes' do
    let!(:active_pending) { create(:pending_registration, expires_at: 1.hour.from_now) }
    let!(:expired_pending) { create(:pending_registration, expires_at: 1.hour.ago) }

    it 'finds active pending registrations' do
      expect(PendingRegistration.active).to include(active_pending)
      expect(PendingRegistration.active).not_to include(expired_pending)
    end

    it 'finds expired pending registrations' do
      expect(PendingRegistration.expired).to include(expired_pending)
      expect(PendingRegistration.expired).not_to include(active_pending)
    end
  end

  describe '#expired?' do
    it 'returns true for expired registrations' do
      pending = build(:pending_registration, expires_at: 1.hour.ago)
      expect(pending.expired?).to be true
    end

    it 'returns false for active registrations' do
      pending = build(:pending_registration, expires_at: 1.hour.from_now)
      expect(pending.expired?).to be false
    end
  end

  describe '#create_user!' do
    let(:pending) { create(:pending_registration, 
      email: 'newuser@example.com',
      name: 'New User',
      password: 'password123',
      password_confirmation: 'password123',
      account_type: 'personal'
    ) }

    it 'creates a user with correct attributes' do
      user = pending.create_user!
      
      expect(user).to be_persisted
      expect(user.email).to eq('newuser@example.com')
      expect(user.name).to eq('New User')
      expect(user.account_id).to eq(0)
      expect(user.is_account_admin).to be false
      expect(user.role).to eq('user')
    end

    it 'creates user with correct password' do
      user = pending.create_user!
      
      expect(user.authenticate('password123')).to eq(user)
      expect(user.authenticate('wrong_password')).to be_falsey
    end

    it 'creates agency user with correct attributes' do
      agency_pending = create(:pending_registration,
        email: 'agency@example.com',
        name: 'Agency User',
        password: 'password123',
        password_confirmation: 'password123',
        account_type: 'agency',
        company_name: 'Test Agency'
      )

      user = agency_pending.create_user!
      
      expect(user.account_id).to be_nil  # Will be set when account is created
      expect(user.is_account_admin).to be true
      expect(user.role).to eq('reseller')
    end

    it 'handles decryption errors gracefully' do
      pending.update_column(:encrypted_password, 'invalid_encrypted_data')
      
      expect {
        pending.create_user!
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'callbacks' do
    it 'sets expires_at before validation' do
      pending = build(:pending_registration, expires_at: nil)
      pending.valid?
      expect(pending.expires_at).to be_present
      expect(pending.expires_at).to be > Time.current
    end
  end

  describe 'payment-first registration flow' do
    it 'does not create user account on registration' do
      plan = create(:plan)
      
      # Simulate registration
      pending = create(:pending_registration,
        email: 'test@example.com',
        name: 'Test User',
        password: 'password123',
        password_confirmation: 'password123'
      )
      
      # User should NOT exist yet
      expect(User.find_by(email: 'test@example.com')).to be_nil
      expect(pending).to be_persisted
    end

    it 'allows same email to register again if pending registration expired' do
      # Create expired pending registration
      expired_pending = create(:pending_registration,
        email: 'test@example.com',
        expires_at: 1.hour.ago
      )
      
      # Should be able to create new pending registration with same email
      new_pending = build(:pending_registration,
        email: 'test@example.com',
        expires_at: 1.hour.from_now
      )
      
      # Expired one should be cleaned up, new one should be valid
      expect(new_pending).to be_valid
    end

    it 'prevents duplicate pending registrations for same email' do
      create(:pending_registration,
        email: 'test@example.com',
        expires_at: 1.hour.from_now
      )
      
      duplicate = build(:pending_registration,
        email: 'test@example.com',
        expires_at: 1.hour.from_now
      )
      
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end
  end
end
