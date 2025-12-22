require 'rails_helper'

RSpec.describe BucketVideo, type: :model do
  describe 'associations' do
    it { should belong_to(:bucket) }
    it { should belong_to(:video) }
  end

  describe 'validations' do
    it { should validate_presence_of(:friendly_name) }
  end

  describe 'methods' do
    let(:user) { create(:user) }
    let(:bucket) { create(:bucket, user: user) }
    let(:video) { create(:video, user: user) }
    let(:bucket_video) { create(:bucket_video, bucket: bucket, video: video) }

    describe '#forced_is_due?' do
      it 'always returns false' do
        expect(bucket_video.forced_is_due?).to be false
      end
    end

    describe '#should_display_twitter_warning?' do
      it 'returns true for long descriptions without twitter_description' do
        bucket_video.update!(description: 'A' * 300, twitter_description: nil)
        expect(bucket_video.should_display_twitter_warning?).to be true
      end

      it 'returns false for short descriptions' do
        bucket_video.update!(description: 'Short description')
        expect(bucket_video.should_display_twitter_warning?).to be false
      end

      it 'returns false when twitter_description is present' do
        bucket_video.update!(description: 'A' * 300, twitter_description: 'Twitter text')
        expect(bucket_video.should_display_twitter_warning?).to be false
      end

      it 'returns false when description is nil' do
        bucket_video.update!(description: nil, twitter_description: nil)
        expect(bucket_video.should_display_twitter_warning?).to be false
      end

      it 'returns false when description is blank' do
        bucket_video.update!(description: '', twitter_description: nil)
        expect(bucket_video.should_display_twitter_warning?).to be false
      end

      it 'returns false when description is exactly at character limit' do
        bucket_video.update!(description: 'A' * BucketSchedule::TWITTER_CHARACTER_LIMIT, twitter_description: nil)
        expect(bucket_video.should_display_twitter_warning?).to be false
      end
    end
  end
end
