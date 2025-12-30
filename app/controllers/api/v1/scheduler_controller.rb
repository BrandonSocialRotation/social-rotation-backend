class Api::V1::SchedulerController < ApplicationController
  before_action :authenticate_user!
  before_action :set_bucket_schedule, only: [:post_now, :skip_image, :skip_image_single]

  # POST /api/v1/scheduler/single_post
  def single_post
    require_active_subscription_for_action!
    
    # Convert network names to bit flags
    post_to = calculate_post_to_flags(params[:networks] || [])
    
    # Handle different types of posts
    if params[:link_attachment].present?
      handle_link_post(post_to)
    elsif params[:file].present?
      handle_file_post(post_to)
    elsif params[:existing_image_id].present?
      handle_existing_image_post(post_to)
    else
      render json: { error: 'No content provided' }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/scheduler/schedule
  def schedule
    @bucket = current_user.buckets.find(params[:bucket_id])
    
    @bucket_schedule = @bucket.bucket_schedules.build(
      schedule: params[:cron],
      schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION
    )
    
    if @bucket_schedule.save
      render json: {
        bucket_schedule: bucket_schedule_json(@bucket_schedule),
        message: 'Schedule created successfully'
      }
    else
      render json: {
        errors: @bucket_schedule.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/scheduler/post_now/:id
  # Immediately posts the scheduled content to social media
  def post_now
    require_active_subscription_for_action!
    
    # Get the next image to post
    bucket_image = @bucket_schedule.get_next_bucket_image_due
    
    unless bucket_image
      # Provide more detailed error message
      bucket = @bucket_schedule.bucket
      image_count = bucket.bucket_images.count
      
      if image_count == 0
        return render json: { error: 'No images available in bucket' }, status: :unprocessable_entity
      else
        return render json: { error: "Unable to determine next image to post. Bucket has #{image_count} image(s) but rotation logic failed." }, status: :unprocessable_entity
      end
    end
    
    # Get description (use bucket_image description if available, otherwise schedule description)
    description = bucket_image.description.presence || @bucket_schedule.description.presence || ''
    twitter_description = bucket_image.twitter_description.presence || @bucket_schedule.twitter_description.presence || description
    
    begin
      # Use the SocialMediaPosterService to post to all selected platforms
      poster = SocialMediaPosterService.new(
        current_user,
        bucket_image,
        @bucket_schedule.post_to,
        description,
        twitter_description
      )
      
      results = poster.post_to_all
      
      # Create send history record
      history = @bucket_schedule.bucket_send_histories.create!(
        bucket_id: @bucket_schedule.bucket_id,
        bucket_image_id: bucket_image.id,
        friendly_name: bucket_image.friendly_name,
        text: description,
        twitter_text: twitter_description,
        sent_to: @bucket_schedule.post_to,
        sent_at: Time.current
      )
      
      # Update schedule
      @bucket_schedule.increment!(:times_sent)
      
      render json: {
        message: 'Post sent successfully',
        results: results,
        times_sent: @bucket_schedule.times_sent,
        history_id: history.id
      }
    rescue => e
      Rails.logger.error "Error posting to social media: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        error: 'Failed to post to social media',
        details: e.message
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/scheduler/skip_image/:id
  def skip_image
    @bucket_schedule.increment!(:skip_image)
    
    render json: {
      message: 'Image skipped',
      skip_count: @bucket_schedule.skip_image
    }
  end

  # POST /api/v1/scheduler/skip_image_single/:id
  def skip_image_single
    if @bucket_schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_ANNUALLY
      @bucket_schedule.update!(skip_image: 1)
    elsif @bucket_schedule.schedule_type == BucketSchedule::SCHEDULE_TYPE_ONCE
      @bucket_schedule.destroy
    end
    
    render json: { message: 'Image skipped' }
  end

  # GET /api/v1/scheduler/open_graph
  def open_graph
    url = params[:url]
    return render json: { error: 'URL required' }, status: :unprocessable_entity unless url.present?

    # This would use a gem like 'opengraph' to fetch OG data
    # For now, return a placeholder
    render json: {
      title: 'Open Graph Title',
      description: 'Open Graph Description',
      image: 'https://example.com/image.jpg',
      url: url
    }
  end

  private

  def set_bucket_schedule
    @bucket_schedule = current_user.bucket_schedules.find(params[:id])
  end

  def calculate_post_to_flags(networks)
    post_to = 0
    networks.each do |network|
      case network
      when 'facebook'
        post_to += BucketSchedule::BIT_FACEBOOK
      when 'twitter'
        post_to += BucketSchedule::BIT_TWITTER
      when 'instagram'
        post_to += BucketSchedule::BIT_INSTAGRAM
      when 'linked_in'
        post_to += BucketSchedule::BIT_LINKEDIN
      when 'google_business'
        post_to += BucketSchedule::BIT_GMB
      end
    end
    post_to
  end

  def handle_link_post(post_to)
    # Handle link sharing
    # This would integrate with social media APIs
    render json: {
      message: 'Link post scheduled',
      post_to: post_to
    }
  end

  def handle_file_post(post_to)
    # Handle file upload and posting
    file = params[:file]
    
    if video_file?(file)
      handle_video_post(file, post_to)
    else
      handle_image_post(file, post_to)
    end
  end

  def handle_video_post(file, post_to)
    # Create video record
    video = current_user.videos.create!(
      file_path: upload_file(file, 'videos'),
      friendly_name: extract_filename_without_extension(file.original_filename),
      status: Video::STATUS_PROCESSED
    )
    
    render json: {
      video: {
        id: video.id,
        file_path: video.file_path,
        source_url: video.get_source_url
      },
      message: 'Video uploaded successfully'
    }
  end

  def handle_image_post(file, post_to)
    # Get or create post-once bucket
    bucket = get_or_create_post_once_bucket
    
    # Create image and bucket_image
    image = Image.create!(
      file_path: upload_file(file, 'images'),
      friendly_name: extract_filename_without_extension(file.original_filename)
    )
    
    bucket_image = bucket.bucket_images.create!(
      image: image,
      friendly_name: image.friendly_name,
      description: params[:caption] || '',
      post_to: post_to,
      use_watermark: params[:use_watermark] == '1'
    )
    
    # Create schedule for immediate posting or scheduled posting
    if params[:scheduled_at].present?
      create_scheduled_post(bucket_image, post_to)
    else
      create_immediate_post(bucket_image, post_to)
    end
  end

  def handle_existing_image_post(post_to)
    bucket_image = BucketImage.find(params[:existing_image_id])
    
    if params[:scheduled_at].present?
      create_scheduled_post(bucket_image, post_to)
    else
      create_immediate_post(bucket_image, post_to)
    end
  end

  def get_or_create_post_once_bucket
    current_user.buckets.find_or_create_by(post_once_bucket: true) do |bucket|
      bucket.name = 'Post Now Bucket'
      bucket.description = 'Bucket where post now images go.'
      bucket.use_watermark = true
    end
  end

  def create_scheduled_post(bucket_image, post_to)
    scheduled_at = Time.parse(params[:scheduled_at])
    cron_string = build_cron_string(scheduled_at)
    
    bucket_schedule = bucket_image.bucket.bucket_schedules.create!(
      bucket_image: bucket_image,
      schedule: cron_string,
      schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
      post_to: post_to,
      description: params[:caption] || bucket_image.description,
      twitter_description: bucket_image.twitter_description
    )
    
    render json: {
      bucket_schedule: bucket_schedule_json(bucket_schedule),
      message: 'Post scheduled successfully'
    }
  end

  def create_immediate_post(bucket_image, post_to)
    # Create temporary schedule for immediate posting
    bucket_schedule = bucket_image.bucket.bucket_schedules.create!(
      bucket_image: bucket_image,
      schedule: '0 0 0 0 0', # Disabled schedule
      schedule_type: BucketSchedule::SCHEDULE_TYPE_ONCE,
      post_to: post_to,
      description: params[:caption] || bucket_image.description,
      twitter_description: bucket_image.twitter_description
    )
    
    # Process immediately (this would trigger the actual posting)
    bucket_schedule.update!(times_sent: 1)
    bucket_schedule.destroy # Remove temporary schedule
    
    render json: {
      message: 'Post sent immediately'
    }
  end

  def build_cron_string(scheduled_at)
    "#{scheduled_at.min} #{scheduled_at.hour} #{scheduled_at.day} #{scheduled_at.month} *"
  end

  def video_file?(file)
    %w[mp4].include?(file.original_filename.split('.').last.downcase)
  end

  def upload_file(file, folder)
    # This would integrate with your file storage system (Digital Ocean, AWS S3, etc.)
    # For now, return a placeholder path
    "#{folder}/#{SecureRandom.uuid}_#{file.original_filename}"
  end

  def extract_filename_without_extension(filename)
    filename.split('.').first
  end

  def bucket_schedule_json(bucket_schedule)
    {
      id: bucket_schedule.id,
      schedule: bucket_schedule.schedule,
      schedule_type: bucket_schedule.schedule_type,
      post_to: bucket_schedule.post_to,
      description: bucket_schedule.description,
      twitter_description: bucket_schedule.twitter_description,
      times_sent: bucket_schedule.times_sent,
      skip_image: bucket_schedule.skip_image,
      bucket_image_id: bucket_schedule.bucket_image_id,
      created_at: bucket_schedule.created_at,
      updated_at: bucket_schedule.updated_at
    }
  end
end
