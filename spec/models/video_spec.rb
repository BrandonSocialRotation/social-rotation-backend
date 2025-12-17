require 'rails_helper'

RSpec.describe Video, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:file_path) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array([Video::STATUS_UNPROCESSED, Video::STATUS_PROCESSING, Video::STATUS_PROCESSED]) }
  end

  describe 'methods' do
    let(:user) { create(:user) }
    let(:video) { create(:video, user: user, file_path: 'test/video.mp4') }
    
    before do
      # Ensure test environment uses correct default endpoint
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
      allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
    end

    describe '#get_source_url' do
      it 'generates source URL' do
        expect(video.get_source_url).to eq('https://se1.sfo2.digitaloceanspaces.com/test/video.mp4')
      end
    end
  end
end
