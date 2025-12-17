require 'rails_helper'

RSpec.describe Plan, type: :model do
  describe 'associations' do
    it { should have_many(:subscriptions).dependent(:restrict_with_error) }
    it { should have_many(:accounts).dependent(:nullify) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:plan_type) }
    it { should validate_inclusion_of(:plan_type).in_array(%w[personal agency location_based user_seat_based]) }
    it { should validate_numericality_of(:price_cents).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:max_buckets).is_greater_than(0) }
    it { should validate_numericality_of(:max_images_per_bucket).is_greater_than(0) }

    context 'when plan_type is location_based' do
      let(:plan) { build(:plan, plan_type: 'location_based', max_locations: nil) }
      
      it 'requires max_locations' do
        plan.valid?
        expect(plan.errors[:max_locations]).to be_present
      end

      it 'requires max_locations to be greater than 0' do
        plan.max_locations = 0
        plan.valid?
        expect(plan.errors[:max_locations]).to be_present
      end
    end

    context 'when plan_type is user_seat_based' do
      let(:plan) { build(:plan, plan_type: 'user_seat_based', max_users: nil) }
      
      it 'requires max_users' do
        plan.valid?
        expect(plan.errors[:max_users]).to be_present
      end

      it 'requires max_users to be greater than 0' do
        plan.max_users = 0
        plan.valid?
        expect(plan.errors[:max_users]).to be_present
      end
    end

    context 'when plan_type is agency' do
      let(:plan) { build(:plan, plan_type: 'agency', max_users: nil) }
      
      it 'requires max_users' do
        plan.valid?
        expect(plan.errors[:max_users]).to be_present
      end
    end
  end

  describe 'scopes' do
    let!(:active_plan) { create(:plan, status: true) }
    let!(:inactive_plan) { create(:plan, status: false) }
    let!(:personal_plan) { create(:plan, plan_type: 'personal') }
    let!(:agency_plan) { create(:plan, plan_type: 'agency') }
    let!(:location_plan) { create(:plan, plan_type: 'location_based') }
    let!(:user_seat_plan) { create(:plan, plan_type: 'user_seat_based') }

    it '.active returns only active plans' do
      expect(Plan.active).to include(active_plan)
      expect(Plan.active).not_to include(inactive_plan)
    end

    it '.personal returns only personal plans' do
      expect(Plan.personal).to include(personal_plan)
      expect(Plan.personal).not_to include(agency_plan)
    end

    it '.agency returns only agency plans' do
      expect(Plan.agency).to include(agency_plan)
      expect(Plan.agency).not_to include(personal_plan)
    end

    it '.location_based returns only location-based plans' do
      expect(Plan.location_based).to include(location_plan)
      expect(Plan.location_based).not_to include(user_seat_plan)
    end

    it '.user_seat_based returns only user-seat-based plans' do
      expect(Plan.user_seat_based).to include(user_seat_plan)
      expect(Plan.user_seat_based).not_to include(location_plan)
    end

    it '.ordered orders by sort_order and price_cents' do
      plan1 = create(:plan, sort_order: 1, price_cents: 1000)
      plan2 = create(:plan, sort_order: 1, price_cents: 2000)
      plan3 = create(:plan, sort_order: 2, price_cents: 500)
      
      ordered = Plan.ordered
      expect(ordered.index(plan1)).to be < ordered.index(plan2)
      expect(ordered.index(plan2)).to be < ordered.index(plan3)
    end
  end

  describe '#features_hash' do
    context 'when features is valid JSON' do
      let(:plan) { create(:plan, features: '{"feature1": true, "feature2": false}') }
      
      it 'returns parsed hash' do
        expect(plan.features_hash).to eq({ 'feature1' => true, 'feature2' => false })
      end
    end

    context 'when features is blank' do
      let(:plan) { create(:plan, features: nil) }
      
      it 'returns empty hash' do
        expect(plan.features_hash).to eq({})
      end
    end

    context 'when features is invalid JSON' do
      let(:plan) { create(:plan, features: 'invalid json') }
      
      it 'returns empty hash' do
        expect(plan.features_hash).to eq({})
      end
    end
  end

  describe '#features_hash=' do
    let(:plan) { build(:plan) }
    
    it 'sets features as JSON string' do
      plan.features_hash = { 'feature1' => true }
      expect(plan.features).to eq('{"feature1":true}')
    end
  end

  describe '#feature_enabled?' do
    let(:plan) { create(:plan, features: '{"feature1": true, "feature2": false}') }
    
    it 'returns true for enabled feature' do
      expect(plan.feature_enabled?(:feature1)).to be true
      expect(plan.feature_enabled?('feature1')).to be true
    end

    it 'returns false for disabled feature' do
      expect(plan.feature_enabled?(:feature2)).to be false
    end

    it 'returns false for non-existent feature' do
      expect(plan.feature_enabled?(:feature3)).to be false
    end
  end

  describe '#price_dollars' do
    let(:plan) { create(:plan, price_cents: 2999) }
    
    it 'converts cents to dollars' do
      expect(plan.price_dollars).to eq(29.99)
    end
  end

  describe '#formatted_price' do
    let(:plan) { create(:plan, price_cents: 2999) }
    
    it 'formats price as currency string' do
      expect(plan.formatted_price).to eq('$29.99')
    end
  end

  describe '#calculate_price_for_users' do
    context 'when plan does not support per-user pricing' do
      let(:plan) { create(:plan, price_cents: 5000) }
      
      it 'returns base price_cents' do
        expect(plan.calculate_price_for_users(5)).to eq(5000)
      end
    end

    context 'when plan supports per-user pricing' do
      let(:plan) do
        create(:plan,
          supports_per_user_pricing: true,
          base_price_cents: 2000,
          per_user_price_cents: 500,
          per_user_price_after_10_cents: 300
        )
      end

      it 'returns base price for 1 user' do
        expect(plan.calculate_price_for_users(1)).to eq(2000)
      end

      it 'calculates price for 5 users (1 base + 4 additional)' do
        # Base: 2000, Additional: 4 * 500 = 2000, Total: 4000
        expect(plan.calculate_price_for_users(5)).to eq(4000)
      end

      it 'calculates price for 15 users (1 base + 10 at regular + 4 at discounted)' do
        # Base: 2000, First 10: 10 * 500 = 5000, Next 4: 4 * 300 = 1200, Total: 8200
        expect(plan.calculate_price_for_users(15)).to eq(8200)
      end

      it 'applies annual discount (10/12)' do
        monthly = plan.calculate_price_for_users(5, 'monthly')
        annual = plan.calculate_price_for_users(5, 'annual')
        expect(annual).to eq((monthly * 10.0 / 12.0).round)
      end
    end
  end

  describe '#formatted_price_for_users' do
    let(:plan) do
      create(:plan,
        supports_per_user_pricing: true,
        base_price_cents: 2000,
        per_user_price_cents: 500
      )
    end

    it 'formats monthly price' do
      result = plan.formatted_price_for_users(5, 'monthly')
      expect(result).to match(/\$[\d.]+\/month/)
    end

    it 'formats annual price' do
      result = plan.formatted_price_for_users(5, 'annual')
      expect(result).to match(/\$[\d.]+\/year/)
    end
  end

  describe '#display_name' do
    context 'when plan does not support per-user pricing' do
      let(:plan) { create(:plan, name: 'Basic', price_cents: 5000) }
      
      it 'returns name with monthly price' do
        expect(plan.display_name).to eq('Basic - $50.00/month')
      end
    end

    context 'when plan supports per-user pricing' do
      let(:plan) do
        create(:plan,
          name: 'Pro',
          supports_per_user_pricing: true,
          base_price_cents: 2000,
          billing_period: 'monthly'
        )
      end
      
      it 'returns name with starting price for monthly' do
        expect(plan.display_name).to match(/Pro - Starting at \$[\d.]+\/month/)
      end

      context 'with annual billing' do
        let(:plan) do
          create(:plan,
            name: 'Pro',
            supports_per_user_pricing: true,
            base_price_cents: 2000,
            billing_period: 'annual'
          )
        end
        
        it 'returns name with starting price for year' do
          expect(plan.display_name).to match(/Pro - Starting at \$[\d.]+\/year/)
        end
      end
    end
  end

  describe 'type check methods' do
    let(:personal_plan) { create(:plan, plan_type: 'personal') }
    let(:agency_plan) { create(:plan, plan_type: 'agency') }
    let(:location_plan) { create(:plan, plan_type: 'location_based') }
    let(:user_seat_plan) { create(:plan, plan_type: 'user_seat_based') }

    it '#personal? returns true for personal plans' do
      expect(personal_plan.personal?).to be true
      expect(agency_plan.personal?).to be false
    end

    it '#agency? returns true for agency plans' do
      expect(agency_plan.agency?).to be true
      expect(personal_plan.agency?).to be false
    end

    it '#location_based? returns true for location-based plans' do
      expect(location_plan.location_based?).to be true
      expect(user_seat_plan.location_based?).to be false
    end

    it '#user_seat_based? returns true for user-seat-based plans' do
      expect(user_seat_plan.user_seat_based?).to be true
      expect(location_plan.user_seat_based?).to be false
    end
  end
end
