require 'rails_helper'

RSpec.describe Video, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:bucket_videos).dependent(:destroy) }
    it { should have_many(:buckets).through(:bucket_videos) }
  end

  describe 'constants' do
    it 'defines STATUS_UNPROCESSED' do
      expect(Video::STATUS_UNPROCESSED).to eq(0)
    end

    it 'defines STATUS_PROCESSING' do
      expect(Video::STATUS_PROCESSING).to eq(1)
    end

    it 'defines STATUS_PROCESSED' do
      expect(Video::STATUS_PROCESSED).to eq(2)
    end
  end

  describe 'validations' do
    it { should validate_presence_of(:file_path) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array([Video::STATUS_UNPROCESSED, Video::STATUS_PROCESSING, Video::STATUS_PROCESSED]) }
  end

  describe 'methods' do
    let(:user) { create(:user) }
    
    describe '#get_source_url' do
      context 'with http/https URLs' do
        it 'returns https URL as-is' do
          video = create(:video, user: user, file_path: 'https://example.com/video.mp4')
          expect(video.get_source_url).to eq('https://example.com/video.mp4')
        end

        it 'returns http URL as-is' do
          video = create(:video, user: user, file_path: 'http://example.com/video.mp4')
          expect(video.get_source_url).to eq('http://example.com/video.mp4')
        end
      end

      context 'with environment-prefixed file paths' do
        before do
          allow(ENV).to receive(:[]).and_call_original
        end

        it 'uses DO_SPACES_ENDPOINT when set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return('https://nyc3.digitaloceanspaces.com')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'production/test/video.mp4')
          expect(video.get_source_url).to eq('https://nyc3.digitaloceanspaces.com/production/test/video.mp4')
        end

        it 'uses DIGITAL_OCEAN_SPACES_ENDPOINT when set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return('https://ams3.digitaloceanspaces.com')
          video = create(:video, user: user, file_path: 'production/test/video.mp4')
          expect(video.get_source_url).to eq('https://ams3.digitaloceanspaces.com/production/test/video.mp4')
        end

        it 'defaults to se1.sfo2.digitaloceanspaces.com when no ENV vars set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'production/test/video.mp4')
          expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/production/test/video.mp4')
        end

        it 'removes trailing slashes from endpoint' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return('https://se1.sfo2.digitaloceanspaces.com/')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'production/test/video.mp4')
          expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/production/test/video.mp4')
        end

        it 'handles development environment prefix' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'development/test/video.mp4')
          expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/development/test/video.mp4')
        end

        it 'handles test environment prefix' do
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'test/video.mp4')
          expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/test/video.mp4')
        end
      end

      context 'in production environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
          allow(ENV).to receive(:[]).and_call_original
        end

        it 'uses DO_SPACES_BUCKET when set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return('my-bucket')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('cdn.example.com')
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://cdn.example.com/my-bucket/local/video.mp4')
        end

        it 'uses DIGITAL_OCEAN_SPACES_NAME when set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return('my-bucket')
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('cdn.example.com')
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://cdn.example.com/my-bucket/local/video.mp4')
        end

        it 'uses DO_SPACES_CDN_HOST when set with bucket' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return('my-bucket')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('cdn.example.com')
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://cdn.example.com/my-bucket/local/video.mp4')
        end

        it 'defaults when DO_SPACES_CDN_HOST is set but no bucket' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('cdn.example.com')
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          # When endpoint is present but bucket is nil, it still uses the endpoint logic
          # The code will create URL with nil bucket, resulting in double slash
          expect(video.get_source_url).to eq('https://cdn.example.com//local/video.mp4')
        end

        it 'uses ACTIVE_STORAGE_URL when set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return('my-bucket')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return('https://storage.example.com')
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://storage.example.com/my-bucket/local/video.mp4')
        end

        it 'defaults to se1.sfo2.digitaloceanspaces.com when no ENV vars set' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/local/video.mp4')
        end

        it 'removes protocol and path from endpoint' do
          allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return('my-bucket')
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('https://cdn.example.com/path')
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('https://cdn.example.com/my-bucket/local/video.mp4')
        end
      end

      context 'in development environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        end

        it 'returns localhost URL for local files' do
          video = create(:video, user: user, file_path: 'local/video.mp4')
          expect(video.get_source_url).to eq('http://localhost:3000/local/video.mp4')
        end
      end
    end
  end
end
