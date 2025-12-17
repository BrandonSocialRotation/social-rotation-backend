require 'rails_helper'

RSpec.describe SocialMedia::GoogleService do
  let(:user) { create(:user, google_refresh_token: 'refresh_token', location_id: 'location123') }
  let(:service) { SocialMedia::GoogleService.new(user) }
  
  before do
    ENV['GOOGLE_CLIENT_ID'] = 'test_client_id'
    ENV['GOOGLE_CLIENT_SECRET'] = 'test_client_secret'
    stub_request(:post, /oauth2\.googleapis\.com/).to_return(status: 200, body: { access_token: 'token' }.to_json)
    stub_request(:post, /mybusiness\.googleapis\.com/).to_return(status: 200, body: { id: 'post123' }.to_json)
  end
  
  describe '#post_to_gmb' do
    context 'when user has Google My Business connected' do
      it 'posts to GMB successfully' do
        result = service.post_to_gmb('Test message', 'https://example.com/image.jpg')
        expect(result).to be_a(Hash)
        expect(result).to have_key('id')
      end
    end
    
    context 'when user does not have Google My Business connected' do
      before do
        user.update(google_refresh_token: nil)
      end
      
      it 'raises an error' do
        expect {
          service.post_to_gmb('Test', 'https://example.com/image.jpg')
        }.to raise_error(/does not have Google My Business connected/)
      end
    end
    
    context 'when user does not have location selected' do
      before do
        user.update(location_id: nil)
      end
      
      it 'raises an error' do
        expect {
          service.post_to_gmb('Test', 'https://example.com/image.jpg')
        }.to raise_error(/does not have a Google My Business location selected/)
      end
    end
  end
end

