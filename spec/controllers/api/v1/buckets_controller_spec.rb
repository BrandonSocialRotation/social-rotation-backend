require 'rails_helper'

RSpec.describe Api::V1::BucketsController, type: :controller do
  let(:user) { create(:user) }
  let(:bucket) { create(:bucket, user: user) }
  let(:image) { create(:image) }
  let(:bucket_image) { create(:bucket_image, bucket: bucket, image: image) }

  before do
    # Mock authentication
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'GET #index' do
    it 'returns all buckets for the current user' do
      bucket1 = create(:bucket, user: user)
      bucket2 = create(:bucket, user: user)
      other_user_bucket = create(:bucket) # Different user

      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['buckets'].length).to eq(2)
      expect(json_response['buckets'].map { |b| b['id'] }).to contain_exactly(bucket1.id, bucket2.id)
    end

    it 'includes bucket images and schedules count' do
      create(:bucket_image, bucket: bucket)
      create(:bucket_schedule, bucket: bucket)

      get :index

      json_response = JSON.parse(response.body)
      bucket_data = json_response['buckets'].first
      expect(bucket_data['images_count']).to eq(1)
      expect(bucket_data['schedules_count']).to eq(1)
    end
  end

  describe 'GET #show' do
    it 'returns bucket with images and schedules' do
      create(:bucket_image, bucket: bucket, image: image)
      create(:bucket_schedule, bucket: bucket)

      get :show, params: { id: bucket.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket']['id']).to eq(bucket.id)
      expect(json_response['bucket_images'].length).to eq(1)
      expect(json_response['bucket_schedules'].length).to eq(1)
    end

    it 'returns 404 for non-existent bucket' do
      get :show, params: { id: 99999 }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for bucket belonging to different user' do
      other_bucket = create(:bucket)
      get :show, params: { id: other_bucket.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        bucket: {
          name: 'Test Bucket',
          description: 'Test Description',
          use_watermark: true,
          post_once_bucket: false
        }
      }
    end

    it 'creates a new bucket' do
      expect {
        post :create, params: valid_params
      }.to change(Bucket, :count).by(1)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket']['name']).to eq('Test Bucket')
      expect(json_response['bucket']['user_id']).to eq(user.id)
    end

    it 'returns errors for invalid parameters' do
      invalid_params = { bucket: { name: '' } }
      
      post :create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to include("Name can't be blank")
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        id: bucket.id,
        bucket: {
          name: 'Updated Bucket Name',
          description: 'Updated Description',
          use_watermark: false
        }
      }
    end

    it 'updates the bucket' do
      patch :update, params: update_params

      expect(response).to have_http_status(:ok)
      bucket.reload
      expect(bucket.name).to eq('Updated Bucket Name')
      expect(bucket.description).to eq('Updated Description')
      expect(bucket.use_watermark).to be false
    end

    it 'returns errors for invalid updates' do
      invalid_params = { id: bucket.id, bucket: { name: '' } }
      
      patch :update, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to include("Name can't be blank")
    end
  end

  describe 'DELETE #destroy' do
    it 'deletes the bucket' do
      # Create the bucket before the expect block
      bucket_id = bucket.id
      
      expect {
        delete :destroy, params: { id: bucket_id }
      }.to change(Bucket, :count).by(-1)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Bucket deleted successfully')
    end

    it 'returns 404 for non-existent bucket' do
      delete :destroy, params: { id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET #page' do
    before do
      # Create multiple bucket images
      15.times do |i|
        img = create(:image, friendly_name: "Image #{i}")
        create(:bucket_image, bucket: bucket, image: img, friendly_name: "Image #{i}")
      end
    end

    it 'returns paginated bucket images' do
      get :page, params: { id: bucket.id, page_num: 1 }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_images'].length).to eq(12) # 4 * 3 rows
      expect(json_response['pagination']['page']).to eq(1)
      expect(json_response['pagination']['total']).to eq(15)
    end

    it 'returns correct page for page 2' do
      get :page, params: { id: bucket.id, page_num: 2 }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_images'].length).to eq(3) # Remaining images
    end
  end

  describe 'GET #images' do
    before do
      create(:bucket_image, bucket: bucket, image: image, friendly_name: 'Image A')
      create(:bucket_image, bucket: bucket, image: create(:image), friendly_name: 'Image B')
    end

    it 'returns all bucket images ordered by friendly name' do
      get :images, params: { id: bucket.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_images'].length).to eq(2)
      expect(json_response['bucket_images'].first['friendly_name']).to eq('Image A')
    end
  end

  describe 'PATCH #update_image' do
    let(:update_params) do
      {
        id: bucket.id,
        image_id: bucket_image.id,
        bucket_image: {
          description: 'Updated Description',
          twitter_description: 'Updated Twitter Description',
          use_watermark: false
        }
      }
    end

    it 'updates the bucket image' do
      patch :update_image, params: update_params

      expect(response).to have_http_status(:ok)
      bucket_image.reload
      expect(bucket_image.description).to eq('Updated Description')
      expect(bucket_image.twitter_description).to eq('Updated Twitter Description')
      expect(bucket_image.use_watermark).to be false
    end
  end

  describe 'DELETE #delete_image' do
    before do
      create(:bucket_schedule, bucket: bucket, bucket_image: bucket_image)
    end

    it 'deletes the bucket image and associated schedules' do
      expect {
        delete :delete_image, params: { id: bucket.id, image_id: bucket_image.id }
      }.to change(BucketImage, :count).by(-1)
        .and change(BucketSchedule, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #randomize' do
    before do
      3.times do |i|
        img = create(:image)
        create(:bucket_image, bucket: bucket, image: img, friendly_name: "Original #{i}")
      end
    end

    it 'randomizes bucket image friendly names' do
      original_names = bucket.bucket_images.pluck(:friendly_name)
      
      get :randomize, params: { id: bucket.id }

      expect(response).to have_http_status(:ok)
      bucket.reload
      new_names = bucket.bucket_images.pluck(:friendly_name)
      expect(new_names).to match_array(original_names) # Same names, different order
    end

    it 'returns error for empty bucket' do
      empty_bucket = create(:bucket, user: user)
      get :randomize, params: { id: empty_bucket.id }

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('No images found in the bucket')
    end
  end

  describe 'GET #for_scheduling' do
    before do
      create(:bucket, user: user, post_once_bucket: false)
      create(:bucket, user: user, post_once_bucket: true)
    end

    it 'returns all buckets when ignore_post_now is false' do
      get :for_scheduling

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['buckets'].length).to eq(2)
    end

    it 'excludes post_once_bucket when ignore_post_now is true' do
      get :for_scheduling, params: { ignore_post_now: 'true' }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['buckets'].length).to eq(1)
    end
  end

  describe 'GET #single_image' do
    it 'returns a specific bucket image' do
      get :single_image, params: { id: bucket.id, image_id: bucket_image.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_image']['id']).to eq(bucket_image.id)
      expect(json_response['bucket_image']['friendly_name']).to eq(bucket_image.friendly_name)
    end

    it 'returns 404 for non-existent image' do
      get :single_image, params: { id: bucket.id, image_id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET #videos' do
    let(:video) { create(:video, friendly_name: 'Test Video') }
    let!(:bucket_video) { create(:bucket_video, bucket: bucket, video: video, friendly_name: 'Test Video') }

    before do
      # Mock video get_source_url to avoid DigitalOcean URL issues
      allow_any_instance_of(Video).to receive(:get_source_url).and_return('https://example.com/video.mp4')
    end

    it 'returns all bucket videos ordered by friendly name' do
      get :videos, params: { id: bucket.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_videos'].length).to eq(1)
      expect(json_response['bucket_videos'].first['friendly_name']).to eq('Test Video')
    end
  end

  describe 'POST #add_image' do
    let(:existing_image) { create(:image, friendly_name: 'Existing Image') }

    it 'adds an existing image to the bucket' do
      expect {
        post :add_image, params: { id: bucket.id, image_id: existing_image.id, friendly_name: 'New Name' }
      }.to change(BucketImage, :count).by(1)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_image']['friendly_name']).to eq('New Name')
    end

    it 'uses image friendly_name when friendly_name not provided' do
      post :add_image, params: { id: bucket.id, image_id: existing_image.id }

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['bucket_image']['friendly_name']).to eq('Existing Image')
    end

    it 'returns error when image_id is missing' do
      post :add_image, params: { id: bucket.id }

      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('image_id is required')
    end

    it 'returns 404 when image does not exist' do
      post :add_image, params: { id: bucket.id, image_id: 99999 }

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Image not found')
    end
  end
end

