require 'rails_helper'

RSpec.describe OauthRequestToken, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:oauth_token) }
    it { should validate_presence_of(:request_secret) }
    it { should validate_presence_of(:user_id) }
    it { should validate_presence_of(:expires_at) }
    it { should validate_uniqueness_of(:oauth_token) }
  end

  describe '.cleanup_expired' do
    let(:user) { create(:user) }
    
    it 'deletes expired tokens' do
      expired_token = create(:oauth_request_token, user: user, expires_at: 1.day.ago)
      valid_token = create(:oauth_request_token, user: user, expires_at: 1.day.from_now)
      
      expect {
        OauthRequestToken.cleanup_expired
      }.to change { OauthRequestToken.count }.by(-1)
      
      expect(OauthRequestToken.exists?(expired_token.id)).to be false
      expect(OauthRequestToken.exists?(valid_token.id)).to be true
    end

    it 'does not delete tokens that expire exactly at current time' do
      token = create(:oauth_request_token, user: user, expires_at: Time.current)
      
      expect {
        OauthRequestToken.cleanup_expired
      }.not_to change { OauthRequestToken.count }
    end

    it 'handles no expired tokens gracefully' do
      create(:oauth_request_token, user: user, expires_at: 1.day.from_now)
      
      expect {
        OauthRequestToken.cleanup_expired
      }.not_to change { OauthRequestToken.count }
    end
  end

  describe '.find_and_delete' do
    let(:user) { create(:user) }
    
    context 'when token exists and is valid' do
      let(:token) { create(:oauth_request_token, user: user, expires_at: 1.hour.from_now) }
      
      it 'returns token data and deletes the token' do
        result = OauthRequestToken.find_and_delete(token.oauth_token)
        
        expect(result).to eq({
          token: token.oauth_token,
          secret: token.request_secret,
          user_id: token.user_id
        })
        expect(OauthRequestToken.exists?(token.id)).to be false
      end
    end

    context 'when token exists but is expired' do
      let(:token) { create(:oauth_request_token, user: user, expires_at: 1.hour.ago) }
      
      it 'deletes the token and returns nil' do
        result = OauthRequestToken.find_and_delete(token.oauth_token)
        
        expect(result).to be_nil
        expect(OauthRequestToken.exists?(token.id)).to be false
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        result = OauthRequestToken.find_and_delete('nonexistent_token')
        expect(result).to be_nil
      end
    end

    context 'when oauth_token is nil' do
      it 'returns nil' do
        result = OauthRequestToken.find_and_delete(nil)
        expect(result).to be_nil
      end
    end

    context 'when oauth_token is empty string' do
      it 'returns nil' do
        result = OauthRequestToken.find_and_delete('')
        expect(result).to be_nil
      end
    end

    context 'when an error occurs' do
      let(:token) { create(:oauth_request_token, user: user, expires_at: 1.hour.from_now) }
      
      it 'handles errors gracefully and returns nil' do
        # Mock the token to raise an error when destroyed
        allow_any_instance_of(OauthRequestToken).to receive(:destroy).and_raise(StandardError.new('Database error'))
        
        result = OauthRequestToken.find_and_delete(token.oauth_token)
        expect(result).to be_nil
      end
    end
  end
end
