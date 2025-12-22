class Api::V1::RssPostsController < ApplicationController
  include JsonSerializers
  
  before_action :authenticate_user!
  before_action :require_rss_access!
  before_action :set_rss_post, only: [:show, :update, :mark_viewed, :mark_unviewed, :schedule_post]

  # GET /api/v1/rss_posts
  def index
    # Get all RSS posts for the user's account
    if current_user.super_admin?
      @posts = RssPost.includes(:rss_feed).recent
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).includes(:rss_feed).recent
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).includes(:rss_feed).recent
    end

    # Apply filters
    apply_filters

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 20
    total_posts = @posts.count
    @posts = @posts.offset((page - 1) * per_page).limit(per_page)

    render json: {
      posts: @posts.map { |post| rss_post_json(post) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total_posts,
        total_pages: (total_posts.to_f / per_page).ceil
      }
    }
  end

  # GET /api/v1/rss_posts/:id
  def show
    render json: {
      post: rss_post_json(@rss_post),
      rss_feed: {
        id: @rss_post.rss_feed.id,
        name: @rss_post.rss_feed.name,
        url: @rss_post.rss_feed.url
      }
    }
  end

  # PATCH/PUT /api/v1/rss_posts/:id
  def update
    if @rss_post.update(rss_post_params)
      render json: {
        post: rss_post_json(@rss_post),
        message: 'RSS post updated successfully'
      }
    else
      render json: {
        errors: @rss_post.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/rss_posts/:id/mark_viewed
  def mark_viewed
    @rss_post.mark_as_viewed!
    
    render json: {
      post: rss_post_json(@rss_post),
      message: 'RSS post marked as viewed'
    }
  end

  # POST /api/v1/rss_posts/:id/mark_unviewed
  def mark_unviewed
    @rss_post.update!(is_viewed: false)
    
    render json: {
      post: rss_post_json(@rss_post),
      message: 'RSS post marked as unviewed'
    }
  end

  # POST /api/v1/rss_posts/bulk_mark_viewed
  def bulk_mark_viewed
    post_ids = params[:post_ids] || []
    
    if post_ids.empty?
      return render json: { error: 'No post IDs provided' }, status: :bad_request
    end
    
    # Get posts the user has access to
    if current_user.super_admin?
      posts = RssPost.where(id: post_ids)
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      posts = RssPost.where(id: post_ids, rss_feed_id: feed_ids)
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      posts = RssPost.where(id: post_ids, rss_feed_id: feed_ids)
    end
    
    count = posts.update_all(is_viewed: true)
    
    render json: {
      message: "Marked #{count} posts as viewed",
      count: count
    }
  end

  # POST /api/v1/rss_posts/bulk_mark_unviewed
  def bulk_mark_unviewed
    post_ids = params[:post_ids] || []
    
    if post_ids.empty?
      return render json: { error: 'No post IDs provided' }, status: :bad_request
    end
    
    # Get posts the user has access to
    if current_user.super_admin?
      posts = RssPost.where(id: post_ids)
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      posts = RssPost.where(id: post_ids, rss_feed_id: feed_ids)
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      posts = RssPost.where(id: post_ids, rss_feed_id: feed_ids)
    end
    
    count = posts.update_all(is_viewed: false)
    
    render json: {
      message: "Marked #{count} posts as unviewed",
      count: count
    }
  end

  # POST /api/v1/rss_posts/:id/schedule_post
  def schedule_post
    begin
      # Create a new bucket for this RSS post
      bucket = current_user.buckets.create!(
        name: @rss_post.short_title(50),
        description: @rss_post.short_description(200),
        account_id: current_user.account_id
      )
      
      # Add the RSS post image to the bucket if it exists
      if @rss_post.has_image?
        # Create an Image record first
        image = Image.create!(
          file_path: @rss_post.image_url, # Store the URL as file_path for now
          friendly_name: @rss_post.short_title(30)
        )
        
        # Then create the BucketImage association
        bucket_image = bucket.bucket_images.create!(
          image: image,
          friendly_name: @rss_post.short_title(30)
        )
      end
      
      # Create a default schedule for the bucket (post once per day)
      # Set up a simple daily schedule at 12:00 PM
      cron_string = "0 12 * * 1,2,3,4,5,6,7" # Every day at 12:00 PM
      post_to = BucketSchedule::BIT_FACEBOOK | BucketSchedule::BIT_TWITTER # Post to Facebook and Twitter
      
      bucket_schedule = bucket.bucket_schedules.create!(
        schedule: cron_string,
        schedule_type: BucketSchedule::SCHEDULE_TYPE_ROTATION,
        post_to: post_to,
        description: @rss_post.short_description(200)
      )
      
      # Mark the RSS post as viewed
      @rss_post.mark_as_viewed!
      
      render json: {
        post: rss_post_json(@rss_post),
        bucket: {
          id: bucket.id,
          name: bucket.name,
          description: bucket.description
        },
        bucket_schedule: {
          id: bucket_schedule.id,
          schedule_type: bucket_schedule.schedule_type,
          schedule: bucket_schedule.schedule,
          post_to: bucket_schedule.post_to
        },
        message: "RSS post scheduled successfully! Created bucket '#{bucket.name}' with daily posting at 12:00 PM to Facebook and Twitter."
      }
    rescue StandardError => e
      Rails.logger.error "Error scheduling RSS post: #{e.message}"
      render json: {
        error: "Failed to schedule RSS post: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/rss_posts/unviewed
  def unviewed
    if current_user.super_admin?
      @posts = RssPost.unviewed.includes(:rss_feed).recent
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).unviewed.includes(:rss_feed).recent
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).unviewed.includes(:rss_feed).recent
    end

    render json: {
      posts: @posts.map { |post| rss_post_json(post) }
    }
  end

  # GET /api/v1/rss_posts/recent
  def recent
    if current_user.super_admin?
      @posts = RssPost.recent.includes(:rss_feed).limit(10)
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).recent.includes(:rss_feed).limit(10)
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      @posts = RssPost.where(rss_feed_id: feed_ids).recent.includes(:rss_feed).limit(10)
    end

    render json: {
      posts: @posts.map { |post| rss_post_json(post) }
    }
  end

  private

  def set_rss_post
    if current_user.super_admin?
      @rss_post = RssPost.find(params[:id])
    elsif current_user.account_id
      feed_ids = current_user.account.rss_feeds.pluck(:id)
      @rss_post = RssPost.where(rss_feed_id: feed_ids).find(params[:id])
    else
      feed_ids = current_user.rss_feeds.pluck(:id)
      @rss_post = RssPost.where(rss_feed_id: feed_ids).find(params[:id])
    end
  end

  def require_rss_access!
    unless current_user.can_access_rss_feeds?
      render json: { error: 'RSS access not allowed for this account' }, status: :forbidden
    end
  end

  def apply_filters
    # Filter by viewed status
    case params[:viewed]
    when 'true'
      @posts = @posts.viewed
    when 'false'
      @posts = @posts.unviewed
    end

    # Filter by RSS feed
    if params[:rss_feed_id].present?
      @posts = @posts.where(rss_feed_id: params[:rss_feed_id])
    end

    # Filter by date range
    if params[:start_date].present?
      begin
        start_time = Time.parse(params[:start_date])
      rescue
        start_time = Date.parse(params[:start_date]).beginning_of_day
      end
      @posts = @posts.where('published_at >= ?', start_time)
    end

    if params[:end_date].present?
      begin
        end_time = Time.parse(params[:end_date])
        # If the parsed time is at the start of day (00:00:00), it might be from beginning_of_day
        # In that case, use end_of_day for that date to include the entire day
        if end_time.hour == 0 && end_time.min == 0 && end_time.sec == 0
          end_time = end_time.end_of_day
        end
      rescue
        end_time = Date.parse(params[:end_date]).end_of_day
      end
      @posts = @posts.where('published_at <= ?', end_time)
    end

    # Filter by search term
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @posts = @posts.where('title ILIKE ? OR description ILIKE ?', search_term, search_term)
    end

    # Filter by has image
    if params[:has_image] == 'true'
      @posts = @posts.with_images
    end
  end

  def rss_post_params
    params.require(:rss_post).permit(:title, :description, :content, :image_url)
  end

  def rss_post_json(post)
    super(post).merge(rss_feed: {
      id: post.rss_feed.id,
      name: post.rss_feed.name,
      url: post.rss_feed.url
    })
  end
end
