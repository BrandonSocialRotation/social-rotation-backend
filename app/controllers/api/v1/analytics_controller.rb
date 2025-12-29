class Api::V1::AnalyticsController < ApplicationController
  def instagram_summary
    range = params[:range].presence || '7d'
    service = MetaInsightsService.new(current_user)
    data = service.summary(range)
    render json: { range: range, metrics: data }
  end

  def instagram_timeseries
    metric = params[:metric].presence || 'reach'
    range = params[:range].presence || '28d'
    service = MetaInsightsService.new(current_user)
    data = service.timeseries(metric, range)
    render json: { metric: metric, range: range, points: data }
  end

  # GET /api/v1/analytics/platform/:platform
  def platform_analytics
    platform = params[:platform]
    range = params[:range].presence || '7d'
    
    case platform
    when 'instagram'
      service = MetaInsightsService.new(current_user)
      data = service.summary(range)
      render json: { platform: platform, range: range, metrics: data }
    when 'facebook', 'twitter', 'linkedin'
      # Placeholder for other platforms - return empty data for now
      render json: {
        platform: platform,
        range: range,
        metrics: {},
        message: "#{platform.capitalize} analytics coming soon"
      }
    else
      render json: { error: "Unknown platform: #{platform}" }, status: :bad_request
    end
  end

  # GET /api/v1/analytics/overall
  def overall
    range = params[:range].presence || '7d'
    
    # Aggregate analytics from all connected platforms
    metrics = {}
    
    # Instagram analytics
    if current_user.instagram_business_id.present?
      begin
        service = MetaInsightsService.new(current_user)
        instagram_data = service.summary(range)
        metrics[:instagram] = instagram_data
      rescue => e
        Rails.logger.error "Instagram analytics error: #{e.message}"
      end
    end
    
    render json: {
      range: range,
      platforms: metrics,
      total_engagement: metrics.values.sum { |m| m[:total_engagement] || 0 },
      total_likes: metrics.values.sum { |m| m[:likes] || 0 },
      total_comments: metrics.values.sum { |m| m[:comments] || 0 },
      total_shares: metrics.values.sum { |m| m[:shares] || 0 },
      total_clicks: metrics.values.sum { |m| m[:clicks] || 0 }
    }
  end

  # GET /api/v1/analytics/posts_count
  def posts_count
    # Count all posts made by the user from the app
    # Posts are tracked in bucket_send_histories through the user's buckets
    bucket_ids = current_user.buckets.pluck(:id)
    total_posts = BucketSendHistory.where(bucket_id: bucket_ids).count
    
    # Count posts in the last 7 days
    posts_last_7d = BucketSendHistory.where(bucket_id: bucket_ids)
                                      .where('sent_at >= ?', 7.days.ago)
                                      .count
    
    # Count posts in the last 30 days
    posts_last_30d = BucketSendHistory.where(bucket_id: bucket_ids)
                                      .where('sent_at >= ?', 30.days.ago)
                                      .count
    
    render json: {
      total_posts: total_posts,
      posts_last_7d: posts_last_7d,
      posts_last_30d: posts_last_30d
    }
  end
end
