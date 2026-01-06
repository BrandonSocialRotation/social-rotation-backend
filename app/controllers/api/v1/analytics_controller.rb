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
    # Accept platforms as array: ?platforms[]=instagram&platforms[]=facebook
    selected_platforms = params[:platforms].present? ? Array(params[:platforms]) : nil
    
    # Aggregate analytics from selected platforms (or all connected if none specified)
    metrics = {}
    
    # Determine which platforms to include
    platforms_to_fetch = if selected_platforms.present?
      selected_platforms.map(&:to_sym)
    else
      # Default: include all connected platforms
      connected_platforms = []
      connected_platforms << :instagram if current_user.instagram_business_id.present?
      connected_platforms << :facebook if current_user.fb_user_access_key.present?
      connected_platforms << :twitter if current_user.twitter_oauth_token.present?
      connected_platforms << :linkedin if current_user.linkedin_access_token.present?
      connected_platforms
    end
    
    # Instagram analytics
    if platforms_to_fetch.include?(:instagram) && current_user.instagram_business_id.present?
      begin
        service = MetaInsightsService.new(current_user)
        instagram_data = service.summary(range)
        metrics[:instagram] = instagram_data
      rescue => e
        Rails.logger.error "Instagram analytics error: #{e.message}"
      end
    end
    
    # Facebook analytics (placeholder for now)
    if platforms_to_fetch.include?(:facebook) && current_user.fb_user_access_key.present?
      metrics[:facebook] = { message: 'Facebook analytics coming soon' }
    end
    
    # Twitter analytics (placeholder for now)
    if platforms_to_fetch.include?(:twitter) && current_user.twitter_oauth_token.present?
      metrics[:twitter] = { message: 'Twitter analytics coming soon' }
    end
    
    # LinkedIn analytics (placeholder for now)
    if platforms_to_fetch.include?(:linkedin) && current_user.linkedin_access_token.present?
      metrics[:linkedin] = { message: 'LinkedIn analytics coming soon' }
    end
    
    # Aggregate totals from platforms that have actual data (not placeholders)
    valid_metrics = metrics.select { |k, v| v.is_a?(Hash) && !v[:message] }
    
    render json: {
      range: range,
      platforms: metrics,
      selected_platforms: platforms_to_fetch.map(&:to_s),
      total_engagement: valid_metrics.values.sum { |m| (m[:total_engagement] || m[:engagement_rate] || 0).to_f },
      total_likes: valid_metrics.values.sum { |m| (m[:likes] || 0).to_i },
      total_comments: valid_metrics.values.sum { |m| (m[:comments] || 0).to_i },
      total_shares: valid_metrics.values.sum { |m| (m[:shares] || 0).to_i },
      total_followers: valid_metrics.values.sum { |m| (m[:followers] || 0).to_i },
      engagement_rate: calculate_engagement_rate(valid_metrics)
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
  
  private
  
  def calculate_engagement_rate(metrics)
    return nil if metrics.empty?
    
    total_engagement = metrics.values.sum { |m| (m[:total_engagement] || 0).to_f }
    total_reach = metrics.values.sum { |m| (m[:reach] || 0).to_i }
    
    return nil if total_reach == 0
    
    ((total_engagement / total_reach) * 100).round(2)
  end
end
