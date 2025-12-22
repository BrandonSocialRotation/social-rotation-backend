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

    context 'when image download fails' do
      before do
        bucket_image.image.update(file_path: 'https://example.com/image.jpg')
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 404, body: 'Not found')
      end
      
      it 'handles download errors gracefully' do
        service = SocialMediaPosterService.new(user, bucket_image, SocialMediaPosterService::BIT_TWITTER, 'Test')
        results = service.post_to_all
        expect(results[:twitter][:success]).to be false
        expect(results[:twitter][:error]).to be_present
      end
    end

    context 'when temp file cleanup fails' do
      before do
        user.update(twitter_oauth_token: 'token', twitter_oauth_token_secret: 'secret')
        bucket_image.image.update(file_path: 'https://example.com/image.jpg')
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
      end
      
      it 'handles cleanup errors gracefully' do
        service = SocialMediaPosterService.new(user, bucket_image, SocialMediaPosterService::BIT_TWITTER, 'Test')
        # Mock temp file to raise error on unlink
        allow_any_instance_of(Tempfile).to receive(:unlink).and_raise(StandardError.new('Cleanup error'))
        expect { service.post_to_all }.not_to raise_error
      end
    end
  end

  describe 'private methods' do
    let(:service) { SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test description') }

    describe '#should_post_to?' do
      it 'returns true when flag is set' do
        result = service.send(:should_post_to?, SocialMediaPosterService::BIT_FACEBOOK)
        expect(result).to be true
      end

      it 'returns false when flag is not set' do
        result = service.send(:should_post_to?, SocialMediaPosterService::BIT_INSTAGRAM)
        expect(result).to be false
      end
    end

    describe '#get_public_image_url' do
      it 'returns localhost URL in development' do
        allow(Rails.env).to receive(:development?).and_return(true)
        url = service.send(:get_public_image_url)
        expect(url).to include('localhost:3000')
      end

      it 'uses image get_source_url in production' do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(bucket_image.image).to receive(:get_source_url).and_return('https://example.com/image.jpg')
        url = service.send(:get_public_image_url)
        expect(url).to eq('https://example.com/image.jpg')
      end
    end

    describe '#get_local_image_path' do
      it 'returns local path for local files' do
        bucket_image.image.update(file_path: 'uploads/test.jpg')
        path = service.send(:get_local_image_path)
        expect(path).to include('uploads/test.jpg')
      end

      it 'downloads and returns temp file path for URLs' do
        bucket_image.image.update(file_path: 'https://example.com/image.jpg')
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
        path = service.send(:get_local_image_path)
        expect(path).to be_a(String)
        expect(File.exist?(path)).to be true
      end

      it 'handles http:// URLs' do
        bucket_image.image.update(file_path: 'http://example.com/image.jpg')
        stub_request(:get, 'http://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
        path = service.send(:get_local_image_path)
        expect(path).to be_a(String)
      end
    end

    describe '#download_image_to_temp' do
      it 'downloads image and creates temp file' do
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
        path = service.send(:download_image_to_temp, 'https://example.com/image.jpg')
        expect(path).to be_a(String)
        expect(File.exist?(path)).to be true
      end

      it 'handles download errors' do
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 404, body: 'Not Found')
        expect {
          service.send(:download_image_to_temp, 'https://example.com/image.jpg')
        }.to raise_error(/Failed to download image/)
      end
    end

    describe 'platform posting error handling' do
      context 'with Instagram' do
        let(:post_to_flags) { SocialMediaPosterService::BIT_INSTAGRAM }

        before do
          user.update(instagram_business_id: 'ig_id')
          stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
            .to_return(status: 200, body: { data: [{ id: 'page123', access_token: 'page_token' }] }.to_json)
        end

        it 'handles Instagram posting errors' do
          stub_request(:post, /graph\.facebook\.com\/v18\.0\/ig_id\/media/)
            .to_return(status: 400, body: { error: { message: 'Invalid media' } }.to_json)
          
          service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test')
          results = service.post_to_all
          expect(results[:instagram][:success]).to be false
          expect(results[:instagram][:error]).to be_present
        end
      end

      context 'with LinkedIn' do
        let(:post_to_flags) { SocialMediaPosterService::BIT_LINKEDIN }

        before do
          user.update(linkedin_access_token: 'token')
          image_path = Rails.root.join('public', 'test', 'image.jpg')
          FileUtils.mkdir_p(File.dirname(image_path))
          File.write(image_path, 'fake image data') unless File.exist?(image_path)
        end

        it 'handles LinkedIn posting errors' do
          stub_request(:post, /api\.linkedin\.com\/v2\/assets/)
            .to_return(status: 401, body: 'Unauthorized')
          
          service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test')
          results = service.post_to_all
          expect(results[:linkedin][:success]).to be false
          expect(results[:linkedin][:error]).to be_present
        end
      end

      context 'with Google My Business' do
        let(:post_to_flags) { SocialMediaPosterService::BIT_GMB }

        before do
          user.update(google_refresh_token: 'token', location_id: 'location123')
        end

        it 'handles GMB posting errors' do
          # Stub the Google service to raise an error
          allow_any_instance_of(SocialMedia::GoogleService).to receive(:post_to_gmb).and_raise(StandardError.new('GMB API error'))
          
          service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test')
          results = service.post_to_all
          expect(results[:gmb][:success]).to be false
          expect(results[:gmb][:error]).to be_present
        end
      end
    end

    describe '#download_image_to_temp edge cases' do
      it 'handles URI.open errors' do
        allow(URI).to receive(:open).and_raise(StandardError.new('Network error'))
        expect {
          service.send(:download_image_to_temp, 'https://example.com/image.jpg')
        }.to raise_error(/Failed to download image/)
      end

      it 'handles temp file write errors' do
        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake image data')
        temp_file_double = instance_double(Tempfile)
        allow(Tempfile).to receive(:new).and_return(temp_file_double)
        allow(temp_file_double).to receive(:binmode).and_return(temp_file_double)
        allow(temp_file_double).to receive(:write).and_raise(IOError.new('Write error'))
        allow(temp_file_double).to receive(:close)
        allow(temp_file_double).to receive(:unlink)
        expect {
          service.send(:download_image_to_temp, 'https://example.com/image.jpg')
        }.to raise_error(/Failed to download image/)
      end
    end

    describe '#get_local_image_path edge cases' do
      it 'handles nil file_path gracefully' do
        allow(bucket_image.image).to receive(:file_path).and_return(nil)
        path = service.send(:get_local_image_path)
        expect(path).to be_nil
      end

      it 'handles empty string file_path' do
        bucket_image.image.update(file_path: '')
        path = service.send(:get_local_image_path)
        expect(path).to be_a(String)
      end
    end

    describe '#post_to_all edge cases' do
      it 'handles when no platforms are selected' do
        service = SocialMediaPosterService.new(user, bucket_image, 0, 'Test')
        results = service.post_to_all
        expect(results).to be_a(Hash)
        expect(results).to be_empty
      end

      it 'continues posting to other platforms when one fails' do
        post_to_flags = SocialMediaPosterService::BIT_FACEBOOK | SocialMediaPosterService::BIT_TWITTER
        user.update!(fb_user_access_key: 'test_token', twitter_oauth_token: 'token', twitter_oauth_token_secret: 'secret')
        stub_request(:get, /graph\.facebook\.com\/v18\.0\/me\/accounts/)
          .to_return(status: 400, body: { error: { message: 'Invalid token' } }.to_json)
        image_path = Rails.root.join('public', 'test', 'image.jpg')
        FileUtils.mkdir_p(File.dirname(image_path))
        File.write(image_path, 'fake image data') unless File.exist?(image_path)
        
        service = SocialMediaPosterService.new(user, bucket_image, post_to_flags, 'Test')
        results = service.post_to_all
        expect(results).to have_key(:facebook)
        expect(results).to have_key(:twitter)
        expect(results[:facebook][:success]).to be false
      end
    end
  end
end

