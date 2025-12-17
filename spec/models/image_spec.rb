require 'rails_helper'

RSpec.describe Image, type: :model do
  describe 'associations' do
    it { should have_many(:bucket_images).dependent(:destroy) }
    it { should have_many(:buckets).through(:bucket_images) }
  end

  describe 'validations' do
    it { should validate_presence_of(:file_path) }
  end

  describe 'methods' do
    describe '#get_source_url' do
      context 'with environment-prefixed file paths' do
        before do
          allow(ENV).to receive(:[]).and_call_original
        end

        it 'uses ACTIVE_STORAGE_URL when set' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return('https://cdn.example.com')
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://cdn.example.com/production/test/image.jpg')
        end

        it 'uses DO_SPACES_CDN_HOST when set' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return('https://cdn.digitalocean.com')
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://cdn.digitalocean.com/production/test/image.jpg')
        end

        it 'uses DIGITAL_OCEAN_SPACES_ENDPOINT when set' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return('https://nyc3.digitaloceanspaces.com')
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://nyc3.digitaloceanspaces.com/production/test/image.jpg')
        end

        it 'uses DO_SPACES_ENDPOINT when set' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return('https://ams3.digitaloceanspaces.com')
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://ams3.digitaloceanspaces.com/production/test/image.jpg')
        end

        it 'defaults to se1.sfo2.digitaloceanspaces.com when no ENV vars set' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/production/test/image.jpg')
        end

        it 'removes trailing slashes from endpoint' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return('https://se1.sfo2.digitaloceanspaces.com/')
          image = create(:image, file_path: 'production/test/image.jpg')
          expect(image.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/production/test/image.jpg')
        end

        it 'handles development environment prefix' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          image = create(:image, file_path: 'development/test/image.jpg')
          expect(image.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/development/test/image.jpg')
        end

        it 'handles test environment prefix' do
          allow(ENV).to receive(:[]).with('ACTIVE_STORAGE_URL').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_CDN_HOST').and_return(nil)
          allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
          allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
          image = create(:image, file_path: 'test/image.jpg')
          expect(image.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/test/image.jpg')
        end
      end

      context 'with http/https URLs' do
        it 'returns the URL as-is' do
          image = create(:image, file_path: 'https://example.com/image.jpg')
          expect(image.get_source_url).to eq('https://example.com/image.jpg')
        end

        it 'returns http URL as-is' do
          image = create(:image, file_path: 'http://example.com/image.jpg')
          expect(image.get_source_url).to eq('http://example.com/image.jpg')
        end
      end

      context 'with placeholder paths' do
        it 'returns placeholder URL' do
          image = create(:image, file_path: 'placeholder/test.jpg')
          expect(image.get_source_url).to eq('https://via.placeholder.com/400x300/cccccc/666666?text=Image+Upload+Disabled')
        end
      end

      context 'with local file paths' do
        it 'returns local path in development' do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
          image = create(:image, file_path: 'local/image.jpg')
          expect(image.get_source_url).to eq('/local/image.jpg')
        end

        it 'returns local path in test' do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
          image = create(:image, file_path: 'local/image.jpg')
          expect(image.get_source_url).to eq('/local/image.jpg')
        end

        it 'returns placeholder URL in production' do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
          image = create(:image, file_path: 'local/image.jpg')
          expect(image.get_source_url).to eq('https://via.placeholder.com/400x300/cccccc/666666?text=Image+Upload+Disabled')
        end
      end
    end
  end
end
