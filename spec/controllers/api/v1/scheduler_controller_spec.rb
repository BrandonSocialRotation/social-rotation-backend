require 'rails_helper'

RSpec.describe Api::V1::SchedulerController, type: :controller do
  let(:user) { create(:user) }
  let(:bucket) { create(:bucket, user: user) }
  let(:bucket_schedule) { create(:bucket_schedule, bucket: bucket, bucket_image: nil, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }

  before do
    # Mock authentication
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'POST #single_post' do
    let(:valid_networks) { ['facebook', 'twitter', 'instagram'] }

    context 'with file upload' do
      let(:file_params) do
        {
          networks: valid_networks,
          caption: 'Test caption',
          use_watermark: '1',
          file: fixture_file_upload('test_image.jpg', 'image/jpeg')
        }
      end

      it 'creates a post-once bucket if none exists' do
        expect {
          post :single_post, params: file_params
        }.to change(Bucket, :count).by(1)

        new_bucket = Bucket.last
        expect(new_bucket.post_once_bucket).to be true
        expect(new_bucket.name).to eq('Post Now Bucket')
      end

      it 'uses existing post-once bucket if it exists' do
        existing_bucket = create(:bucket, user: user, post_once_bucket: true)
        
        expect {
          post :single_post, params: file_params
        }.not_to change(Bucket, :count)
      end

      it 'creates image and bucket_image records' do
        expect {
          post :single_post, params: file_params
        }.to change(Image, :count).by(1)
         .and change(BucketImage, :count).by(1)

        bucket_image = BucketImage.last
        expect(bucket_image.description).to eq('Test caption')
        expect(bucket_image.use_watermark).to be true
      end

      it 'calculates correct post_to flags' do
        post :single_post, params: file_params

        bucket_image = BucketImage.last
        expected_flags = BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER | BucketSchedule::BIT_INSTAGRAM
        expect(bucket_image.post_to).to eq(expected_flags)
      end
    end

    context 'with scheduled post' do
      let(:scheduled_params) do
        {
          networks: valid_networks,
          caption: 'Scheduled post',
          scheduled_at: '2024-12-25 10:00 AM',
          file: fixture_file_upload('test_image.jpg', 'image/jpeg')
        }
      end

      it 'creates a scheduled post' do
        expect {
          post :single_post, params: scheduled_params
        }.to change(BucketSchedule, :count).by(1)

        schedule = BucketSchedule.last
        expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ONCE)
        expect(schedule.description).to eq('Scheduled post')
      end
    end

    context 'with existing image' do
      let(:image) { create(:image) }
      let(:bucket_image) { create(:bucket_image, bucket: bucket, image: image) }
      let(:existing_image_params) do
        {
          networks: valid_networks,
          caption: 'Using existing image',
          existing_image_id: bucket_image.id
        }
      end

      it 'uses existing bucket image' do
        # Force creation of bucket_image before counting
        bucket_image_id = bucket_image.id
        
        image_count_before = Image.count
        bucket_image_count_before = BucketImage.count
        
        post :single_post, params: existing_image_params
        
        expect(Image.count).to eq(image_count_before)
        expect(BucketImage.count).to eq(bucket_image_count_before)
      end
    end

    context 'with link attachment' do
      let(:link_params) do
        {
          networks: valid_networks,
          caption: 'Check this out!',
          link_attachment: 'https://example.com'
        }
      end

      it 'handles link sharing' do
        post :single_post, params: link_params

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Link post scheduled')
      end
    end

    context 'with no content' do
      it 'returns error for missing content' do
        post :single_post, params: { networks: valid_networks }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('No content provided')
      end
    end
  end

  describe 'POST #schedule' do
    let(:schedule_params) do
      {
        bucket_id: bucket.id,
        cron: '0 9 * * 1-5'
      }
    end

    it 'creates a rotation schedule' do
      expect {
        post :schedule, params: schedule_params
      }.to change(BucketSchedule, :count).by(1)

      schedule = BucketSchedule.last
      expect(schedule.schedule).to eq('0 9 * * 1-5')
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ROTATION)
    end

    it 'returns error for invalid bucket' do
      invalid_params = { bucket_id: 99999, cron: '0 9 * * 1-5' }
      
      post :schedule, params: invalid_params

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #post_now' do
    let!(:bucket_image) { create(:bucket_image, bucket: bucket) }
    let(:poster_double) { instance_double(SocialMediaPosterService) }
    
    before do
      # Stub the SocialMediaPosterService
      allow(SocialMediaPosterService).to receive(:new).and_return(poster_double)
      allow(poster_double).to receive(:post_to_all).and_return({
        'facebook' => { success: true },
        'twitter' => { success: true }
      })
    end

    it 'increments times_sent counter' do
      post :post_now, params: { id: bucket_schedule.id }
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Post sent successfully')
      expect(bucket_schedule.reload.times_sent).to eq(1)
    end

    it 'returns error when no images available' do
      bucket.bucket_images.destroy_all
      post :post_now, params: { id: bucket_schedule.id }
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('No images available in bucket')
    end

    it 'creates send history record' do
      expect {
        post :post_now, params: { id: bucket_schedule.id }
      }.to change(BucketSendHistory, :count).by(1)

      history = BucketSendHistory.last
      expect(history.bucket_schedule).to eq(bucket_schedule)
      expect(history.bucket_image).to eq(bucket_image)
    end

    it 'handles posting errors gracefully' do
      allow(poster_double).to receive(:post_to_all).and_raise(StandardError.new('API Error'))
      
      post :post_now, params: { id: bucket_schedule.id }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Failed to post to social media')
    end

    it 'uses bucket_image description when available' do
      bucket_image.update!(description: 'Image description', twitter_description: 'Image Twitter')
      post :post_now, params: { id: bucket_schedule.id }
      
      expect(poster_double).to have_received(:post_to_all)
      expect(SocialMediaPosterService).to have_received(:new).with(
        user,
        bucket_image,
        anything,
        'Image description',
        'Image Twitter'
      )
    end

    it 'falls back to schedule description when bucket_image description is empty' do
      bucket_image.update!(description: '', twitter_description: '')
      bucket_schedule.update!(description: 'Schedule description', twitter_description: 'Schedule Twitter')
      
      post :post_now, params: { id: bucket_schedule.id }
      
      expect(SocialMediaPosterService).to have_received(:new).with(
        user,
        bucket_image,
        anything,
        'Schedule description',
        'Schedule Twitter'
      )
    end
  end

  describe 'POST #skip_image' do
    it 'increments skip_image counter' do
      expect {
        post :skip_image, params: { id: bucket_schedule.id }
      }.to change { bucket_schedule.reload.skip_image }.by(1)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Image skipped')
    end
  end

  describe 'POST #skip_image_single' do
    context 'with annually schedule' do
      let(:annually_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ANNUALLY) }

      it 'sets skip_image to 1' do
        post :skip_image_single, params: { id: annually_schedule.id }

        expect(response).to have_http_status(:ok)
        annually_schedule.reload
        expect(annually_schedule.skip_image).to eq(1)
      end
    end

    context 'with once schedule' do
      let(:once_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE) }

      it 'deletes the schedule' do
        # Create the schedule before the expect block
        schedule_id = once_schedule.id
        
        expect {
          post :skip_image_single, params: { id: schedule_id }
        }.to change(BucketSchedule, :count).by(-1)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'GET #open_graph' do
    it 'returns OG data for valid URL' do
      get :open_graph, params: { url: 'https://example.com' }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['url']).to eq('https://example.com')
      expect(json_response).to have_key('title')
      expect(json_response).to have_key('description')
    end

    it 'returns error for missing URL' do
      get :open_graph

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('URL required')
    end
  end

  describe 'network flag calculation' do
    it 'correctly calculates post_to flags for all networks' do
      all_networks = ['facebook', 'twitter', 'instagram', 'linked_in', 'google_business']
      expected_flags = BucketSchedule::BIT_FACEBOOK | 
                      BucketSchedule::BIT_TWITTER | 
                      BucketSchedule::BIT_INSTAGRAM | 
                      BucketSchedule::BIT_LINKEDIN | 
                      BucketSchedule::BIT_GMB

      params = {
        networks: all_networks,
        caption: 'Test',
        file: fixture_file_upload('test_image.jpg', 'image/jpeg')
      }

      post :single_post, params: params

      bucket_image = BucketImage.last
      expect(bucket_image.post_to).to eq(expected_flags)
    end
  end
end

