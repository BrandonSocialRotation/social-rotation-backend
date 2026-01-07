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
    
    # Twitter analytics
    if platforms_to_fetch.include?(:twitter) && current_user.twitter_oauth_token.present?
      begin
        twitter_data = fetch_twitter_analytics(current_user, range)
        metrics[:twitter] = twitter_data
      rescue => e
        Rails.logger.error "Twitter analytics error: #{e.message}"
        metrics[:twitter] = { message: 'Twitter analytics unavailable' }
      end
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

  def fetch_twitter_analytics(user, range)
    require 'oauth'
    
    consumer_key = ENV['TWITTER_API_KEY']
    consumer_secret = ENV['TWITTER_API_SECRET_KEY']
    
    unless consumer_key.present? && consumer_secret.present?
      return { message: 'Twitter API credentials not configured' }
    end
    
    unless user.twitter_oauth_token.present? && user.twitter_oauth_token_secret.present?
      return { message: 'Twitter not connected' }
    end
    
    # Create OAuth consumer
    consumer = ::OAuth::Consumer.new(
      consumer_key,
      consumer_secret,
      site: 'https://api.twitter.com'
    )
    
    # Create access token
    access_token = ::OAuth::AccessToken.new(
      consumer,
      user.twitter_oauth_token,
      user.twitter_oauth_token_secret
    )
    
    # Get user ID (use twitter_user_id if available, otherwise fetch it)
    user_id = user.twitter_user_id
    
    unless user_id.present?
      # Fetch user ID from Twitter API
      response = access_token.get('/2/users/me?user.fields=public_metrics')
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        user_id = data.dig('data', 'id')
        # Store user_id for future use
        user.update_column(:twitter_user_id, user_id) if user_id.present?
      end
    end
    
    return { message: 'Could not fetch Twitter user ID' } unless user_id.present?
    
    # Get user metrics using Twitter API v2
    response = access_token.get("/2/users/#{user_id}?user.fields=public_metrics")
    
    unless response.is_a?(Net::HTTPSuccess)
      error_data = parse_twitter_error(response)
      return error_data if error_data[:message]
      Rails.logger.error "Twitter API error: #{response.body}"
      return { message: 'Failed to fetch Twitter analytics' }
    end
    
    data = JSON.parse(response.body)
    public_metrics = data.dig('data', 'public_metrics') || {}
    followers = public_metrics['followers_count']&.to_i || 0
    
    # Calculate time range for tweets
    end_time = Time.now
    start_time = case range.to_s
                 when '24h'
                   end_time - 24.hours
                 when '30d'
                   end_time - 30.days
                 else
                   end_time - 7.days
                 end
    
    # Fetch tweets in the time range
    tweets_data = fetch_twitter_tweets(access_token, user_id, start_time, end_time)
    
    # Check for rate limit errors
    if tweets_data[:error] == 'rate_limit'
      return {
        message: 'Twitter API monthly limit reached',
        error_code: 'TWITTER_MONTHLY_LIMIT',
        error_details: 'You have reached your monthly limit of 100 tweets. Please upgrade to Twitter API Basic ($100/month) for unlimited analytics, or wait until your limit resets.',
        followers: followers,
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    end
    
    if tweets_data[:error]
      return {
        message: tweets_data[:error],
        followers: followers,
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    end
    
    # Aggregate metrics from tweets
    total_likes = tweets_data[:likes] || 0
    total_comments = tweets_data[:comments] || 0
    total_shares = tweets_data[:shares] || 0
    total_engagement = total_likes + total_comments + total_shares
    
    # Calculate engagement rate
    engagement_rate = if followers > 0
      ((total_engagement.to_f / followers) * 100).round(2)
    else
      nil
    end
    
    {
      followers: followers,
      likes: total_likes,
      comments: total_comments,
      shares: total_shares,
      engagement_rate: engagement_rate,
      total_engagement: total_engagement
    }
  rescue => e
    Rails.logger.error "Twitter analytics exception: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { message: 'Twitter analytics error' }
  end

  def fetch_twitter_tweets(access_token, user_id, start_time, end_time)
    total_likes = 0
    total_comments = 0
    total_shares = 0
    next_token = nil
    request_count = 0
    max_requests = 5 # Limit requests to conserve monthly API quota (100 tweets/month on Free tier)
    
    begin
      # Fetch tweets with pagination - get metrics directly in the first call to save API quota
      loop do
        request_count += 1
        break if request_count > max_requests
        
        url = "/2/users/#{user_id}/tweets"
        params = {
          max_results: 100, # Max per request
          start_time: start_time.iso8601,
          end_time: end_time.iso8601,
          'tweet.fields' => 'id,created_at,public_metrics' # Get metrics in the same call
        }
        params[:pagination_token] = next_token if next_token.present?
        
        # Build query string
        query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
        response = access_token.get("#{url}?#{query_string}")
        
        # Check for rate limit errors (429 = Too Many Requests)
        if response.code == '429'
          Rails.logger.warn "Twitter API rate limit hit: #{response.body}"
          error_data = JSON.parse(response.body) rescue {}
          # Check if it's monthly cap (status 429 with specific error)
          if error_data.dig('status') == 429 || response.body.include?('limit') || response.body.include?('cap')
            return { error: 'rate_limit' }
          end
          # If it's a temporary rate limit, wait a bit and retry once
          sleep(1)
          next
        end
        
        unless response.is_a?(Net::HTTPSuccess)
          error_data = parse_twitter_error(response)
          Rails.logger.error "Twitter API error (#{response.code}): #{error_data[:message]}"
          return { error: error_data[:message] || 'Failed to fetch tweets' }
        end
        
        data = JSON.parse(response.body)
        tweets = data['data'] || []
        
        # Aggregate metrics directly from the response (no need for second API call!)
        tweets.each do |tweet|
          metrics = tweet['public_metrics'] || {}
          total_likes += metrics['like_count']&.to_i || 0
          total_comments += metrics['reply_count']&.to_i || 0
          # Shares = retweets + quote tweets
          total_shares += (metrics['retweet_count']&.to_i || 0) + (metrics['quote_count']&.to_i || 0)
        end
        
        Rails.logger.info "Twitter analytics: Fetched #{tweets.length} tweets, Total so far - Likes: #{total_likes}, Comments: #{total_comments}, Shares: #{total_shares}"
        
        # Check pagination
        next_token = data.dig('meta', 'next_token')
        break unless next_token.present?
        
        # Safety limit to prevent excessive API usage
        break if (total_likes + total_comments + total_shares) > 0 && request_count >= max_requests
      end
      
      Rails.logger.info "Twitter analytics final totals - Likes: #{total_likes}, Comments: #{total_comments}, Shares: #{total_shares}"
      
      { likes: total_likes, comments: total_comments, shares: total_shares }
    rescue JSON::ParserError => e
      Rails.logger.error "Twitter API JSON parse error: #{e.message}"
      { error: 'Failed to parse Twitter API response' }
    rescue => e
      Rails.logger.error "Error fetching Twitter tweets: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: 'Failed to fetch tweet metrics' }
    end
  end

  def parse_twitter_error(response)
    begin
      error_data = JSON.parse(response.body)
      error_obj = error_data['errors']&.first || error_data['error']
      
      if error_obj.is_a?(Hash)
        error_code = error_obj['code'] || error_obj['type']
        error_message = error_obj['message'] || error_obj['detail']
        
        # Check for monthly cap error
        if error_code == 429 || error_message&.include?('limit') || error_message&.include?('cap')
          return {
            message: 'Twitter API monthly limit reached',
            error_code: 'TWITTER_MONTHLY_LIMIT'
          }
        end
        
        return { message: error_message || 'Twitter API error' }
      end
      
      { message: error_obj.to_s }
    rescue
      { message: "Twitter API error: #{response.code}" }
    end
  end
end
