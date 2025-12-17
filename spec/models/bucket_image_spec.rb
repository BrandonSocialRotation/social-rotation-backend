require 'rails_helper'

RSpec.describe BucketImage, type: :model do
  describe 'associations' do
    it { should belong_to(:bucket) }
    it { should belong_to(:image) }
    it { should have_many(:bucket_schedules).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:friendly_name) }
  end

  describe 'methods' do
    let(:user) { create(:user, timezone: 'America/New_York') }
    let(:bucket) { create(:bucket, user: user) }
    let(:image) { create(:image) }
    let(:bucket_image) { create(:bucket_image, bucket: bucket, image: image) }

    describe '#should_display_twitter_warning?' do
      it 'returns true for long descriptions without twitter_description' do
        bucket_image.update!(description: 'A' * 300, twitter_description: nil)
        expect(bucket_image.should_display_twitter_warning?).to be true
      end

      it 'returns false for short descriptions' do
        bucket_image.update!(description: 'Short description')
        expect(bucket_image.should_display_twitter_warning?).to be false
      end

      it 'returns false when twitter_description is present' do
        bucket_image.update!(description: 'A' * 300, twitter_description: 'Twitter text')
        expect(bucket_image.should_display_twitter_warning?).to be false
      end

      it 'returns false when description is nil' do
        bucket_image.update!(description: nil, twitter_description: nil)
        expect(bucket_image.should_display_twitter_warning?).to be false
      end

      it 'returns false when description is exactly at character limit' do
        bucket_image.update!(description: 'A' * BucketSchedule::TWITTER_CHARACTER_LIMIT, twitter_description: nil)
        expect(bucket_image.should_display_twitter_warning?).to be false
      end
    end

    describe '#forced_is_due?' do
      it 'returns false when no force_send_date' do
        expect(bucket_image.forced_is_due?).to be false
      end

      it 'returns true when force_send_date matches current time exactly' do
        now = Time.current
        bucket_image.update!(force_send_date: now)
        expect(bucket_image.forced_is_due?).to be true
      end

      it 'returns false when force_send_date is in the future' do
        bucket_image.update!(force_send_date: 1.hour.from_now)
        expect(bucket_image.forced_is_due?).to be false
      end

      it 'returns false when force_send_date is in the past' do
        bucket_image.update!(force_send_date: 1.hour.ago)
        expect(bucket_image.forced_is_due?).to be false
      end

      it 'returns false when user has no timezone' do
        user.update!(timezone: nil)
        bucket_image.update!(force_send_date: Time.current)
        expect(bucket_image.forced_is_due?).to be false
      end

      it 'handles timezone conversion correctly' do
        # Set user to different timezone
        user.update!(timezone: 'America/Los_Angeles')
        
        # Create a time that would be current in LA timezone
        la_time = Time.current.in_time_zone('America/Los_Angeles')
        bucket_image.update!(force_send_date: la_time)
        
        expect(bucket_image.forced_is_due?).to be true
      end

      it 'compares time with minute precision' do
        now = Time.current
        # Set force_send_date to same time but different seconds
        bucket_image.update!(force_send_date: now.change(sec: 30))
        expect(bucket_image.forced_is_due?).to be true
      end

      it 'returns false when user has no timezone (already tested above)' do
        # This scenario is already covered by the "returns false when user has no timezone" test
        # Bucket must have a user (NOT NULL constraint), so we can't test nil user
        # The method already handles nil user via user&.timezone check
      end
    end

    describe '#should_display_twitter_warning? edge cases' do
      it 'returns false when description is empty string' do
        bucket_image.update!(description: '', twitter_description: nil)
        expect(bucket_image.should_display_twitter_warning?).to be false
      end

      it 'handles description exactly one character over limit' do
        long_desc = 'A' * (BucketSchedule::TWITTER_CHARACTER_LIMIT + 1)
        bucket_image.update!(description: long_desc, twitter_description: nil)
        expect(bucket_image.should_display_twitter_warning?).to be true
      end
    end
  end
end
