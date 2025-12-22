require 'rails_helper'

RSpec.describe JsonWebToken, type: :service do
  describe '.encode' do
    it 'encodes a payload into a JWT token' do
      payload = { user_id: 1 }
      token = JsonWebToken.encode(payload)
      
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3) # JWT has 3 parts
    end

    it 'includes expiration time in payload' do
      payload = { user_id: 1 }
      exp = 1.hour.from_now
      token = JsonWebToken.encode(payload, exp)
      
      decoded = JsonWebToken.decode(token)
      expect(decoded[:exp]).to eq(exp.to_i)
    end

    it 'uses default expiration of 24 hours' do
      payload = { user_id: 1 }
      token = JsonWebToken.encode(payload)
      
      decoded = JsonWebToken.decode(token)
      expect(decoded[:exp]).to be > Time.now.to_i
      expect(decoded[:exp]).to be < 25.hours.from_now.to_i
    end
  end

  describe '.decode' do
    it 'decodes a valid JWT token' do
      payload = { user_id: 1, name: 'Test User' }
      token = JsonWebToken.encode(payload)
      
      decoded = JsonWebToken.decode(token)
      expect(decoded[:user_id]).to eq(1)
      expect(decoded[:name]).to eq('Test User')
    end

    it 'returns HashWithIndifferentAccess' do
      payload = { user_id: 1 }
      token = JsonWebToken.encode(payload)
      
      decoded = JsonWebToken.decode(token)
      expect(decoded).to be_a(HashWithIndifferentAccess)
      expect(decoded['user_id']).to eq(1)
      expect(decoded[:user_id]).to eq(1)
    end

    it 'returns nil for invalid token' do
      invalid_token = 'invalid.token.here'
      
      result = JsonWebToken.decode(invalid_token)
      expect(result).to be_nil
    end

    it 'returns nil for expired token' do
      payload = { user_id: 1 }
      exp = 1.hour.ago
      token = JsonWebToken.encode(payload, exp)
      
      result = JsonWebToken.decode(token)
      expect(result).to be_nil
    end

    it 'returns nil for malformed token' do
      result = JsonWebToken.decode('not.a.valid.jwt')
      expect(result).to be_nil
    end

    it 'returns nil for empty string' do
      result = JsonWebToken.decode('')
      expect(result).to be_nil
    end
  end
end
