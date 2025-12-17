require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:plan) }
  end

  describe 'validations' do
    let(:account) { create(:account) }
    let(:plan) { create(:plan) }
    
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:stripe_customer_id) }
    
    it 'validates uniqueness of stripe_subscription_id when present' do
      create(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_123')
      duplicate = build(:subscription, account: account, plan: plan, stripe_subscription_id: 'sub_123')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:stripe_subscription_id]).to be_present
    end
    
    it 'allows nil stripe_subscription_id' do
      subscription = build(:subscription, account: account, plan: plan, stripe_subscription_id: nil)
      expect(subscription).to be_valid
    end

    context 'when stripe_subscription_id is nil' do
      let(:subscription) { build(:subscription, stripe_subscription_id: nil) }
      
      it 'is valid' do
        expect(subscription).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_sub) { create(:subscription, status: Subscription::STATUS_ACTIVE) }
    let!(:trialing_sub) { create(:subscription, status: Subscription::STATUS_TRIALING) }
    let!(:canceled_sub) { create(:subscription, status: Subscription::STATUS_CANCELED) }
    let!(:past_due_sub) { create(:subscription, status: Subscription::STATUS_PAST_DUE) }

    it '.active returns active and trialing subscriptions' do
      expect(Subscription.active).to include(active_sub)
      expect(Subscription.active).to include(trialing_sub)
      expect(Subscription.active).not_to include(canceled_sub)
    end

    it '.trialing returns only trialing subscriptions' do
      expect(Subscription.trialing).to include(trialing_sub)
      expect(Subscription.trialing).not_to include(active_sub)
    end

    it '.canceled returns only canceled subscriptions' do
      expect(Subscription.canceled).to include(canceled_sub)
      expect(Subscription.canceled).not_to include(active_sub)
    end

    it '.past_due returns only past_due subscriptions' do
      expect(Subscription.past_due).to include(past_due_sub)
      expect(Subscription.past_due).not_to include(active_sub)
    end
  end

  describe '#active?' do
    it 'returns true for active status' do
      subscription = create(:subscription, status: Subscription::STATUS_ACTIVE)
      expect(subscription.active?).to be true
    end

    it 'returns true for trialing status' do
      subscription = create(:subscription, status: Subscription::STATUS_TRIALING)
      expect(subscription.active?).to be true
    end

    it 'returns false for canceled status' do
      subscription = create(:subscription, status: Subscription::STATUS_CANCELED)
      expect(subscription.active?).to be false
    end

    it 'returns false for past_due status' do
      subscription = create(:subscription, status: Subscription::STATUS_PAST_DUE)
      expect(subscription.active?).to be false
    end
  end

  describe '#canceled?' do
    it 'returns true for canceled status' do
      subscription = create(:subscription, status: Subscription::STATUS_CANCELED)
      expect(subscription.canceled?).to be true
    end

    it 'returns false for active status' do
      subscription = create(:subscription, status: Subscription::STATUS_ACTIVE)
      expect(subscription.canceled?).to be false
    end
  end

  describe '#past_due?' do
    it 'returns true for past_due status' do
      subscription = create(:subscription, status: Subscription::STATUS_PAST_DUE)
      expect(subscription.past_due?).to be true
    end

    it 'returns false for active status' do
      subscription = create(:subscription, status: Subscription::STATUS_ACTIVE)
      expect(subscription.past_due?).to be false
    end
  end

  describe '#trialing?' do
    it 'returns true for trialing status' do
      subscription = create(:subscription, status: Subscription::STATUS_TRIALING)
      expect(subscription.trialing?).to be true
    end

    it 'returns false for active status' do
      subscription = create(:subscription, status: Subscription::STATUS_ACTIVE)
      expect(subscription.trialing?).to be false
    end
  end

  describe '#will_cancel?' do
    it 'returns true when cancel_at_period_end is true and subscription is active' do
      subscription = create(:subscription,
        status: Subscription::STATUS_ACTIVE,
        cancel_at_period_end: true
      )
      expect(subscription.will_cancel?).to be true
    end

    it 'returns false when cancel_at_period_end is false' do
      subscription = create(:subscription,
        status: Subscription::STATUS_ACTIVE,
        cancel_at_period_end: false
      )
      expect(subscription.will_cancel?).to be false
    end

    it 'returns false when subscription is not active' do
      subscription = create(:subscription,
        status: Subscription::STATUS_CANCELED,
        cancel_at_period_end: true
      )
      expect(subscription.will_cancel?).to be false
    end
  end

  describe '#days_remaining' do
    context 'when current_period_end is in the future' do
      let(:subscription) do
        create(:subscription,
          current_period_end: 5.days.from_now
        )
      end
      
      it 'returns days remaining' do
        expect(subscription.days_remaining).to be_between(4, 5)
      end
    end

    context 'when current_period_end is in the past' do
      let(:subscription) do
        create(:subscription,
          current_period_end: 5.days.ago
        )
      end
      
      it 'returns 0' do
        expect(subscription.days_remaining).to eq(0)
      end
    end

    context 'when current_period_end is nil' do
      let(:subscription) { create(:subscription, current_period_end: nil) }
      
      it 'returns 0' do
        expect(subscription.days_remaining).to eq(0)
      end
    end

    context 'when current_period_end is exactly now' do
      let(:subscription) do
        create(:subscription,
          current_period_end: Time.current
        )
      end
      
      it 'returns 0' do
        expect(subscription.days_remaining).to eq(0)
      end
    end
  end

  describe '#expired?' do
    context 'when current_period_end is in the past and not active' do
      let(:subscription) do
        create(:subscription,
          status: Subscription::STATUS_CANCELED,
          current_period_end: 5.days.ago
        )
      end
      
      it 'returns true' do
        expect(subscription.expired?).to be true
      end
    end

    context 'when current_period_end is in the past but subscription is active' do
      let(:subscription) do
        create(:subscription,
          status: Subscription::STATUS_ACTIVE,
          current_period_end: 5.days.ago
        )
      end
      
      it 'returns false' do
        expect(subscription.expired?).to be false
      end
    end

    context 'when current_period_end is in the future' do
      let(:subscription) do
        create(:subscription,
          status: Subscription::STATUS_CANCELED,
          current_period_end: 5.days.from_now
        )
      end
      
      it 'returns false' do
        expect(subscription.expired?).to be false
      end
    end

    context 'when current_period_end is nil' do
      let(:subscription) do
        create(:subscription,
          status: Subscription::STATUS_CANCELED,
          current_period_end: nil
        )
      end
      
      it 'returns false' do
        expect(subscription.expired?).to be false
      end
    end
  end
end
