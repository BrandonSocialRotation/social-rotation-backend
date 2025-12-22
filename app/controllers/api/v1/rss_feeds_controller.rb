class Api::V1::RssFeedsController < ApplicationController
  include JsonSerializers
  
  before_action :authenticate_user!
  before_action :require_rss_access!
  before_action :set_rss_feed, only: [:show, :update, :destroy, :fetch_posts, :posts]
  
  def fetch_all
    # Trigger background job to fetch all active RSS feeds
    RssFeedFetchJob.perform_later
    
    render json: {
      message: 'RSS feed automation triggered. All active feeds will be fetched in the background.',
      queued_at: Time.current
    }
  end

  # POST /api/v1/rss_feeds/validate
  def validate
    url = params[:url]
    
    unless url.present?
      return render json: { valid: false, error: 'URL is required' }, status: :bad_request
    end
    
    begin
      # Try to fetch and parse the feed
      feed_obj = OpenStruct.new(url: url)
      service = RssFetchService.new(feed_obj)
      content = service.send(:fetch_rss_content)
      
      if content.blank?
        render json: { valid: false, error: 'Unable to fetch feed. Check if the URL is accessible.' }
        return
      end
      
      # Try to parse it
      posts = service.send(:parse_rss_content, content)
      
      if posts.present?
        render json: { 
          valid: true, 
          message: "Valid RSS feed with #{posts.length} posts found",
          preview: posts.first(3).map { |p| { title: p[:title], description: p[:description]&.truncate(100) } }
        }
      else
        render json: { valid: false, error: 'Feed found but no posts could be parsed' }
      end
    rescue StandardError => e
      render json: { valid: false, error: "Feed validation failed: #{e.message}" }
    end
  end

  # GET /api/v1/rss_feeds
  def index
    if current_user.super_admin?
      @rss_feeds = RssFeed.includes(:account, :user).order(:created_at)
    elsif current_user.account_id
      @rss_feeds = current_user.account.rss_feeds.includes(:user).order(:created_at)
    else
      @rss_feeds = current_user.rss_feeds.includes(:user).order(:created_at)
    end

    render json: {
      rss_feeds: @rss_feeds.map { |feed| rss_feed_json(feed) }
    }
  end

  # GET /api/v1/rss_feeds/:id
  def show
    render json: {
      rss_feed: rss_feed_json(@rss_feed),
      recent_posts: @rss_feed.latest_posts(5).map { |post| rss_post_json(post) }
    }
  end

  # POST /api/v1/rss_feeds
  def create
    @rss_feed = current_user.rss_feeds.build(rss_feed_params)
    @rss_feed.account_id = current_user.account_id if current_user.account_id

    if @rss_feed.save
      render json: {
        rss_feed: rss_feed_json(@rss_feed),
        message: 'RSS feed created successfully'
      }, status: :created
    else
      render json: {
        errors: @rss_feed.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/rss_feeds/:id
  def update
    if @rss_feed.update(rss_feed_params)
      render json: {
        rss_feed: rss_feed_json(@rss_feed),
        message: 'RSS feed updated successfully'
      }
    else
      render json: {
        errors: @rss_feed.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/rss_feeds/:id
  def destroy
    @rss_feed.destroy
    render json: { message: 'RSS feed deleted successfully' }
  end

  # POST /api/v1/rss_feeds/:id/fetch_posts
  def fetch_posts
    begin
      # Use the RSS fetch service to actually fetch and parse content
      service = RssFetchService.new(@rss_feed)
      result = service.fetch_and_parse
      
      if result[:success]
        @rss_feed.record_success!
        render json: {
          message: result[:message],
          posts_found: result[:posts_found],
          posts_saved: result[:posts_saved],
          last_fetched: @rss_feed.reload.last_fetched_at
        }
      else
        @rss_feed.record_failure!(result[:error])
        render json: {
          error: result[:error]
        }, status: :unprocessable_entity
      end
    rescue StandardError => e
      @rss_feed.record_failure!(e.message)
      Rails.logger.error "RSS fetch error: #{e.message}"
      render json: {
        error: 'Failed to fetch RSS feed: ' + e.message
      }, status: :internal_server_error
    end
  end

  # GET /api/v1/rss_feeds/:id/posts
  def posts
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 20
    viewed_filter = params[:viewed]

    @posts = @rss_feed.rss_posts.recent

    # Filter by viewed status
    case viewed_filter
    when 'true'
      @posts = @posts.viewed
    when 'false'
      @posts = @posts.unviewed
    end

    # Pagination
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

  private

  def set_rss_feed
    if current_user.super_admin?
      @rss_feed = RssFeed.find(params[:id])
    elsif current_user.account_id
      @rss_feed = current_user.account.rss_feeds.find(params[:id])
    else
      @rss_feed = current_user.rss_feeds.find(params[:id])
    end
  end

  def require_rss_access!
    unless current_user.can_access_rss_feeds?
      render json: { error: 'RSS access not allowed for this account' }, status: :forbidden
    end
  end

  def rss_feed_params
    params.require(:rss_feed).permit(:url, :name, :description, :is_active)
  end

end
