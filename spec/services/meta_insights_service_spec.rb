require 'rails_helper'

RSpec.describe MetaInsightsService do
  let(:user) { create(:user, instagram_business_id: 'test_ig_id', fb_user_access_key: 'test_fb_token') }
  let(:service) { MetaInsightsService.new(user) }
  
  before do
    # Stub all HTTP requests
    stub_request(:get, /graph\.facebook\.com/).to_return(status: 200, body: '{}')
  end
  
  describe '#summary' do
    context 'when Instagram is connected' do
      it 'returns summary data' do
        result = service.summary('7d')
        expect(result).to be_a(Hash)
        expect(result).to have_key(:engagement)
        expect(result).to have_key(:followers)
      end
    end
    
    context 'when Instagram is not connected' do
      before do
        user.update(instagram_business_id: nil, fb_user_access_key: nil)
      end
      
      it 'returns mock summary data' do
        result = service.summary('7d')
        expect(result).to be_a(Hash)
        expect(result).to have_key(:engagement)
      end
    end
    
    context 'with different ranges' do
      it 'handles 7d range' do
        result = service.summary('7d')
        expect(result).to be_a(Hash)
      end
      
      it 'handles 28d range' do
        result = service.summary('28d')
        expect(result).to be_a(Hash)
      end
    end
  end
  
  describe '#timeseries' do
    context 'when Instagram is connected' do
      it 'returns timeseries data' do
        result = service.timeseries('engagement', '7d')
        expect(result).to be_an(Array)
      end
    end
    
    context 'when Instagram is not connected' do
      before do
        user.update(instagram_business_id: nil, fb_user_access_key: nil)
      end
      
      it 'returns mock timeseries data' do
        result = service.timeseries('engagement', '7d')
        expect(result).to be_an(Array)
      end
    end
    
    context 'with different metrics' do
      ['engagement', 'followers', 'new_followers'].each do |metric|
        it "handles #{metric} metric" do
          result = service.timeseries(metric, '7d')
          expect(result).to be_an(Array)
        end
      end
    end
  end
end

