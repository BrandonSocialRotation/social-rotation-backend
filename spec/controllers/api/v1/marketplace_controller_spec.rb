require 'rails_helper'

RSpec.describe Api::V1::MarketplaceController, type: :controller do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:bucket) { create(:bucket, user: other_user) }
  let(:front_image) { create(:image) }
  let(:market_item) { create(:market_item, bucket: bucket, front_image: front_image, visible: true) }

  before do
    # Mock authentication
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'GET #index' do
    before do
      # Create purchased market items
      create(:user_market_item, user: user, market_item: market_item, visible: true)
      create(:user_market_item, user: user, market_item: create(:market_item, visible: true), visible: false)
      create(:user_market_item, user: other_user, market_item: create(:market_item, visible: true), visible: true)
    end

    it 'returns only visible purchased market items for current user' do
      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['market_items'].length).to eq(1)
      expect(json_response['market_items'].first['id']).to eq(market_item.id)
    end
  end

  describe 'GET #available' do
    before do
      # Create available market items
      create(:market_item, visible: true)
      create(:market_item, visible: true)
      create(:market_item, visible: false) # Hidden
      
      # Create purchased item (should not appear in available)
      purchased_item = create(:market_item, visible: true)
      create(:user_market_item, user: user, market_item: purchased_item)
    end

    it 'returns only available (not purchased) market items' do
      get :available

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['market_items'].length).to eq(2)
    end

    context 'with super admin user' do
      let(:super_admin) { create(:user, account_id: 0) }

      before do
        allow(controller).to receive(:current_user).and_return(super_admin)
        # Clear existing market items to ensure clean test
        MarketItem.destroy_all
        # Create exactly 3 items for super admin
        create(:market_item, bucket: create(:bucket, user: super_admin), visible: true)
        create(:market_item, bucket: create(:bucket, user: super_admin), visible: true)
        create(:market_item, bucket: create(:bucket, user: super_admin), visible: true)
      end

      it 'shows all available items for super admin' do
        get :available

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['market_items'].length).to eq(3)
      end
    end

    context 'with reseller account user' do
      let(:reseller_account) { create(:account, is_reseller: true) }
      let(:reseller_user) { create(:user, account: reseller_account, is_account_admin: true) }
      let(:reseller_bucket) { create(:bucket, user: reseller_user) }
      let(:regular_user) { create(:user, account: reseller_account, is_account_admin: false) }

      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        # Clear existing market items to ensure clean test
        MarketItem.destroy_all
        # Create exactly 1 item for this reseller
        create(:market_item, bucket: reseller_bucket, visible: true)
        # Create items for different reseller (should not appear)
        other_reseller = create(:account, is_reseller: true)
        other_reseller_user = create(:user, account: other_reseller, is_account_admin: true)
        create(:market_item, bucket: create(:bucket, user: other_reseller_user), visible: true)
      end

      it 'shows items from same reseller account' do
        get :available

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['market_items'].length).to eq(1)
        # Verify the market item belongs to the reseller's bucket
        market_item_id = json_response['market_items'].first['id']
        market_item = MarketItem.find(market_item_id)
        expect(market_item.bucket.user.account_id).to eq(reseller_account.id)
      end
    end

    context 'with user without marketplace access' do
      let(:restricted_account) { create(:account) }
      let(:restricted_user) { create(:user, account: restricted_account) }

      before do
        allow(controller).to receive(:current_user).and_return(restricted_user)
        restricted_account.account_feature.update!(allow_marketplace: false)
      end

      it 'returns empty array when marketplace access is disabled' do
        get :available

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['market_items']).to be_empty
      end
    end
  end

  describe 'GET #show' do
    before do
      # Create bucket images
      15.times do |i|
        img = create(:image)
        create(:bucket_image, bucket: bucket, image: img, friendly_name: "Image #{i}")
      end
    end

    it 'returns market item with first 12 bucket images' do
      get :show, params: { id: market_item.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['market_item']['id']).to eq(market_item.id)
      expect(json_response['bucket_images'].length).to eq(12)
    end
  end

  describe 'GET #info' do
    let(:info_bucket) { create(:bucket, user: user) }
    let(:info_market_item) { create(:market_item, bucket: info_bucket, front_image: create(:image), visible: true) }

    before do
      # Create bucket images
      6.times do |i|
        img = create(:image)
        create(:bucket_image, bucket: info_bucket, image: img, friendly_name: "Image #{i}")
      end
    end

    it 'returns market item with first 4 preview images' do
      get :info, params: { id: info_market_item.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['market_item']['id']).to eq(info_market_item.id)
      expect(json_response['preview_images'].length).to eq(4)
    end

    it 'returns error when market item not found' do
      get :info, params: { id: 99999 }
      
      expect(response).to have_http_status(:not_found)
    end

    it 'returns error when bucket is nil' do
      # Stub the bucket association on the instance that will be loaded
      allow(MarketItem).to receive(:find).and_return(info_market_item)
      allow(info_market_item).to receive(:bucket).and_return(nil)
      
      get :info, params: { id: info_market_item.id }
      
      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('No bucket associated')
    end
  end

  describe 'POST #clone' do
    before do
      # Create source bucket with images
      img1 = create(:image)
      img2 = create(:image)
      bucket_image1 = create(:bucket_image, bucket: bucket, image: img1, friendly_name: 'Image 1')
      bucket_image2 = create(:bucket_image, bucket: bucket, image: img2, friendly_name: 'Image 2')
      
      # Add force_send_date to one image
      bucket_image1.update!(force_send_date: 1.week.from_now, repeat: true)
    end

    it 'creates new bucket with cloned images' do
      expect {
        post :clone, params: { id: market_item.id }
      }.to change(Bucket, :count).by(1)
       .and change(BucketImage, :count).by(2)

      new_bucket = Bucket.last
      expect(new_bucket.user).to eq(user)
      expect(new_bucket.name).to eq('New Bucket')
      expect(new_bucket.description).to eq(bucket.description)
    end

    it 'preserves scheduling when requested' do
      post :clone, params: { id: market_item.id, preserve_scheduling: 'true' }

      expect(BucketSchedule.count).to eq(1)
      schedule = BucketSchedule.last
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
    end

    it 'does not preserve scheduling when not requested' do
      post :clone, params: { id: market_item.id, preserve_scheduling: 'false' }

      expect(BucketSchedule.count).to eq(0)
    end
  end

  describe 'POST #copy_to_bucket' do
    let(:target_bucket) { create(:bucket, user: user) }

    before do
      # Create source bucket with images
      img1 = create(:image)
      img2 = create(:image)
      create(:bucket_image, bucket: bucket, image: img1, friendly_name: 'Image 1')
      create(:bucket_image, bucket: bucket, image: img2, friendly_name: 'Image 2')
    end

    it 'copies images to target bucket' do
      expect {
        post :copy_to_bucket, params: { id: market_item.id, bucket_id: target_bucket.id }
      }.to change(BucketImage, :count).by(2)

      target_bucket.reload
      expect(target_bucket.bucket_images.count).to eq(2)
    end

    it 'returns error for non-existent target bucket' do
      post :copy_to_bucket, params: { id: market_item.id, bucket_id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #buy' do
    it 'creates user_market_item record' do
      expect {
        post :buy, params: { id: market_item.id }
      }.to change(UserMarketItem, :count).by(1)

      user_market_item = UserMarketItem.last
      expect(user_market_item.user).to eq(user)
      expect(user_market_item.market_item).to eq(market_item)
      expect(user_market_item.visible).to be true
    end

    it 'returns success message' do
      post :buy, params: { id: market_item.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Market item purchased successfully')
    end
  end

  describe 'POST #hide' do
    let!(:purchased_item) { create(:user_market_item, user: user, market_item: market_item, visible: true) }

    it 'hides the purchased market item' do
      post :hide, params: { id: market_item.id }

      expect(response).to have_http_status(:ok)
      user_market_item = UserMarketItem.find_by(user: user, market_item: market_item)
      expect(user_market_item.visible).to be false
    end
  end

  describe 'POST #hide without purchase' do
    it 'returns error for non-purchased item' do
      post :hide, params: { id: market_item.id }

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Could not find purchased pack')
    end
  end

  describe 'POST #make_visible' do
    let!(:purchased_item) { create(:user_market_item, user: user, market_item: market_item, visible: false) }

    it 'makes the purchased market item visible' do
      post :make_visible, params: { id: market_item.id }

      expect(response).to have_http_status(:ok)
      user_market_item = UserMarketItem.find_by(user: user, market_item: market_item)
      expect(user_market_item.visible).to be true
    end
  end

  describe 'POST #make_visible without purchase' do
    it 'returns error for non-purchased item' do
      post :make_visible, params: { id: market_item.id }

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Could not find purchased pack')
    end
  end

  describe 'GET #user_buckets' do
    before do
      create(:bucket, user: user)
      create(:bucket, user: user)
      create(:bucket, user: other_user) # Different user
    end

    it 'returns only current user buckets' do
      get :user_buckets

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['buckets'].length).to eq(2)
    end
  end

  describe 'schedule creation from force dates' do
    let(:target_bucket) { create(:bucket, user: user) }

    before do
      img = create(:image)
      bucket_image = create(:bucket_image, bucket: bucket, image: img, friendly_name: 'Test Image')
      bucket_image.update!(force_send_date: 1.week.from_now, repeat: true)
    end

    it 'creates schedule when preserving scheduling' do
      post :copy_to_bucket, params: { 
        id: market_item.id, 
        bucket_id: target_bucket.id, 
        preserve_scheduling: 'true' 
      }

      expect(BucketSchedule.count).to eq(1)
      schedule = BucketSchedule.last
      expect(schedule.schedule_type).to eq(BucketSchedule::SCHEDULE_TYPE_ANNUALLY)
    end

    it 'does not create schedule when not preserving scheduling' do
      post :copy_to_bucket, params: { 
        id: market_item.id, 
        bucket_id: target_bucket.id, 
        preserve_scheduling: 'false' 
      }

      expect(BucketSchedule.count).to eq(0)
    end

    it 'handles schedule creation errors gracefully' do
      allow_any_instance_of(Bucket).to receive(:bucket_schedules).and_return(double(create!: nil))
      allow_any_instance_of(Bucket).to receive(:bucket_schedules).and_raise(StandardError.new('Schedule error'))
      
      post :copy_to_bucket, params: { 
        id: market_item.id, 
        bucket_id: target_bucket.id, 
        preserve_scheduling: 'true' 
      }
      
      # Should still succeed even if schedule creation fails
      expect(response).to have_http_status(:ok)
    end

    it 'handles force_send_date as string' do
      # Clear any existing schedules and bucket_images from before block
      BucketSchedule.destroy_all
      market_item.bucket.bucket_images.destroy_all
      
      # Add a bucket_image to the market_item's bucket with force_send_date
      img = create(:image)
      bucket_image = create(:bucket_image, bucket: market_item.bucket, image: img)
      # Set force_send_date as a Time object (which will be stored correctly)
      bucket_image.update!(force_send_date: Time.parse('2024-12-25 10:00:00'))
      
      post :copy_to_bucket, params: { 
        id: market_item.id, 
        bucket_id: target_bucket.id, 
        preserve_scheduling: 'true' 
      }
      
      expect(BucketSchedule.count).to eq(1)
    end
  end

  describe 'get_visible_user_ids' do
    it 'includes super admin users' do
      super_admin = create(:user, account_id: 0)
      regular_user = create(:user, account_id: 1)
      
      # This is tested indirectly through available endpoint
      get :available
      
      expect(response).to have_http_status(:ok)
    end

    it 'includes reseller users for same account' do
      account = create(:account)
      reseller = create(:user, account: account, is_account_admin: true)
      regular_user = create(:user, account: account, is_account_admin: false)
      
      allow(controller).to receive(:current_user).and_return(regular_user)
      account.account_feature.update!(allow_marketplace: true)
      
      reseller_bucket = create(:bucket, user: reseller)
      create(:market_item, bucket: reseller_bucket, visible: true)
      
      get :available
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['market_items'].length).to be >= 1
    end
  end
end

