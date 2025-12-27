require 'rails_helper'

RSpec.describe BucketSchedule, type: :model do
  describe 'constants' do
    it 'has correct schedule type constants' do
      expect(BucketSchedule::SCHEDULE_TYPE_ROTATION).to eq(1)
      expect(BucketSchedule::SCHEDULE_TYPE_ONCE).to eq(2)
      expect(BucketSchedule::SCHEDULE_TYPE_ANNUALLY).to eq(3)
    end

    it 'has correct social media bit flags' do
      expect(BucketSchedule::BIT_FACEBOOK).to eq(1)
      expect(BucketSchedule::BIT_TWITTER).to eq(2)
      expect(BucketSchedule::BIT_INSTAGRAM).to eq(4)
      expect(BucketSchedule::BIT_LINKEDIN).to eq(8)
      expect(BucketSchedule::BIT_GMB).to eq(16)
    end
  end

  describe 'associations' do
    it { should belong_to(:bucket) }
    it { should belong_to(:bucket_image).optional }
    it { should have_many(:bucket_send_histories).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:schedule) }
    it { should validate_presence_of(:schedule_type) }
    it { should validate_inclusion_of(:schedule_type).in_array([BucketSchedule::SCHEDULE_TYPE_ROTATION, BucketSchedule::SCHEDULE_TYPE_ONCE, BucketSchedule::SCHEDULE_TYPE_ANNUALLY]) }
    
    it 'validates cron format' do
      valid_schedule = create(:bucket_schedule, schedule: '0 9 * * 1-5')
      expect(valid_schedule).to be_valid
      
      invalid_schedule = build(:bucket_schedule, schedule: 'invalid cron')
      expect(invalid_schedule).not_to be_valid
      expect(invalid_schedule.errors[:schedule]).to include(/must have exactly 5 space-separated parts/)
    end
  end

  describe 'methods' do
    let(:user) { create(:user, timezone: 'America/New_York') }
    let(:bucket) { create(:bucket, user: user) }
    let(:bucket_image) { create(:bucket_image, bucket: bucket) }
    let(:bucket_schedule) { create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image) }

    describe '#get_type_image' do
      it 'returns correct image for rotation type' do
        bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        expect(bucket_schedule.get_type_image).to eq('rotation.png')
      end

      it 'returns correct image for once type' do
        bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE)
        expect(bucket_schedule.get_type_image).to eq('post_once.png')
      end

      it 'returns correct image for annually type' do
        bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
        expect(bucket_schedule.get_type_image).to eq('annual.png')
      end
    end

    describe '#can_send?' do
      it 'returns true for schedules without history' do
        expect(bucket_schedule.can_send?).to be true
      end

      it 'returns true for rotation schedules regardless of history' do
        bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        create(:bucket_send_history, bucket_schedule: bucket_schedule, sent_at: 1.minute.ago)
        expect(bucket_schedule.can_send?).to be true
      end

      it 'returns true for once schedules without history' do
        bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE)
        expect(bucket_schedule.can_send?).to be true
      end

      context 'for annually schedules' do
        before do
          bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
        end

        it 'returns true when no history exists' do
          expect(bucket_schedule.can_send?).to be true
        end

        it 'returns true when last sent was over a year ago' do
          create(:bucket_send_history, bucket_schedule: bucket_schedule, sent_at: 1.year.ago - 1.day)
          expect(bucket_schedule.can_send?).to be true
        end

        it 'returns false when last sent was less than a year ago' do
          create(:bucket_send_history, bucket_schedule: bucket_schedule, sent_at: 6.months.ago)
          expect(bucket_schedule.can_send?).to be false
        end
      end
    end

    describe '#is_network_selected?' do
      it 'returns true for selected networks' do
        bucket_schedule.update!(post_to: BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER)
        expect(bucket_schedule.is_network_selected?(BucketSchedule::BIT_FACEBOOK)).to be true
        expect(bucket_schedule.is_network_selected?(BucketSchedule::BIT_TWITTER)).to be true
        expect(bucket_schedule.is_network_selected?(BucketSchedule::BIT_LINKEDIN)).to be false
      end
    end

    describe '#get_posts_to_images' do
      it 'returns correct image states for selected platforms' do
        bucket_schedule.update!(post_to: BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER)
        result = bucket_schedule.get_posts_to_images

        expect(result['Facebook']).to eq('facebook_on.png')
        expect(result['Twitter']).to eq('twitter_on.png')
        expect(result['LinkedIn']).to eq('linkedin_off.png')
      end
    end

    describe '#get_days_selected' do
      it 'returns days from cron expression' do
        bucket_schedule.update!(schedule: '0 9 * * 1,3,5')
        expect(bucket_schedule.get_days_selected).to eq(['1', '3', '5'])
      end

      it 'returns empty array for invalid schedule' do
        bucket_schedule.schedule = nil
        expect(bucket_schedule.get_days_selected).to eq([])
      end
    end

    describe '#is_day_selected?' do
      it 'returns true for selected days' do
        bucket_schedule.update!(schedule: '0 9 * * 1,3,5')
        expect(bucket_schedule.is_day_selected?(1)).to be true
        expect(bucket_schedule.is_day_selected?(3)).to be true
        expect(bucket_schedule.is_day_selected?(2)).to be false
      end

      it 'returns true for wildcard days' do
        bucket_schedule.update!(schedule: '0 9 * * *')
        expect(bucket_schedule.is_day_selected?(1)).to be true
        expect(bucket_schedule.is_day_selected?(7)).to be true
      end
    end

    describe '#get_time_format' do
      it 'returns time from cron expression' do
        bucket_schedule.update!(schedule: '30 14 * * *')
        expect(bucket_schedule.get_time_format).to eq('14:30')
      end

      it 'returns default time for wildcard schedule' do
        bucket_schedule.update!(schedule: '* * * * *')
        expect(bucket_schedule.get_time_format).to eq('12:00')
      end
    end

    describe '#get_next_bucket_image_due' do
      it 'returns bucket_image for once and annually schedules' do
        once_schedule = create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image, schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE)
        expect(once_schedule.get_next_bucket_image_due).to eq(bucket_image)

        annual_schedule = create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image, schedule_type: BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
        expect(annual_schedule.get_next_bucket_image_due).to eq(bucket_image)
      end
    end

    describe '#get_time_format' do
      it 'returns time from cron schedule' do
        bucket_schedule.update!(schedule: '30 14 * * *')
        expect(bucket_schedule.get_time_format).to eq('14:30')
      end

      it 'returns default time for wildcard schedule' do
        bucket_schedule.update!(schedule: '* * * * *')
        expect(bucket_schedule.get_time_format).to eq(BucketSchedule::DEFAULT_TIME)
      end

      it 'returns default time for invalid schedule' do
        bucket_schedule.update_column(:schedule, 'invalid') # Skip validation
        expect(bucket_schedule.get_time_format).to eq(BucketSchedule::DEFAULT_TIME)
      end
    end

    describe '#get_scheduled_date_format' do
      it 'returns date from cron schedule' do
        bucket_schedule.update!(schedule: '0 9 15 12 *')
        expected_date = "#{Date.current.year}-12-15"
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end

      it 'returns current date for wildcard schedule' do
        bucket_schedule.update!(schedule: '0 9 * * *')
        expected_date = Date.current.strftime('%Y-%m-%d')
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end

      it 'returns current date for invalid schedule' do
        bucket_schedule.update_column(:schedule, 'invalid') # Skip validation
        expected_date = Date.current.strftime('%Y-%m-%d')
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end
    end

    describe '#get_next_description_due' do
      context 'with once or annually schedule' do
        before do
          bucket_schedule.update!(
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
            description: 'Schedule description',
            twitter_description: 'Twitter description'
          )
        end

        it 'returns schedule description for regular text' do
          result = bucket_schedule.get_next_description_due
          expect(result).to eq('Schedule description')
        end

        it 'returns schedule twitter description for twitter text' do
          result = bucket_schedule.get_next_description_due(0, 0, true)
          expect(result).to eq('Twitter description')
        end

        it 'falls back to bucket_image description when schedule description is empty' do
          bucket_schedule.update!(description: '')
          bucket_image.update!(description: 'Image description')
          result = bucket_schedule.get_next_description_due
          expect(result).to eq('Image description')
        end
      end

      context 'with rotation schedule' do
        before do
          bucket_schedule.update!(schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION)
        end

        it 'returns bucket_image description for rotation' do
          bucket_image.update!(description: 'Image description')
          result = bucket_schedule.get_next_description_due
          expect(result).to eq('Image description')
        end

        it 'returns empty string when no bucket_image' do
          bucket_schedule.update!(bucket_image: nil)
          # Ensure bucket has no images for this test
          bucket_schedule.bucket.bucket_images.destroy_all
          result = bucket_schedule.get_next_description_due
          expect(result).to eq('')
        end
      end
    end

    describe 'self.get_network_hash' do
      it 'returns correct network hash' do
        hash = BucketSchedule.get_network_hash
        expect(hash[BucketSchedule::BIT_FACEBOOK]).to eq('facebook_on.png')
        expect(hash[BucketSchedule::BIT_TWITTER]).to eq('twitter_on.png')
        expect(hash[BucketSchedule::BIT_LINKEDIN]).to eq('linkedin_on.png')
        expect(hash[BucketSchedule::BIT_INSTAGRAM]).to eq('instagram_on.png')
        expect(hash[BucketSchedule::BIT_GMB]).to eq('gmb_on.png')
      end
    end

    describe 'self.get_days_of_week_array' do
      it 'returns correct days of week hash' do
        hash = BucketSchedule.get_days_of_week_array
        expect(hash[1]).to eq('Monday')
        expect(hash[2]).to eq('Tuesday')
        expect(hash[3]).to eq('Wednesday')
        expect(hash[4]).to eq('Thursday')
        expect(hash[5]).to eq('Friday')
        expect(hash[6]).to eq('Saturday')
        expect(hash[7]).to eq('Sunday')
      end
    end

    describe '#should_display_twitter_warning?' do
      context 'for once/annually schedules' do
        before do
          bucket_schedule.update!(
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
            description: 'A' * 300,
            twitter_description: nil
          )
        end

        it 'returns true when description is too long and no twitter_description' do
          bucket_image.update!(twitter_description: nil)
          expect(bucket_schedule.should_display_twitter_warning?).to be true
        end

        it 'returns false when twitter_description is present' do
          bucket_schedule.update!(twitter_description: 'Short Twitter text')
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end

        it 'returns false when bucket_image has twitter_description' do
          bucket_image.update!(twitter_description: 'Image Twitter text')
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end

        it 'returns false when Twitter is not selected' do
          bucket_schedule.update!(post_to: BucketSchedule::BIT_FACEBOOK)
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end
      end

      context 'for rotation schedules' do
        before do
          bucket_schedule.update!(
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION,
            post_to: BucketSchedule::BIT_TWITTER
          )
        end

        it 'returns true when any bucket image has long description without twitter_description' do
          bucket_image.update!(description: 'A' * 300, twitter_description: nil)
          expect(bucket_schedule.should_display_twitter_warning?).to be true
        end

        it 'returns false when all images have twitter_description' do
          bucket_image.update!(description: 'A' * 300, twitter_description: 'Twitter text')
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end

        it 'returns false when Twitter is not selected' do
          bucket_schedule.update!(post_to: BucketSchedule::BIT_FACEBOOK)
          bucket_image.update!(description: 'A' * 300, twitter_description: nil)
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end
      end
    end

    describe '#get_next_bucket_image_due' do
      context 'with once/annually schedule' do
        it 'returns bucket_image when present' do
          once_schedule = create(:bucket_schedule, 
            bucket: bucket, 
            bucket_image: bucket_image, 
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE
          )
          expect(once_schedule.get_next_bucket_image_due).to eq(bucket_image)
        end

        it 'falls back to rotation logic when bucket_image is nil' do
          rotation_image = create(:bucket_image, bucket: bucket, friendly_name: 'A')
          once_schedule = create(:bucket_schedule,
            bucket: bucket,
            bucket_image: nil,
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE
          )
          result = once_schedule.get_next_bucket_image_due
          expect(result).to eq(rotation_image)
        end
      end

      context 'with rotation schedule' do
        let!(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }
        let!(:image1) { create(:bucket_image, bucket: bucket, friendly_name: 'A') }
        let!(:image2) { create(:bucket_image, bucket: bucket, friendly_name: 'B') }

        it 'returns next image from rotation' do
          result = rotation_schedule.get_next_bucket_image_due
          expect(result).to eq(image1)
        end

        it 'falls back to first image if rotation returns nil' do
          bucket.bucket_images.destroy_all
          image = create(:bucket_image, bucket: bucket, friendly_name: 'Fallback')
          result = rotation_schedule.get_next_bucket_image_due
          expect(result).to eq(image)
        end
      end
    end

    describe '#get_next_schedule' do
      it 'returns "Already sent" for once schedule that has been sent' do
        bucket_schedule.update!(
          schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
          times_sent: 1,
          schedule: '0 9 * * *'
        )
        expect(bucket_schedule.get_next_schedule).to eq('Already sent')
      end

      it 'returns "Next run calculated" for valid cron schedule' do
        bucket_schedule.update!(schedule: '0 9 * * *')
        expect(bucket_schedule.get_next_schedule).to eq('Next run calculated')
      end

      it 'returns "Invalid Schedule" for invalid cron format' do
        bucket_schedule.update_column(:schedule, 'invalid')
        expect(bucket_schedule.get_next_schedule).to eq('Invalid Schedule')
      end

      it 'handles errors gracefully' do
        allow(bucket_schedule).to receive(:valid_cron_format?).and_raise(StandardError.new('Error'))
        expect(bucket_schedule.get_next_schedule).to eq('Invalid Schedule')
      end
    end

    describe '#get_next_bucket_image_due with offsets' do
      let!(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }
      let!(:image1) { create(:bucket_image, bucket: bucket, friendly_name: 'A') }
      let!(:image2) { create(:bucket_image, bucket: bucket, friendly_name: 'B') }
      let!(:image3) { create(:bucket_image, bucket: bucket, friendly_name: 'C') }

      it 'applies offset correctly' do
        result = rotation_schedule.get_next_bucket_image_due(1)
        expect(result).to eq(image2)
      end

      it 'applies skip_offset correctly' do
        result = rotation_schedule.get_next_bucket_image_due(0, 2)
        expect(result).to eq(image3)
      end

      it 'applies both offset and skip_offset' do
        result = rotation_schedule.get_next_bucket_image_due(1, 1)
        expect(result).to eq(image3)
      end
    end

    describe '#get_next_description_due with offsets' do
      let!(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }
      let!(:image1) { create(:bucket_image, bucket: bucket, friendly_name: 'A', description: 'Desc 1', twitter_description: 'Twitter 1') }
      let!(:image2) { create(:bucket_image, bucket: bucket, friendly_name: 'B', description: 'Desc 2', twitter_description: 'Twitter 2') }

      it 'applies offset for regular description' do
        result = rotation_schedule.get_next_description_due(1)
        expect(result).to eq('Desc 2')
      end

      it 'applies offset for twitter description' do
        result = rotation_schedule.get_next_description_due(1, 0, true)
        expect(result).to eq('Twitter 2')
      end

      it 'returns empty string when bucket_image has no description' do
        image1.update!(description: nil, twitter_description: nil)
        result = rotation_schedule.get_next_description_due(0, 0, true)
        expect(result).to eq('')
      end
    end

    describe '#get_days_selected edge cases' do
      it 'handles schedule with less than 5 parts' do
        bucket_schedule.update_column(:schedule, '0 9 * *')
        expect(bucket_schedule.get_days_selected).to eq([])
      end

      it 'handles schedule with more than 5 parts' do
        bucket_schedule.update_column(:schedule, '0 9 * * 1,2,3 extra')
        expect(bucket_schedule.get_days_selected).to eq(['1', '2', '3'])
      end
    end

    describe '#get_time_format edge cases' do
      it 'handles nil schedule' do
        bucket_schedule.update_column(:schedule, nil)
        expect(bucket_schedule.get_time_format).to eq(BucketSchedule::DEFAULT_TIME)
      end

      it 'handles schedule with only minute wildcard' do
        bucket_schedule.update_column(:schedule, '* 14 * * *')
        expect(bucket_schedule.get_time_format).to eq(BucketSchedule::DEFAULT_TIME)
      end

      it 'handles schedule with only hour wildcard' do
        bucket_schedule.update_column(:schedule, '30 * * * *')
        expect(bucket_schedule.get_time_format).to eq(BucketSchedule::DEFAULT_TIME)
      end
    end

    describe '#get_scheduled_date_format edge cases' do
      it 'handles nil schedule' do
        bucket_schedule.update_column(:schedule, nil)
        expected_date = Date.current.strftime('%Y-%m-%d')
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end

      it 'handles schedule with only day wildcard' do
        bucket_schedule.update_column(:schedule, '0 9 * 12 *')
        expected_date = Date.current.strftime('%Y-%m-%d')
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end

      it 'handles schedule with only month wildcard' do
        bucket_schedule.update_column(:schedule, '0 9 15 * *')
        expected_date = Date.current.strftime('%Y-%m-%d')
        expect(bucket_schedule.get_scheduled_date_format).to eq(expected_date)
      end
    end

    describe '#should_display_twitter_warning? edge cases' do
      context 'for once/annually schedule without bucket_image' do
        before do
          bucket_schedule.update!(
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
            bucket_image: nil,
            description: 'A' * 300,
            post_to: BucketSchedule::BIT_TWITTER
          )
        end

        it 'returns false when bucket_image is nil' do
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end
      end

      context 'for rotation schedule' do
        before do
          bucket_schedule.update!(
            schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION,
            post_to: BucketSchedule::BIT_TWITTER
          )
        end

        it 'returns false when no bucket images' do
          bucket.bucket_images.destroy_all
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end

        it 'returns false when description is nil' do
          bucket.bucket_images.update_all(description: nil, twitter_description: nil)
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end

        it 'returns false when description is blank' do
          bucket.bucket_images.update_all(description: '', twitter_description: nil)
          expect(bucket_schedule.should_display_twitter_warning?).to be false
        end
      end
    end

    describe '#get_next_bucket_image_due fallback behavior' do
      let!(:image1) { create(:bucket_image, bucket: bucket, friendly_name: 'A') }
      let!(:image2) { create(:bucket_image, bucket: bucket, friendly_name: 'B') }

      context 'when rotation returns nil but bucket has images' do
        let!(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }

        it 'falls back to first image when get_next_rotation_image returns nil' do
          # Mock get_next_rotation_image to return nil to test fallback
          allow(bucket).to receive(:get_next_rotation_image).and_return(nil)
          allow(Rails.logger).to receive(:warn)
          result = rotation_schedule.get_next_bucket_image_due
          expect(result).to eq(image1)
          expect(Rails.logger).to have_received(:warn).with(match(/get_next_rotation_image returned nil/))
        end
      end

      context 'when schedule_type is ONCE/ANNUALLY without bucket_image' do
        let!(:once_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE, bucket_image: nil) }

        it 'falls through to rotation logic when no bucket_image' do
          # Should use rotation logic when bucket_image is nil
          allow(bucket).to receive(:get_next_rotation_image).and_return(image2)
          result = once_schedule.get_next_bucket_image_due
          expect(result).to eq(image2)
        end
      end
    end
  end
end