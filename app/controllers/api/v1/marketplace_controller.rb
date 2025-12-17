class Api::V1::MarketplaceController < ApplicationController
  before_action :authenticate_user!
  before_action :set_market_item, only: [:show, :info, :clone, :copy_to_bucket, :buy, :hide, :make_visible]

  # GET /api/v1/marketplace
  def index
    # Get visible market items for the user
    user_market_items = current_user.user_market_items.where(visible: true)
    market_item_ids = user_market_items.pluck(:market_item_id)
    
    @market_items = MarketItem.where(id: market_item_ids)
                              .includes(:bucket, :front_image)
                              .where(visible: true)

    render json: {
      market_items: @market_items.map { |item| market_item_json(item) }
    }
  end

  # GET /api/v1/marketplace/available
  def available
    # Get all available market items (not purchased by user)
    # Filtered by account visibility rules
    purchased_ids = current_user.user_market_items.pluck(:market_item_id)
    
    # Build query based on user type
    query = MarketItem.where(visible: true).where.not(id: purchased_ids)
    
    # Filter by account permissions
    if current_user.super_admin?
      # Super admins see everything
      @market_items = query.includes(:bucket, :front_image)
    elsif current_user.account && current_user.account.account_feature&.allow_marketplace
      # Users with marketplace permission see:
      # 1. Public items (created by super admins)
      # 2. Items created by their reseller
      bucket_ids = Bucket.where(user_id: get_visible_user_ids).pluck(:id)
      @market_items = query.where(bucket_id: bucket_ids).includes(:bucket, :front_image)
    else
      # No marketplace access
      @market_items = []
    end

    render json: {
      market_items: @market_items.map { |item| market_item_json(item) }
    }
  end

  # GET /api/v1/marketplace/:id
  def show
    @bucket_images = @market_item.bucket.bucket_images
                                 .includes(:image)
                                 .order(:friendly_name)
                                 .limit(12) # Show first 12 images

    render json: {
      market_item: market_item_json(@market_item),
      bucket_images: @bucket_images.map { |bi| bucket_image_json(bi) }
    }
  end

  # GET /api/v1/marketplace/:id/info
  def info
    return render json: { error: 'Market item not found' }, status: :not_found unless @market_item
    return render json: { error: 'No bucket associated with this market item' }, status: :not_found unless @market_item.bucket
    
    @bucket_images = @market_item.bucket.bucket_images
                                 .includes(:image)
                                 .limit(4) # Show first 4 images for preview

    render json: {
      market_item: market_item_json(@market_item),
      preview_images: @bucket_images.map { |bi| bucket_image_json(bi) }
    }
  end

  # POST /api/v1/marketplace/:id/clone
  def clone
    preserve_scheduling = params[:preserve_scheduling] == 'true'
    
    # Create new bucket
    new_bucket = current_user.buckets.create!(
      name: 'New Bucket',
      description: @market_item.bucket.description,
      use_watermark: @market_item.bucket.use_watermark
    )

    # Clone bucket images
    @market_item.bucket.bucket_images.each do |bucket_image|
      new_bucket_image = new_bucket.bucket_images.create!(
        image: bucket_image.image,
        friendly_name: bucket_image.friendly_name,
        description: bucket_image.description,
        twitter_description: bucket_image.twitter_description,
        force_send_date: preserve_scheduling ? bucket_image.force_send_date : nil,
        repeat: bucket_image.repeat,
        post_to: bucket_image.post_to,
        use_watermark: bucket_image.use_watermark
      )

      # Create schedule if preserving scheduling and force_send_date exists
      if preserve_scheduling && bucket_image.force_send_date
        create_schedule_from_force_date(new_bucket_image, bucket_image.force_send_date)
      end
    end

    render json: {
      bucket: bucket_json(new_bucket),
      message: "Content Bucket '#{@market_item.bucket.name}' successfully created"
    }
  end

  # POST /api/v1/marketplace/:id/copy_to_bucket
  def copy_to_bucket
    target_bucket = current_user.buckets.find(params[:bucket_id])
    preserve_scheduling = params[:preserve_scheduling] == 'true'

    # Copy bucket images to target bucket
    @market_item.bucket.bucket_images.each do |bucket_image|
      new_bucket_image = target_bucket.bucket_images.create!(
        image: bucket_image.image,
        friendly_name: bucket_image.friendly_name,
        description: bucket_image.description,
        twitter_description: bucket_image.twitter_description,
        force_send_date: preserve_scheduling ? bucket_image.force_send_date : nil,
        repeat: bucket_image.repeat,
        post_to: bucket_image.post_to,
        use_watermark: bucket_image.use_watermark
      )

      # Create schedule if preserving scheduling and force_send_date exists
      if preserve_scheduling && bucket_image.force_send_date
        create_schedule_from_force_date(new_bucket_image, bucket_image.force_send_date)
      end
    end

    render json: {
      message: "Package successfully copied to #{target_bucket.name}"
    }
  end

  # POST /api/v1/marketplace/:id/buy
  def buy
    # This would integrate with payment processing (Stripe, etc.)
    # For now, we'll just create the user_market_item record
    
    user_market_item = current_user.user_market_items.create!(
      market_item: @market_item,
      visible: true
    )

    render json: {
      user_market_item: {
        id: user_market_item.id,
        market_item_id: user_market_item.market_item_id,
        visible: user_market_item.visible,
        created_at: user_market_item.created_at
      },
      message: 'Market item purchased successfully'
    }
  end

  # POST /api/v1/marketplace/:id/hide
  def hide
    user_market_item = current_user.user_market_items.find_by(market_item_id: @market_item.id)
    
    if user_market_item
      user_market_item.update!(visible: false)
      render json: { message: 'Purchased pack successfully hidden' }
    else
      render json: { error: 'Could not find purchased pack' }, status: :not_found
    end
  end

  # POST /api/v1/marketplace/:id/make_visible
  def make_visible
    user_market_item = current_user.user_market_items.find_by(market_item_id: @market_item.id)
    
    if user_market_item
      user_market_item.update!(visible: true)
      render json: { message: 'Bucket successfully added to Purchased Buckets' }
    else
      render json: { error: 'Could not find purchased pack' }, status: :not_found
    end
  end

  # GET /api/v1/marketplace/user_buckets
  def user_buckets
    @buckets = current_user.buckets.includes(:bucket_images)
    
    render json: {
      buckets: @buckets.map { |bucket| bucket_json(bucket) }
    }
  end

  private

  def set_market_item
    @market_item = MarketItem.find(params[:id])
  end

  def create_schedule_from_force_date(bucket_image, force_send_date)
    return unless force_send_date

    begin
      date_time = force_send_date.is_a?(String) ? Time.parse(force_send_date) : force_send_date
      
      cron_string = "#{date_time.min} #{date_time.hour} #{date_time.day} #{date_time.month} *"
      
      bucket_image.bucket.bucket_schedules.create!(
        bucket_image: bucket_image,
        schedule: cron_string,
        schedule_type: bucket_image.repeat ? BucketSchedule::SCHEDULE_TYPE_ANNUALLY : BucketSchedule::SCHEDULE_TYPE_ONCE,
        description: bucket_image.description,
        twitter_description: bucket_image.twitter_description,
        post_to: bucket_image.post_to
      )
    rescue => e
      Rails.logger.error "Error creating schedule from force date: #{e.message}"
    end
  end

  def market_item_json(market_item)
    {
      id: market_item.id,
      price: market_item.price,
      visible: market_item.visible,
      bucket: {
        id: market_item.bucket.id,
        name: market_item.bucket.name,
        description: market_item.bucket.description,
        images_count: market_item.bucket.bucket_images.count
      },
      front_image: market_item.front_image ? {
        id: market_item.front_image.id,
        file_path: market_item.front_image.file_path,
        source_url: market_item.front_image.get_source_url
      } : nil,
      created_at: market_item.created_at,
      updated_at: market_item.updated_at
    }
  end

  def bucket_json(bucket)
    {
      id: bucket.id,
      name: bucket.name,
      description: bucket.description,
      use_watermark: bucket.use_watermark,
      post_once_bucket: bucket.post_once_bucket,
      images_count: bucket.bucket_images.count,
      schedules_count: bucket.bucket_schedules.count,
      created_at: bucket.created_at,
      updated_at: bucket.updated_at
    }
  end

  def bucket_image_json(bucket_image)
    {
      id: bucket_image.id,
      friendly_name: bucket_image.friendly_name,
      description: bucket_image.description,
      twitter_description: bucket_image.twitter_description,
      force_send_date: bucket_image.force_send_date,
      repeat: bucket_image.repeat,
      post_to: bucket_image.post_to,
      use_watermark: bucket_image.use_watermark,
      image: {
        id: bucket_image.image.id,
        file_path: bucket_image.image.file_path,
        source_url: bucket_image.image.get_source_url
      },
      created_at: bucket_image.created_at,
      updated_at: bucket_image.updated_at
    }
  end
  
  # Get list of user IDs whose marketplace items are visible to current user
  def get_visible_user_ids
    user_ids = []
    
    # Super admins created items (account_id = 0)
    user_ids += User.where(account_id: 0).pluck(:id)
    
    # If user belongs to a reseller account, also show reseller's items
    if current_user.account_id && current_user.account_id > 0
      # Get the account admin (reseller) for this account
      reseller_users = User.where(account_id: current_user.account_id, is_account_admin: true)
      user_ids += reseller_users.pluck(:id)
    end
    
    user_ids.uniq
  end
end
