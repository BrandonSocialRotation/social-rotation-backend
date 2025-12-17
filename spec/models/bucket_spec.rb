require 'rails_helper'

RSpec.describe Bucket, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:bucket_images).dependent(:destroy) }
    it { should have_many(:bucket_schedules).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
  end

  describe 'scopes' do
    describe '.is_market' do
      it 'returns buckets with account_id 0' do
        market_bucket = create(:bucket, account_id: 0)
        regular_bucket = create(:bucket, account_id: 1)

        expect(Bucket.is_market).to include(market_bucket)
        expect(Bucket.is_market).not_to include(regular_bucket)
      end
    end
  end

  describe 'methods' do
    let(:user) { create(:user, account_id: 1) }
    let(:bucket) { create(:bucket, user: user) }

    describe '#is_market_bucket?' do
      it 'returns true when user account_id is 0' do
        user.update!(account_id: 0)
        expect(bucket.is_market_bucket?).to be true
      end

      it 'returns false when user account_id is not 0' do
        expect(bucket.is_market_bucket?).to be false
      end
    end

    describe '#is_due' do
      it 'returns nil when no bucket schedules exist' do
        expect(bucket.is_due(Time.current)).to be_nil
      end

      it 'returns nil when schedule is disabled' do
        create(:bucket_schedule, bucket: bucket, schedule: '0 0 0 0 0')
        expect(bucket.is_due(Time.current)).to be_nil
      end

      it 'returns false when user has no timezone' do
        user.update!(timezone: nil)
        create(:bucket_schedule, bucket: bucket, schedule: '0 9 * * *')
        result = bucket.is_due(Time.current)
        expect(result).to be false
      end

      it 'returns schedule when valid cron format exists' do
        # Ensure user has timezone for is_due to work
        user.update!(timezone: 'America/New_York')
        schedule = create(:bucket_schedule, bucket: bucket, schedule: '0 9 * * *')
        # Reload bucket to ensure fresh association
        bucket.reload
        # Verify schedule is in the association
        expect(bucket.bucket_schedules).to include(schedule)
        result = bucket.is_due(Time.current)
        # The method returns the first schedule with valid cron format (placeholder logic)
        # Note: This is placeholder logic - actual cron parsing would check if it's due
        expect(result).to eq(schedule)
      end


      it 'skips schedules with invalid cron format' do
        # Create with valid format first, then update to invalid to bypass validation
        schedule = create(:bucket_schedule, bucket: bucket, schedule: '0 9 * * *')
        schedule.update_column(:schedule, 'invalid cron')
        expect(bucket.is_due(Time.current)).to be_nil
      end

      it 'handles cron parsing errors gracefully' do
        user.update!(timezone: 'America/New_York')
        schedule = create(:bucket_schedule, bucket: bucket, schedule: '0 9 * * *')
        bucket.reload
        # Mock valid_cron_format? to raise an error when called
        allow_any_instance_of(BucketSchedule).to receive(:valid_cron_format?).and_raise(StandardError.new('Cron parsing error'))
        # Should return nil when error occurs (caught by rescue block, continues to next, then returns nil)
        result = bucket.is_due(Time.current)
        expect(result).to be_nil
      end
    end

    describe '#get_next_rotation_image' do
      let(:image1) { create(:image, friendly_name: 'A') }
      let(:image2) { create(:image, friendly_name: 'B') }
      let(:image3) { create(:image, friendly_name: 'C') }
      let!(:bucket_image1) { create(:bucket_image, bucket: bucket, image: image1, friendly_name: 'A') }
      let!(:bucket_image2) { create(:bucket_image, bucket: bucket, image: image2, friendly_name: 'B') }
      let!(:bucket_image3) { create(:bucket_image, bucket: bucket, image: image3, friendly_name: 'C') }

      it 'returns nil when no rotation schedules exist' do
        expect(bucket.get_next_rotation_image).to be_nil
      end

      it 'returns the first image when no previous sends' do
        create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        expect(bucket.get_next_rotation_image).to eq(bucket_image1)
      end

      it 'returns correct image with offset' do
        create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        expect(bucket.get_next_rotation_image(1)).to eq(bucket_image2)
      end

      it 'wraps around when offset exceeds image count' do
        create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        expect(bucket.get_next_rotation_image(3)).to eq(bucket_image1)
      end

      context 'with send history' do
        let!(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }

        before do
          # Create send history for first image
          create(:bucket_send_history, 
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image1,
            friendly_name: 'A',
            sent_at: 1.hour.ago
          )
        end

        it 'returns next image in rotation after last sent' do
          result = bucket.get_next_rotation_image
          expect(result).to eq(bucket_image2)
        end

        it 'wraps around to first image after last image' do
          # Create history for last image
          create(:bucket_send_history,
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image3,
            friendly_name: 'C',
            sent_at: 30.minutes.ago
          )

          result = bucket.get_next_rotation_image
          expect(result).to eq(bucket_image1)
        end

        it 'applies offset correctly' do
          result = bucket.get_next_rotation_image(1)
          expect(result).to eq(bucket_image3)
        end

        it 'handles skip_offset parameter' do
          result = bucket.get_next_rotation_image(0, 1)
          expect(result).to eq(bucket_image3)
        end

        it 'handles case when last_sent_image is not found by id' do
          # Create history with a bucket_image, then delete it to simulate not found
          history = create(:bucket_send_history,
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image2,
            friendly_name: 'B',
            sent_at: 1.hour.ago
          )
          # Delete the bucket_image to simulate it not being found by id
          bucket_image2.destroy
          # Should find next image by friendly_name
          result = bucket.get_next_rotation_image
          expect(result).to eq(bucket_image3)
        end

        it 'handles case when no image found with friendly_name > last sent' do
          # Create history with last image, then delete it and set friendly_name after all
          history = create(:bucket_send_history,
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image3,
            friendly_name: 'C',
            sent_at: 1.hour.ago
          )
          # Delete the bucket_image to simulate it not being found by id
          bucket_image3.destroy
          # Update history friendly_name to be after all existing images
          history.update_column(:friendly_name, 'Z')
          # The logic: when no image found with friendly_name > 'Z', it falls back to first image
          # last_sent_image ||= bucket_images.first, then next_index = (0 + 1) % 3 = 1
          result = bucket.get_next_rotation_image
          # After getting first image (index 0) as fallback, next in rotation is index 1 (second image)
          expect(result).to eq(bucket_image2)
        end

        it 'handles case when last_sent_image found by friendly_name lookup' do
          # Create history with friendly_name but bucket_image deleted
          history = create(:bucket_send_history,
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image2,
            friendly_name: 'B',
            sent_at: 1.hour.ago
          )
          bucket_image2.destroy
          # Should find next image after 'B' which is 'C'
          result = bucket.get_next_rotation_image
          expect(result).to eq(bucket_image3)
        end

        it 'handles case when last_sent_image is found by id' do
          # Create history with actual bucket_image
          create(:bucket_send_history,
            bucket_schedule: rotation_schedule,
            bucket_image: bucket_image2,
            friendly_name: 'B',
            sent_at: 1.hour.ago
          )
          result = bucket.get_next_rotation_image
          expect(result).to eq(bucket_image3)
        end
      end

      context 'with no images' do
        before do
          bucket.bucket_images.destroy_all
        end

        it 'returns nil when no images exist' do
          create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
          result = bucket.get_next_rotation_image
          expect(result).to be_nil
        end
      end
    end
  end
end