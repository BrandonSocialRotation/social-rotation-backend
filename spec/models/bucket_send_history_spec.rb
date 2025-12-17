require 'rails_helper'

RSpec.describe BucketSendHistory, type: :model do
  describe 'associations' do
    it { should belong_to(:bucket) }
    it { should belong_to(:bucket_schedule) }
    it { should belong_to(:bucket_image) }
  end

  describe 'methods' do
    let(:user) { create(:user) }
    let(:bucket) { create(:bucket, user: user) }
    let(:bucket_image) { create(:bucket_image, bucket: bucket) }
    let(:bucket_schedule) { create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image) }
    let(:history) { create(:bucket_send_history, bucket: bucket, bucket_schedule: bucket_schedule, bucket_image: bucket_image, sent_to: BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER) }

    describe '#get_sent_to_name' do
      it 'converts sent_to flags to platform names' do
        expect(history.get_sent_to_name).to include('Facebook')
        expect(history.get_sent_to_name).to include('Twitter')
      end

      it 'includes all selected platforms' do
        history.update!(sent_to: BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER | BucketSchedule::BIT_LINKEDIN)
        result = history.get_sent_to_name
        expect(result).to include('Facebook')
        expect(result).to include('Twitter')
        expect(result).to include('LinkedIn')
      end

      it 'includes Instagram when selected' do
        history.update!(sent_to: BucketSchedule::BIT_INSTAGRAM)
        expect(history.get_sent_to_name).to include('Instagram')
      end

      it 'includes Google My Business when selected' do
        history.update!(sent_to: BucketSchedule::BIT_GMB)
        expect(history.get_sent_to_name).to include('Google My Business')
      end

      it 'returns "Unknown" when sent_to is 0' do
        history.update!(sent_to: 0)
        expect(history.get_sent_to_name).to eq('Unknown')
      end

      it 'returns "Unknown" when sent_to is nil' do
        history.update_column(:sent_to, nil)
        expect(history.get_sent_to_name).to eq('Unknown')
      end
    end
  end
end
