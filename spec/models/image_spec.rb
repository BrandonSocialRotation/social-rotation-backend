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
    let(:image) { create(:image, file_path: 'test/image.jpg') }
    
    before do
      # Ensure test environment doesn't have ENV vars that would override
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
      allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
      allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return(nil)
      allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
    end

    describe '#get_source_url' do
      it 'generates source URL' do
        expect(image.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/test/image.jpg')
      end
    end
  end
end
