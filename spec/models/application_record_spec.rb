# Test suite for ApplicationRecord
# Tests: Base ActiveRecord class configuration
require 'rails_helper'

RSpec.describe ApplicationRecord, type: :model do
  # Test: ApplicationRecord is configured as primary abstract class
  describe 'configuration' do
    it 'is configured as primary abstract class' do
      # In Rails 7+, ApplicationRecord is the primary abstract class
      expect(ApplicationRecord.abstract_class?).to be true
    end

    it 'inherits from ActiveRecord::Base' do
      expect(ApplicationRecord.superclass).to eq(ActiveRecord::Base)
    end
  end

  # Test: ApplicationRecord cannot be instantiated directly
  describe 'instantiation' do
    it 'cannot be instantiated directly' do
      expect { ApplicationRecord.new }.to raise_error(NotImplementedError)
    end
  end
end
