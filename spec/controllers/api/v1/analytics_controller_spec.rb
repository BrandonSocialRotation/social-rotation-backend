require 'rails_helper'

RSpec.describe Api::V1::AnalyticsController, type: :controller do
  let(:user) { create(:user, instagram_business_id: 'ig_business_123') }
  let(:token) { JsonWebToken.encode(user_id: user.id) }
  let(:mock_service) { instance_double(MetaInsightsService) }
  
  before do
    request.headers['Authorization'] = "Bearer #{token}"
    allow(controller).to receive(:current_user).and_return(user)
    allow(MetaInsightsService).to receive(:new).with(user).and_return(mock_service)
  end
  
  describe 'GET #instagram_summary' do
    context 'with default range' do
      it 'returns summary data' do
        allow(mock_service).to receive(:summary).with('7d').and_return({
          impressions: 1000,
          reach: 800,
          engagement: 50
        })
        
        get :instagram_summary
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['range']).to eq('7d')
        expect(json_response['metrics']).to be_present
      end
    end
    
    context 'with custom range' do
      it 'returns summary data for specified range' do
        allow(mock_service).to receive(:summary).with('30d').and_return({
          impressions: 5000,
          reach: 4000,
          engagement: 250
        })
        
        get :instagram_summary, params: { range: '30d' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['range']).to eq('30d')
        expect(json_response['metrics']).to be_present
      end
    end
  end
  
  describe 'GET #instagram_timeseries' do
    context 'with default parameters' do
      it 'returns timeseries data' do
        allow(mock_service).to receive(:timeseries).with('reach', '28d').and_return([
          { date: '2024-01-01', value: 100 },
          { date: '2024-01-02', value: 150 }
        ])
        
        get :instagram_timeseries
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['metric']).to eq('reach')
        expect(json_response['range']).to eq('28d')
        expect(json_response['points']).to be_an(Array)
      end
    end
    
    context 'with custom parameters' do
      it 'returns timeseries data for specified metric and range' do
        allow(mock_service).to receive(:timeseries).with('impressions', '7d').and_return([
          { date: '2024-01-01', value: 200 },
          { date: '2024-01-02', value: 250 }
        ])
        
        get :instagram_timeseries, params: { metric: 'impressions', range: '7d' }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['metric']).to eq('impressions')
        expect(json_response['range']).to eq('7d')
        expect(json_response['points']).to be_an(Array)
      end
    end
  end
end
