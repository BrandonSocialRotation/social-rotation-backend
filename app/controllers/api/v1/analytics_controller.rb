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
    
    # LinkedIn analytics
    if platforms_to_fetch.include?(:linkedin) && current_user.linkedin_access_token.present?
      begin
        linkedin_data = fetch_linkedin_analytics(current_user, range)
        metrics[:linkedin] = linkedin_data
      rescue => e
        Rails.logger.error "LinkedIn analytics error: #{e.message}"
        metrics[:linkedin] = { message: 'LinkedIn analytics unavailable' }
      end
    end
    
    # Aggregate totals from platforms that have actual data (not placeholders)
    # Include platforms with errors if they have follower data (like Twitter rate limit)
    valid_metrics = metrics.select { |k, v| v.is_a?(Hash) && (!v[:message] || v[:followers].present?) }
    
    # For followers, include ALL platforms that have follower data, even if they have errors
    all_platforms_with_followers = metrics.select { |k, v| v.is_a?(Hash) && v[:followers].present? }
    
    render json: {
      range: range,
      platforms: metrics,
      selected_platforms: platforms_to_fetch.map(&:to_s),
      total_engagement: valid_metrics.values.sum { |m| (m[:total_engagement] || m[:engagement_rate] || 0).to_f },
      total_likes: valid_metrics.values.sum { |m| (m[:likes] || 0).to_i },
      total_comments: valid_metrics.values.sum { |m| (m[:comments] || 0).to_i },
      total_shares: valid_metrics.values.sum { |m| (m[:shares] || 0).to_i },
      total_followers: all_platforms_with_followers.values.sum { |m| (m[:followers] || 0).to_i },
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
      begin
        response = access_token.get('/2/users/me?user.fields=public_metrics')
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          user_id = data.dig('data', 'id')
          # Store user_id for future use
          if user_id.present?
            user.update_column(:twitter_user_id, user_id)
            Rails.logger.info "Twitter analytics: Stored user_id: #{user_id}"
          end
        else
          Rails.logger.warn "Twitter API error fetching user_id: #{response.code} - #{response.body}"
        end
      rescue => e
        Rails.logger.error "Twitter API exception fetching user_id: #{e.message}"
      end
    end
    
    unless user_id.present?
      Rails.logger.error "Twitter analytics: No user_id available (stored: #{user.twitter_user_id.present?}, fetched: false)"
      return { 
        message: 'Could not fetch Twitter user ID. Please reconnect your Twitter account.',
        followers: 0,
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    end
    
    Rails.logger.info "Twitter analytics: Using user_id: #{user_id}"
    
    # Try to get cached follower count first (cache for 1 hour)
    cache_key = "twitter_followers_#{user_id}"
    cached_followers = Rails.cache.read(cache_key)
    
    # Get user metrics using Twitter API v2
    response = access_token.get("/2/users/#{user_id}?user.fields=public_metrics")
    
    followers = 0
    rate_limited = false
    
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      Rails.logger.info "Twitter user metrics response: #{data.inspect}"
      
      public_metrics = data.dig('data', 'public_metrics') || {}
      followers = public_metrics['followers_count']&.to_i || 0
      
      # Cache the follower count for 1 hour
      if followers > 0
        Rails.cache.write(cache_key, followers, expires_in: 1.hour)
        Rails.logger.info "Twitter analytics: Cached follower count: #{followers} for user #{user_id}"
      end
      
      Rails.logger.info "Twitter analytics: Fetched follower count: #{followers} for user #{user_id} (public_metrics: #{public_metrics.inspect})"
    else
      # Handle rate limit or other errors
      error_data = parse_twitter_error(response)
      Rails.logger.warn "Twitter API error fetching user metrics (#{response.code}): #{error_data[:message]}"
      
      # If it's a rate limit (429), use cached value if available
      if response.code == '429'
        rate_limited = true
        if cached_followers.present?
          followers = cached_followers.to_i
          Rails.logger.info "Twitter rate limit (429) - using cached follower count: #{followers}"
        else
          Rails.logger.warn "Twitter rate limit on user metrics endpoint (429). No cached followers available."
        end
      else
        # For other errors, try cached value, otherwise return early
        if cached_followers.present?
          followers = cached_followers.to_i
          Rails.logger.info "Twitter API error - using cached follower count: #{followers}"
        else
          return { 
            message: error_data[:message] || 'Failed to fetch Twitter analytics',
            followers: 0,
            likes: 0,
            comments: 0,
            shares: 0,
            engagement_rate: nil,
            total_engagement: 0
          }
        end
      end
    end
    
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
    
    # If we got rate limited on user metrics, return early with helpful message
    if rate_limited
      return {
        message: 'Twitter API rate limit reached',
        error_code: 'TWITTER_RATE_LIMIT',
        error_details: 'Twitter API rate limit exceeded. Please wait 15 minutes and try again, or upgrade to Twitter API Basic for higher limits.',
        followers: followers, # Will be 0 if we couldn't fetch it
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    end
    
    # Fetch tweets in the time range
    tweets_data = fetch_twitter_tweets(access_token, user_id, start_time, end_time)
    
    # Check for rate limit errors on tweet fetching
    if tweets_data[:error] == 'monthly_cap'
      Rails.logger.warn "Twitter monthly cap reached on tweet fetching (followers: #{followers})"
      return {
        message: 'Twitter API monthly limit reached',
        error_code: 'TWITTER_MONTHLY_LIMIT',
        error_details: 'You have reached your monthly limit of 100 tweets. Please upgrade to Twitter API Basic ($100/month) for unlimited analytics, or wait until your limit resets.',
        followers: followers, # Include followers if we got them
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    elsif tweets_data[:error] == 'rate_limit_429'
      Rails.logger.warn "Twitter temporary rate limit (429) on tweet fetching (followers: #{followers})"
      return {
        message: 'Twitter API rate limit exceeded',
        error_code: 'TWITTER_RATE_LIMIT',
        error_details: tweets_data[:message] || 'Twitter API rate limit exceeded. Please wait 15 minutes and try again, or upgrade to Twitter API Basic for higher limits.',
        followers: followers, # Include followers if we got them
        likes: 0,
        comments: 0,
        shares: 0,
        engagement_rate: nil,
        total_engagement: 0
      }
    end
    
    if tweets_data[:error]
      Rails.logger.warn "Twitter tweet fetch error: #{tweets_data[:error]}, but returning follower count: #{followers}"
      return {
        message: tweets_data[:error],
        followers: followers, # Always include followers even with errors
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
        # Twitter API v2 returns 429 for BOTH rate limits AND monthly caps, but with different titles
        if response.code == '429'
          Rails.logger.warn "Twitter API 429 error: #{response.body}"
          error_data = JSON.parse(response.body) rescue {}
          
          # Check the title to distinguish between rate limit and monthly cap
          error_title = error_data['title'] || ''
          error_detail = error_data['detail'] || ''
          
          # Monthly cap has "UsageCapExceeded" title
          if error_title.include?('UsageCapExceeded') || error_detail.include?('Monthly product cap') || error_detail.include?('monthly')
            Rails.logger.warn "Twitter monthly cap detected from error response"
            return { error: 'monthly_cap' }
          else
            # Regular rate limit (429) - "Too Many Requests"
            Rails.logger.warn "Twitter temporary rate limit (429) detected"
            return { error: 'rate_limit_429', message: 'Twitter API rate limit exceeded. Please wait 15 minutes and try again.' }
          end
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
      
      # Check for monthly cap (UsageCapExceeded)
      if error_data['title'] == 'UsageCapExceeded' || error_data['detail']&.include?('Monthly product cap')
        return {
          message: 'Twitter API monthly limit reached',
          error_code: 'TWITTER_MONTHLY_LIMIT'
        }
      end
      
      # Check for rate limit (Too Many Requests)
      if error_data['title'] == 'Too Many Requests' || response.code == '429'
        return {
          message: 'Twitter API rate limit exceeded',
          error_code: 'TWITTER_RATE_LIMIT'
        }
      end
      
      error_obj = error_data['errors']&.first || error_data['error']
      
      if error_obj.is_a?(Hash)
        error_code = error_obj['code'] || error_obj['type']
        error_message = error_obj['message'] || error_obj['detail']
        
        return { message: error_message || 'Twitter API error' }
      end
      
      { message: error_data['detail'] || error_data['title'] || "Twitter API error: #{response.code}" }
    rescue
      { message: "Twitter API error: #{response.code}" }
    end
  end

  def fetch_linkedin_analytics(user, range)
    unless user.linkedin_access_token.present?
      return { message: 'LinkedIn not connected' }
    end

    begin
      # Get organization URN - try to get from stored data or fetch it
      org_urn = nil
      org_id = nil
      
      # Try to get organization from user's stored data or fetch organizations
      linkedin_service = SocialMedia::LinkedinService.new(user)
      organizations = linkedin_service.fetch_organizations
      
      if organizations.empty?
        Rails.logger.warn "LinkedIn analytics: No organizations found for user #{user.id}"
        return {
          message: 'No LinkedIn Company Page found. LinkedIn analytics require a Company Page.',
          followers: 0,
          likes: 0,
          comments: 0,
          shares: 0,
          engagement_rate: nil,
          total_engagement: 0
        }
      end
      
      # Use the first organization (or we could let user select)
      org = organizations.first
      org_id = org[:id]
      org_urn = org[:urn] || "urn:li:organization:#{org_id}"
      
      Rails.logger.info "LinkedIn analytics: Using organization #{org_id} (#{org[:name]})"
      
      # Get follower count using networkSizes endpoint (doesn't require Community Management API)
      headers = {
        'Authorization' => "Bearer #{user.linkedin_access_token}",
        'X-Restli-Protocol-Version' => '2.0.0'
      }
      
      # Use networkSizes endpoint - works with r_organization_social scope (no Community Management API needed)
      network_sizes_url = "https://api.linkedin.com/v2/networkSizes/#{org_urn}"
      network_params = {
        edgeType: 'COMPANY_FOLLOWED_BY_MEMBER'  # Get followers count
      }
      
      follower_response = HTTParty.get(network_sizes_url, headers: headers, query: network_params)
      
      followers = 0
      if follower_response.success?
        follower_data = JSON.parse(follower_response.body)
        Rails.logger.info "LinkedIn networkSizes response: #{follower_data.inspect}"
        
        # Extract follower count - firstDegreeSize is the total follower count
        followers = follower_data['firstDegreeSize']&.to_i || 0
        
        Rails.logger.info "LinkedIn analytics: Fetched follower count: #{followers} for organization #{org_id}"
      else
        Rails.logger.warn "LinkedIn networkSizes error: #{follower_response.code} - #{follower_response.body}"
        
        # If networkSizes fails, try the organization endpoint to get basic info
        # (though it might not have follower count)
        begin
          org_url = "https://api.linkedin.com/v2/organizations/#{org_id}"
          org_response = HTTParty.get(org_url, headers: headers)
          if org_response.success?
            org_data = JSON.parse(org_response.body)
            Rails.logger.info "LinkedIn organization response: #{org_data.inspect}"
            # Organization endpoint doesn't typically include follower count, but worth checking
          end
        rescue => e
          Rails.logger.warn "LinkedIn organization endpoint error: #{e.message}"
        end
      end
      
      # Get share statistics for engagement metrics
      # Note: LinkedIn API doesn't provide easy access to likes/comments/shares like Instagram
      # We'd need to fetch individual posts and aggregate, which is complex
      # For now, return follower count and placeholder engagement metrics
      
      {
        followers: followers,
        likes: 0,  # LinkedIn API doesn't provide easy aggregated likes
        comments: 0,  # LinkedIn API doesn't provide easy aggregated comments
        shares: 0,  # LinkedIn API doesn't provide easy aggregated shares
        engagement_rate: nil,
        total_engagement: 0
      }
    rescue => e
      Rails.logger.error "LinkedIn analytics exception: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { message: 'LinkedIn analytics error' }
    end
  end
end
