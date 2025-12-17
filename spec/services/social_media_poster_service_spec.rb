require 'rails_helper'

RSpec.describe SocialMediaPosterService do
  let(:user) { create(:user) }
  let(:bucket) { create(:bucket, user: user) }
  let(:image) { create(:image, file_path: '/test/image.jpg') }
  let(:bucket_image) { create(:bucket_image, bucket: bucket, image: image) }
  let(:post_to_flags) { SocialMediaPosterService::BIT_FACEBOOK | SocialMediaPosterService::BIT_TWITTER }
  
  before do
    stub_request(:get, /graph\.facebook\.com/).to_return(status: 200, body: '{}')
    stub_request(:post, /graph\.facebook\.com/).to_return(status: 200, body: '{"id": "123"}')
    stub_request(:get, /api\.linkedin\.com/).to_return(status: 200, body: '{}')
    stub_request(:post, /api\.linkedin\.com/).to_return(status: 200, body: '{}')
    stub_request(:get, /mybusiness\.googleapis\.com/).to_return(status: 200, body: '{}')
    stub_request(:post, /mybusiness\.googleapis\.com/).to_return(status: 200, body: '{}')
    
    # Mock OAuth for Twitter
    consumer = double('OAuth::Consumer')
    access_token = double('OAuth::AccessToken')
    allow(OAuth::Consumer).to receive(:new).and_return(consumer)
    allow(OAuth::AccessToken).to receive(:new).and_return(access_token)
    allow(access_token).to receive(:post).and_return(double(is_a?: true, code: '200', body: '{}'))
    
    ENV['TWITTER_API_KEY'] = 'test_key'
    ENV['TWITTER_API_SECRET_KEY'] = 'test_secret'
  end
  
  describe '#initialize' do
    it 'initializes with user, bucket_image, and post flags' do
      service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description')
      expect(service).to be_a(SocialMediaPosterService)
    end
    
    it 'handles facebook_page_id parameter' do
      service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test', nil, facebook_page_id: 'page123')
      expect(service).to be_a(SocialMediaPosterService)
    end
    
    it 'handles linkedin_organization_urn parameter' do
      service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test', nil, linkedin_organization_urn: 'urn:li:org:123')
      expect(service).to be_a(SocialMediaPosterService)
    end
  end
  
  describe '#post_to_all' do
    context 'with Facebook selected' do
      let(:post_to_flags) { SocialMediaPosterService::BIT_FACEBOOK }
      
      before do
        user.update(fb_user_access_key: 'test_token')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/page123\/photos/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
      end
      
      it 'posts to Facebook' do
        service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description')
        results = service.post_to_all
        expect(results).to have_key(:facebook)
        expect(results[:facebook][:success]).to be true
      end
    end
    
    context 'with Twitter selected' do
      let(:post_to_flags) { SocialMediaPosterService::BIT_TWITTER }
      
      before do
        user.update(twitter_oauth_token: 'token', twitter_oauth_token_secret: 'secret')
        image_path = Rails.root.join('public', 'test', 'image.jpg')
        FileUtils.mkdir_p(File.dirname(image_path))
        File.write(image_path, 'fake image data') unless File.exist?(image_path)
      end
      
      it 'posts to Twitter' do
        service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description')
        results = service.post_to_all
        expect(results).to have_key(:twitter)
      end
    end
    
    context 'with multiple platforms' do
      let(:post_to_flags) { SocialMediaPosterService::BIT_FACEBOOK | SocialMediaPosterService::BIT_TWITTER }
      
      before do
        user.update(fb_user_access_key: 'test_token', twitter_oauth_token: 'token', twitter_oauth_token_secret: 'secret')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        stub_request(:post, /graph\.facebook\.com\/v18\.0\/page123\/photos/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
      end
      
      it 'posts to all selected platforms' do
        service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description')
        results = service.post_to_all
        expect(results).to have_key(:facebook)
        expect(results).to have_key(:twitter)
      end
    end
    
    context 'with image URL' do
      before do
        bucket_image.image.update(file_path: 'https://example.com/image.jpg')
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
      end
      
      it 'downloads image and posts it' do
        service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description')
        # Should not raise error
        expect { service.post_to_all }.not_to raise_error
      end
    end
  end
end

