require 'rails_helper'

RSpec.describe Api::V1::BucketSchedulesController, type: :controller do
  let(:user) { create(:user) }
  let(:bucket) { create(:bucket, user: user) }
  let(:bucket_image) { create(:bucket_image, bucket: bucket) }
  let(:bucket_schedule) { create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image) }

  before do
    # Mock authentication
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
    # Mock subscription check - assume user has active subscription for these tests
    allow(controller).to receive(:has_active_subscription?).and_return(true)
    allow(controller).to receive(:require_active_subscription_for_action!).and_return(true)
  end

  describe 'GET #index' do
    before do
      create(:bucket_schedule, bucket: bucket)
      create(:bucket_schedule, bucket: bucket)
      create(:bucket_schedule) # Different user
    end

    it 'returns all bucket schedules for current user' do
      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_schedules'].length).to eq(2)
    end
  end

  describe 'GET #show' do
    it 'returns bucket schedule details' do
      get :show, params: { id: bucket_schedule.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_schedule']['id']).to eq(bucket_schedule.id)
      expect(json_response['bucket_schedule']['schedule']).to eq(bucket_schedule.schedule)
    end

    it 'returns 404 for non-existent schedule' do
      get :show, params: { id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:create_params) do
      {
        bucket_id: bucket.id,
        bucket_schedule: {
          schedule: '0 9 * * 1-5',
          schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION,
          post_to: BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER
        }
      }
    end

    it 'creates a new bucket schedule' do
      expect {
        post :create, params: create_params
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_schedule']['schedule']).to eq('0 9 * * 1-5')
    end

    it 'creates schedule with facebook_page_id' do
      params_with_page = create_params.deep_merge(
        bucket_schedule: { facebook_page_id: 'page_123' }
      )
      
      expect {
        post :create, params: params_with_page
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:created)
      schedule = BucketSchedule.last
      expect(schedule.facebook_page_id).to eq('page_123')
    end

    it 'creates schedule with linkedin_organization_urn' do
      params_with_org = create_params.deep_merge(
        bucket_schedule: { linkedin_organization_urn: 'urn:li:organization:123' }
      )
      
      expect {
        post :create, params: params_with_org
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:created)
      schedule = BucketSchedule.last
      expect(schedule.linkedin_organization_urn).to eq('urn:li:organization:123')
    end

    it 'creates schedule with both facebook_page_id and linkedin_organization_urn' do
      params_with_both = create_params.deep_merge(
        bucket_schedule: {
          facebook_page_id: 'page_123',
          linkedin_organization_urn: 'urn:li:organization:123'
        }
      )
      
      expect {
        post :create, params: params_with_both
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:created)
      schedule = BucketSchedule.last
      expect(schedule.facebook_page_id).to eq('page_123')
      expect(schedule.linkedin_organization_urn).to eq('urn:li:organization:123')
    end

    it 'returns errors for invalid parameters' do
      invalid_params = { bucket_id: bucket.id, bucket_schedule: { schedule: '' } }
      
      post :create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end

    it 'returns error when bucket_image_id does not belong to bucket' do
      other_bucket = create(:bucket, user: user)
      other_bucket_image = create(:bucket_image, bucket: other_bucket)
      
      invalid_params = {
        bucket_id: bucket.id,
        bucket_schedule: {
          schedule: '0 9 * * 1-5',
          schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
          bucket_image_id: other_bucket_image.id
        }
      }
      
      post :create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to include('Selected image does not belong to this bucket')
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        id: bucket_schedule.id,
        bucket_schedule: {
          schedule: '0 10 * * 1-5',
          post_to: BucketSchedule::BIT_INSTAGRAM
        }
      }
    end

    it 'updates the bucket schedule' do
      patch :update, params: update_params

      expect(response).to have_http_status(:ok)
      bucket_schedule.reload
      expect(bucket_schedule.schedule).to eq('0 10 * * 1-5')
      expect(bucket_schedule.post_to).to eq(BucketSchedule::BIT_INSTAGRAM)
    end

    it 'updates facebook_page_id' do
      params_with_page = update_params.deep_merge(
        bucket_schedule: { facebook_page_id: 'page_456' }
      )
      
      patch :update, params: params_with_page

      expect(response).to have_http_status(:ok)
      bucket_schedule.reload
      expect(bucket_schedule.facebook_page_id).to eq('page_456')
    end

    it 'updates linkedin_organization_urn' do
      params_with_org = update_params.deep_merge(
        bucket_schedule: { linkedin_organization_urn: 'urn:li:organization:456' }
      )
      
      patch :update, params: params_with_org

      expect(response).to have_http_status(:ok)
      bucket_schedule.reload
      expect(bucket_schedule.linkedin_organization_urn).to eq('urn:li:organization:456')
    end

    it 'updates both facebook_page_id and linkedin_organization_urn' do
      params_with_both = update_params.deep_merge(
        bucket_schedule: {
          facebook_page_id: 'page_789',
          linkedin_organization_urn: 'urn:li:organization:789'
        }
      )
      
      patch :update, params: params_with_both

      expect(response).to have_http_status(:ok)
      bucket_schedule.reload
      expect(bucket_schedule.facebook_page_id).to eq('page_789')
      expect(bucket_schedule.linkedin_organization_urn).to eq('urn:li:organization:789')
    end

    it 'clears facebook_page_id when set to empty string' do
      bucket_schedule.update!(facebook_page_id: 'page_123')
      params_clear_page = update_params.deep_merge(
        bucket_schedule: { facebook_page_id: '' }
      )
      
      patch :update, params: params_clear_page

      expect(response).to have_http_status(:ok)
      bucket_schedule.reload
      expect(bucket_schedule.facebook_page_id).to be_nil
    end

    it 'returns error when update fails' do
      bucket_schedule.update_column(:schedule, 'invalid cron')
      # Make it invalid so update fails
      invalid_params = update_params.merge(bucket_schedule: { schedule: 'invalid' })
      
      patch :update, params: invalid_params
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end
  end

  describe 'DELETE #destroy' do
    it 'deletes the bucket schedule' do
      # Create the schedule before the expect block
      schedule_id = bucket_schedule.id
      
      expect {
        delete :destroy, params: { id: schedule_id }
      }.to change(BucketSchedule, :count).by(-1)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Schedule deleted successfully')
    end
  end

  describe 'POST #bulk_update' do
    let(:schedule1) { create(:bucket_schedule, bucket: bucket) }
    let(:schedule2) { create(:bucket_schedule, bucket: bucket) }
    let(:bulk_params) do
      {
        bucket_schedule_ids: "#{schedule1.id},#{schedule2.id}",
        networks: ['facebook', 'twitter'],
        time: '2024-12-25 10:00 AM'
      }
    end

    it 'updates multiple schedules' do
      post :bulk_update, params: bulk_params

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('2 schedules successfully updated')

      schedule1.reload
      schedule2.reload
      expected_post_to = BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER
      expect(schedule1.post_to).to eq(expected_post_to)
      expect(schedule2.post_to).to eq(expected_post_to)
    end

    it 'returns error for invalid time format' do
      invalid_params = bulk_params.merge(time: 'invalid time')
      
      post :bulk_update, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'skips non-existent schedule IDs' do
      params = bulk_params.merge(bucket_schedule_ids: "#{schedule1.id},99999")
      
      post :bulk_update, params: params
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('1 schedules successfully updated')
    end
  end

  describe 'DELETE #bulk_delete' do
    let(:schedule1) { create(:bucket_schedule, bucket: bucket) }
    let(:schedule2) { create(:bucket_schedule, bucket: bucket) }

    it 'deletes multiple schedules' do
      # Force creation before the expect block
      id1 = schedule1.id
      id2 = schedule2.id
      
      bulk_params = {
        bucket_schedule_ids: "#{id1},#{id2}"
      }
      
      expect {
        post :bulk_delete, params: bulk_params
      }.to change(BucketSchedule, :count).by(-2)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('2 schedules successfully deleted')
    end

    it 'skips non-existent schedule IDs' do
      id1 = schedule1.id
      params = { bucket_schedule_ids: "#{id1},99999" }
      
      expect {
        post :bulk_delete, params: params
      }.to change(BucketSchedule, :count).by(-1)
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('1 schedules successfully deleted')
    end

    it 'handles empty schedule IDs' do
      params = { bucket_schedule_ids: '' }
      
      post :bulk_delete, params: params
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('0 schedules successfully deleted')
    end
  end

  describe 'POST #rotation_create' do
    let(:rotation_params) do
      {
        bucket_id: bucket.id,
        networks: ['facebook', 'instagram'],
        time: '09:00',
        days: ['1', '2', '3', '4', '5'] # Monday to Friday
      }
    end

    it 'creates a rotation schedule' do
      expect {
        post :rotation_create, params: rotation_params
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:ok)
      schedule = BucketSchedule.last
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ROTATION)
      expect(schedule.schedule).to eq('0 9 * * 1,2,3,4,5')
      expect(schedule.post_to).to eq(BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_INSTAGRAM)
    end

    it 'returns error for missing parameters' do
      invalid_params = { bucket_id: bucket.id, networks: ['facebook'] }
      
      post :rotation_create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'handles time with leading zeros' do
      params = rotation_params.merge(time: '09:05')
      post :rotation_create, params: params
      
      expect(response).to have_http_status(:ok)
      schedule = BucketSchedule.last
      expect(schedule.schedule).to include('5 9')
    end

    it 'returns error for missing days' do
      params = { bucket_id: bucket.id, networks: ['facebook'], time: '09:00', days: [] }
      post :rotation_create, params: params
      
      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Invalid parameters')
    end
  end

  describe 'POST #date_create' do
    let(:date_params) do
      {
        bucket_id: bucket.id,
        bucket_image_id: bucket_image.id,
        networks: ['twitter', 'linked_in'],
        time: '2024-12-25 10:00 AM',
        description: 'Holiday post',
        twitter_description: 'Holiday tweet'
      }
    end

    it 'creates a date-based schedule' do
      expect {
        post :date_create, params: date_params
      }.to change(BucketSchedule, :count).by(1)

      expect(response).to have_http_status(:ok)
      schedule = BucketSchedule.last
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ONCE)
      expect(schedule.bucket_image).to eq(bucket_image)
      expect(schedule.description).to eq('Holiday post')
      expect(schedule.twitter_description).to eq('Holiday tweet')
    end

    it 'creates annually schedule when requested' do
      annually_params = date_params.merge(post_annually: 'true')
      
      post :date_create, params: annually_params

      schedule = BucketSchedule.last
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
    end
  end

  describe 'POST #post_now' do
    it 'increments times_sent counter' do
      expect {
        post :post_now, params: { id: bucket_schedule.id }
      }.to change { bucket_schedule.reload.times_sent }.by(1)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Post sent successfully')
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

    context 'with rotation schedule' do
      let(:rotation_schedule) { create(:bucket_schedule, bucket: bucket, schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION) }

      it 'does not modify rotation schedule' do
        initial_skip = rotation_schedule.skip_image
        
        post :skip_image_single, params: { id: rotation_schedule.id }
        
        expect(response).to have_http_status(:ok)
        rotation_schedule.reload
        expect(rotation_schedule.skip_image).to eq(initial_skip)
      end
    end
  end

  describe 'GET #history' do
    before do
      create(:bucket_send_history, bucket_schedule: bucket_schedule, sent_at: 1.day.ago)
      create(:bucket_send_history, bucket_schedule: bucket_schedule, sent_at: 2.days.ago)
    end

    it 'returns send history for the schedule' do
      get :history, params: { id: bucket_schedule.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['send_histories'].length).to eq(2)
      expect(json_response['bucket_schedule']['id']).to eq(bucket_schedule.id)
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
        bucket_id: bucket.id,
        networks: all_networks,
        time: '09:00',
        days: ['1', '2', '3', '4', '5']
      }

      post :rotation_create, params: params

      schedule = BucketSchedule.last
      expect(schedule.post_to).to eq(expected_flags)
    end
  end

  describe 'JSON serializer methods' do
    describe '#bucket_schedule_json' do
      it 'returns correct JSON structure' do
        json = controller.send(:bucket_schedule_json, bucket_schedule)
        expect(json).to have_key(:id)
        expect(json).to have_key(:schedule)
        expect(json).to have_key(:schedule_type)
        expect(json).to have_key(:post_to)
        expect(json).to have_key(:description)
        expect(json).to have_key(:twitter_description)
        expect(json).to have_key(:times_sent)
        expect(json).to have_key(:skip_image)
        expect(json).to have_key(:bucket_id)
        expect(json).to have_key(:bucket_image_id)
        expect(json).to have_key(:bucket)
        expect(json).to have_key(:bucket_image)
        expect(json).to have_key(:created_at)
        expect(json).to have_key(:updated_at)
      end

      it 'includes bucket info when present' do
        json = controller.send(:bucket_schedule_json, bucket_schedule)
        expect(json[:bucket]).to be_a(Hash)
        expect(json[:bucket][:id]).to eq(bucket.id)
        expect(json[:bucket][:name]).to eq(bucket.name)
      end

      it 'handles nil bucket gracefully' do
        schedule = create(:bucket_schedule, bucket: bucket)
        allow(schedule).to receive(:bucket).and_return(nil)
        json = controller.send(:bucket_schedule_json, schedule)
        expect(json[:bucket]).to be_nil
      end

      it 'includes bucket_image info when present' do
        json = controller.send(:bucket_schedule_json, bucket_schedule)
        expect(json[:bucket_image]).to be_a(Hash)
        expect(json[:bucket_image][:id]).to eq(bucket_image.id)
        expect(json[:bucket_image][:friendly_name]).to eq(bucket_image.friendly_name)
      end

      it 'handles nil bucket_image gracefully' do
        schedule = create(:bucket_schedule, bucket: bucket, bucket_image: nil)
        json = controller.send(:bucket_schedule_json, schedule)
        expect(json[:bucket_image]).to be_nil
      end
    end

    describe '#send_history_json' do
      let(:send_history) { create(:bucket_send_history, bucket: bucket, bucket_schedule: bucket_schedule, bucket_image: bucket_image) }

      it 'returns correct JSON structure' do
        json = controller.send(:send_history_json, send_history)
        expect(json).to have_key(:id)
        expect(json).to have_key(:sent_at)
        expect(json).to have_key(:sent_to)
        expect(json).to have_key(:sent_to_name)
        expect(json).to have_key(:bucket_image)
        expect(json).to have_key(:created_at)
      end

      it 'includes bucket_image info when present' do
        json = controller.send(:send_history_json, send_history)
        expect(json[:bucket_image]).to be_a(Hash)
        expect(json[:bucket_image][:id]).to eq(bucket_image.id)
        expect(json[:bucket_image][:friendly_name]).to eq(bucket_image.friendly_name)
      end

      it 'handles nil bucket_image gracefully' do
        history = create(:bucket_send_history, bucket: bucket, bucket_schedule: bucket_schedule, bucket_image: bucket_image)
        allow(history).to receive(:bucket_image).and_return(nil)
        json = controller.send(:send_history_json, history)
        expect(json[:bucket_image]).to be_nil
      end
    end
  end
end

