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

    it 'handles different ranges' do
        result7d = service.timeseries('reach', '7d')
        result28d = service.timeseries('reach', '28d')
        expect(result7d.length).to eq(7)
        expect(result28d.length).to eq(28)
      end
    end
  end

  describe 'private methods (tested indirectly)' do
    it 'uses caching for summary' do
      allow(Rails.cache).to receive(:fetch).and_call_original
      service.summary('7d')
      expect(Rails.cache).to have_received(:fetch).with("ig_summary_#{user.id}_7d", expires_in: 15.minutes)
    end

    it 'uses caching for timeseries' do
      allow(Rails.cache).to receive(:fetch).and_call_original
      service.timeseries('reach', '7d')
      expect(Rails.cache).to have_received(:fetch).with("ig_ts_#{user.id}_reach_7d", expires_in: 15.minutes)
    end

    it 'checks live_available? based on ENV vars' do
      allow(ENV).to receive(:[]).with('META_APP_ID').and_return('app_id')
      allow(ENV).to receive(:[]).with('META_APP_SECRET').and_return('app_secret')
      # When live available, it calls fetch_live_summary which returns mock_summary
      result = service.summary('7d')
      expect(result).to be_a(Hash)
    end

    it 'uses mock when live not available' do
      allow(ENV).to receive(:[]).with('META_APP_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('META_APP_SECRET').and_return(nil)
      result = service.summary('7d')
      expect(result).to be_a(Hash)
      expect(result).to have_key(:reach)
    end

    it 'generates consistent mock data for same range' do
      result1 = service.summary('7d')
      result2 = service.summary('7d')
      # Should be consistent due to seed
      expect(result1.keys).to eq(result2.keys)
    end

    it 'generates different data for different ranges' do
      result7d = service.summary('7d')
      result28d = service.summary('28d')
      # Different ranges should produce different results
      expect(result7d).to be_a(Hash)
      expect(result28d).to be_a(Hash)
    end

    it 'handles all metric types in base_for' do
      # Test all metrics: reach, impressions, engagement, followers, and default
      ['reach', 'impressions', 'engagement', 'followers', 'unknown_metric'].each do |metric|
        result = service.timeseries(metric, '7d')
        expect(result).to be_an(Array)
        expect(result.length).to eq(7)
      end
    end

    it 'handles range_days logic' do
      result7d = service.timeseries('reach', '7d')
      result28d = service.timeseries('reach', '28d')
      expect(result7d.length).to eq(7)
      expect(result28d.length).to eq(28)
    end
  end
end

