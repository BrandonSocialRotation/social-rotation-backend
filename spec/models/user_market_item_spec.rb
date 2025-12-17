require 'rails_helper'

RSpec.describe UserMarketItem, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:market_item) }
  end

  describe 'validations' do
    it { should validate_inclusion_of(:visible).in_array([true, false]) }
    
    it 'allows true for visible' do
      user_market_item = build(:user_market_item, visible: true)
      expect(user_market_item).to be_valid
    end

    it 'allows false for visible' do
      user_market_item = build(:user_market_item, visible: false)
      expect(user_market_item).to be_valid
    end

    it 'rejects nil for visible' do
      user_market_item = build(:user_market_item, visible: nil)
      expect(user_market_item).not_to be_valid
    end
  end
end





