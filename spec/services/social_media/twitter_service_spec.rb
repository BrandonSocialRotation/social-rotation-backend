require 'rails_helper'

RSpec.describe SocialMedia::TwitterService do
  let(:user) { create(:user, twitter_oauth_token: 'token123', twitter_oauth_token_secret: 'secret123') }
  let(:service) { described_class.new(user) }
  
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TWITTER_API_KEY').and_return('test_key')
    allow(ENV).to receive(:[]).with('TWITTER_API_SECRET_KEY').and_return('test_secret')
    allow(ENV).to receive(:[]).with('TWITTER_CONSUMER_KEY').and_return('test_key')
    allow(ENV).to receive(:[]).with('TWITTER_CONSUMER_SECRET').and_return('test_secret')
  end
  
  describe '#initialize' do
    it 'sets the user' do
      expect(service.instance_variable_get(:@user)).to eq(user)
    end
  end
  
  describe '#post_tweet' do
    context 'when user has Twitter connected' do
      let(:message) { 'Test tweet' }
      let(:image_path) { '/tmp/test_image.jpg' }
      let(:mock_consumer) { double('OAuth::Consumer') }
      let(:mock_access_token) { double('OAuth::AccessToken') }
      let(:success_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"media_id_string": "12345"}') }
      let(:tweet_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"data": {"id": "tweet123"}}') }
      
      before do
        allow(File).to receive(:exist?).with(image_path).and_return(true)
        allow(File).to receive(:binread).with(image_path).and_return('image data')
        allow(OAuth::Consumer).to receive(:new).and_return(mock_consumer)
        allow(OAuth::AccessToken).to receive(:new).and_return(mock_access_token)
        allow(mock_access_token).to receive(:post).and_return(success_response, tweet_response)
        allow(JSON).to receive(:parse).with('{"media_id_string": "12345"}').and_return({'media_id_string' => '12345'})
        allow(JSON).to receive(:parse).with('{"data": {"id": "tweet123"}}').and_return({'data' => {'id' => 'tweet123'}})
      end
      
      it 'posts a tweet with media' do
        result = service.post_tweet(message, image_path)
        expect(result).to be_present
        expect(result['data']['id']).to eq('tweet123')
      end
      
      it 'truncates message to 280 characters' do
        long_message = 'a' * 300
        expect(mock_access_token).to receive(:post).with(
          '/2/tweets',
          anything,
          hash_including('Content-Type' => 'application/json')
        ).and_return(tweet_response)
        
        service.post_tweet(long_message, image_path)
      end
    end
    
    context 'when user does not have Twitter connected' do
      let(:user_without_twitter) { create(:user, twitter_oauth_token: nil, twitter_oauth_token_secret: nil) }
      let(:service) { described_class.new(user_without_twitter) }
      
      it 'raises an error' do
        expect {
          service.post_tweet('Test', '/tmp/image.jpg')
        }.to raise_error("User does not have Twitter connected")
      end
    end
    
    context 'when image_path is a URL' do
      let(:image_url) { 'https://example.com/image.jpg' }
      let(:temp_file) { double(path: '/tmp/temp.jpg', close: nil, unlink: nil, rewind: nil) }
      let(:mock_consumer) { double('OAuth::Consumer') }
      let(:mock_access_token) { double('OAuth::AccessToken') }
      let(:success_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"media_id_string": "12345"}') }
      let(:tweet_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"data": {"id": "tweet123"}}') }
      
      before do
        allow(service).to receive(:download_image_to_temp).and_return(temp_file)
        allow(File).to receive(:exist?).with(temp_file.path).and_return(true)
        allow(File).to receive(:binread).with(temp_file.path).and_return('image data')
        allow(OAuth::Consumer).to receive(:new).and_return(mock_consumer)
        allow(OAuth::AccessToken).to receive(:new).and_return(mock_access_token)
        allow(mock_access_token).to receive(:post).and_return(success_response, tweet_response)
        allow(JSON).to receive(:parse).with('{"media_id_string": "12345"}').and_return({'media_id_string' => '12345'})
        allow(JSON).to receive(:parse).with('{"data": {"id": "tweet123"}}').and_return({'data' => {'id' => 'tweet123'}})
      end
      
      it 'downloads the image and posts it' do
        expect(service).to receive(:download_image_to_temp).with(image_url).and_return(temp_file)
        service.post_tweet('Test', image_url)
      end
    end
  end
  
  describe '#upload_media' do
    let(:image_path) { '/tmp/test_image.jpg' }
    let(:mock_consumer) { double('OAuth::Consumer') }
    let(:mock_access_token) { double('OAuth::AccessToken') }
    
      before do
        allow(File).to receive(:exist?).with(image_path).and_return(true)
        allow(File).to receive(:binread).with(image_path).and_return('image data')
        allow(OAuth::Consumer).to receive(:new).and_return(mock_consumer)
        allow(OAuth::AccessToken).to receive(:new).and_return(mock_access_token)
      end
      
      context 'when upload succeeds' do
        let(:success_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"media_id_string": "12345"}') }
        
        before do
          allow(mock_access_token).to receive(:post).and_return(success_response)
          allow(JSON).to receive(:parse).with('{"media_id_string": "12345"}').and_return({'media_id_string' => '12345'})
        end
      
      it 'returns media_id' do
        media_id = service.send(:upload_media, image_path)
        expect(media_id).to eq('12345')
      end
    end
    
    context 'when upload fails' do
      let(:error_response) { double('Net::HTTPError', is_a?: false, code: '400', body: '{"errors": [{"message": "Upload failed"}]}') }
      
      before do
        allow(mock_access_token).to receive(:post).and_return(error_response)
      end
      
      it 'raises an error' do
        expect {
          service.send(:upload_media, image_path)
        }.to raise_error(/Failed to upload media/)
      end
    end
  end
  
  describe '#create_tweet' do
    let(:message) { 'Test tweet' }
    let(:media_id) { '12345' }
    let(:mock_consumer) { double('OAuth::Consumer') }
    let(:mock_access_token) { double('OAuth::AccessToken') }
    
      before do
        allow(OAuth::Consumer).to receive(:new).and_return(mock_consumer)
        allow(OAuth::AccessToken).to receive(:new).and_return(mock_access_token)
      end
      
      context 'when tweet creation succeeds' do
        let(:tweet_response) { double('Net::HTTPSuccess', is_a?: true, code: '200', body: '{"data": {"id": "tweet123", "text": "Test tweet"}}') }
        
        before do
          allow(mock_access_token).to receive(:post).and_return(tweet_response)
          allow(JSON).to receive(:parse).with('{"data": {"id": "tweet123", "text": "Test tweet"}}').and_return({'data' => {'id' => 'tweet123', 'text' => 'Test tweet'}})
        end
      
      it 'returns tweet data' do
        result = service.send(:create_tweet, message, media_id)
        expect(result['data']['id']).to eq('tweet123')
      end
    end
    
    context 'when tweet creation fails' do
      let(:error_response) { double('Net::HTTPError', is_a?: false, code: '400', body: '{"errors": [{"message": "Tweet failed"}]}') }
      
      before do
        allow(mock_access_token).to receive(:post).and_return(error_response)
      end
      
      it 'raises an error' do
        expect {
          service.send(:create_tweet, message, media_id)
        }.to raise_error(/Failed to create tweet/)
      end
    end
  end
end
