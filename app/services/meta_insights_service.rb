class MetaInsightsService
  # Placeholder service for Instagram insights via Meta Graph API
  # Swaps to real API when credentials and tokens are present

  def initialize(user)
    @user = user
  end

  # Returns aggregate metrics for a given range (e.g., '7d', '28d')
  def summary(range)
    cached("ig_summary_#{@user.id}_#{range}", 15.minutes) do
      if live_available?
        fetch_live_summary(range)
      else
        mock_summary(range)
      end
    end
  end

  # Returns [{date:, value:}] points for metric over range
  def timeseries(metric, range)
    cached("ig_ts_#{@user.id}_#{metric}_#{range}", 15.minutes) do
      if live_available?
        fetch_live_timeseries(metric, range)
      else
        mock_timeseries(metric, range)
      end
    end
  end

  private

  def live_available?
    @user.instagram_business_id.present? && @user.fb_user_access_key.present?
  end

  def fetch_live_summary(range)
    unless live_available?
      Rails.logger.warn "MetaInsightsService: Live data not available - instagram_business_id: #{@user.instagram_business_id.present?}, fb_user_access_key: #{@user.fb_user_access_key.present?}"
      return mock_summary(range)
    end
    
    begin
      page_token = get_page_access_token
      unless page_token
        Rails.logger.warn "MetaInsightsService: Could not get page access token for user #{@user.id}"
        return mock_summary(range)
      end
      
      period = 'day'
      # Get Hootsuite-style metrics (removed impressions and reach as requested)
      # Note: Instagram API uses 'saves' not 'saved'
      metric_list = 'likes,comments,saves,profile_views,website_clicks'
      
      # Get insights for the specified range
      insights_url = "https://graph.facebook.com/v18.0/#{@user.instagram_business_id}/insights"
      insights_params = {
        metric: metric_list,
        period: period,
        access_token: page_token
      }
      
      # Add date range
      case range.to_s
      when '24h'
        insights_params[:since] = 24.hours.ago.to_i
        insights_params[:until] = Time.now.to_i
      when '30d'
        insights_params[:since] = 30.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      when '28d'
        insights_params[:since] = 28.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      else
        # Default to 7 days
        insights_params[:since] = 7.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      end
      
      response = HTTParty.get(insights_url, query: insights_params)
      
      unless response.success?
        error_body = response.body
        Rails.logger.error "Instagram Insights API error: #{error_body}"
        Rails.logger.error "Instagram Insights API URL: #{insights_url}"
        Rails.logger.error "Instagram Insights API Params: #{insights_params.except(:access_token).inspect}"
        # Try to parse error for more details
        begin
          error_data = JSON.parse(error_body)
          Rails.logger.error "Instagram Insights API Error Details: #{error_data.inspect}"
        rescue
          # Not JSON, that's fine
        end
        return mock_summary(range)
      end
      
      data = JSON.parse(response.body)
      
      # Parse insights data
      metrics_hash = {}
      if data['data']
        data['data'].each do |metric_data|
          metric_name = metric_data['name']
          values = metric_data['values'] || []
          # Sum all values for the period
          total = values.sum { |v| v['value'].to_i }
          metrics_hash[metric_name] = total
        end
      end
      
      # Get follower count
      account_url = "https://graph.facebook.com/v18.0/#{@user.instagram_business_id}"
      account_params = {
        fields: 'followers_count,media_count',
        access_token: page_token
      }
      account_response = HTTParty.get(account_url, query: account_params)
      
      unless account_response.success?
        Rails.logger.error "Instagram Account API error: #{account_response.body}"
      end
      
      account_data = account_response.success? ? JSON.parse(account_response.body) : {}
      
      followers = account_data['followers_count']&.to_i || 0
      posts_count = account_data['media_count']&.to_i || 0
      
      Rails.logger.info "MetaInsightsService: Fetched data for user #{@user.id} - Followers: #{followers}, Likes: #{metrics_hash['likes'] || 0}, Comments: #{metrics_hash['comments'] || 0}"
      
      # Calculate Hootsuite-style metrics
      likes = metrics_hash['likes'] || 0
      comments = metrics_hash['comments'] || 0
      shares = 0 # Instagram doesn't provide shares directly, calculate from engagement
      clicks = metrics_hash['website_clicks'] || 0
      saves = metrics_hash['saves'] || 0  # Note: API returns 'saves' not 'saved'
      profile_visits = metrics_hash['profile_views'] || 0
      
      total_engagement = likes + comments + saves
      engagement_rate_percent = followers > 0 ? ((total_engagement.to_f / followers) * 100).round(2) : 0.0
      
      {
        engagement_rate: engagement_rate_percent,
        likes: likes,
        comments: comments,
        shares: shares,
        clicks: clicks,
        saves: saves,
        profile_visits: profile_visits,
        total_engagement: total_engagement,
        followers: followers,
        posts_count: posts_count
      }
    rescue => e
      Rails.logger.error "Error fetching Instagram insights: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      mock_summary(range)
    end
  end

  def fetch_live_timeseries(metric, range)
    return mock_timeseries(metric, range) unless live_available?
    
    begin
      page_token = get_page_access_token
      return mock_timeseries(metric, range) unless page_token
      
      period = 'day'
      metric_name = case metric
                     when 'likes' then 'likes'
                     when 'comments' then 'comments'
                     when 'engagement' then 'likes' # Use likes as proxy for engagement
                     when 'saves' then 'saves'
                     when 'clicks' then 'website_clicks'
                     when 'profile_visits' then 'profile_views'
                     else 'likes'
                     end
      
      insights_url = "https://graph.facebook.com/v18.0/#{@user.instagram_business_id}/insights"
      insights_params = {
        metric: metric_name,
        period: period,
        access_token: page_token
      }
      
      if range == '28d'
        insights_params[:since] = 28.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      else
        insights_params[:since] = 7.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      end
      
      response = HTTParty.get(insights_url, query: insights_params)
      
      unless response.success?
        Rails.logger.error "Instagram Insights timeseries error: #{response.body}"
        return mock_timeseries(metric, range)
      end
      
      data = JSON.parse(response.body)
      
      if data['data'] && data['data'].any?
        metric_data = data['data'].first
        values = metric_data['values'] || []
        
        values.map do |v|
          {
            date: v['end_time']&.split('T')&.first || Date.today.to_s,
            value: v['value'].to_i
          }
        end
      else
        mock_timeseries(metric, range)
      end
    rescue => e
      Rails.logger.error "Error fetching Instagram timeseries: #{e.message}"
      mock_timeseries(metric, range)
    end
  end
  
  def get_page_access_token
    return nil unless @user.fb_user_access_key.present? && @user.instagram_business_id.present?
    
    begin
      # Get pages with Instagram accounts
      url = "https://graph.facebook.com/v18.0/me/accounts"
      params = {
        access_token: @user.fb_user_access_key,
        fields: 'id,name,access_token,instagram_business_account',
        limit: 1000
      }
      
      response = HTTParty.get(url, query: params)
      unless response.success?
        Rails.logger.error "Error fetching pages: #{response.body}"
        return nil
      end
      
      data = JSON.parse(response.body)
      return nil unless data['data']&.any?
      
      # Find the page that has the Instagram account
      data['data'].each do |page|
        if page['instagram_business_account'] && page['instagram_business_account']['id'] == @user.instagram_business_id
          page_token = page['access_token']
          
          # Debug: Check what permissions this token has
          debug_token_url = "https://graph.facebook.com/v18.0/debug_token"
          debug_params = {
            input_token: page_token,
            access_token: @user.fb_user_access_key
          }
          debug_response = HTTParty.get(debug_token_url, query: debug_params)
          if debug_response.success?
            debug_data = JSON.parse(debug_response.body)
            Rails.logger.info "Page token permissions: #{debug_data.dig('data', 'scopes')&.inspect}"
            Rails.logger.info "Page token has instagram_manage_insights: #{debug_data.dig('data', 'scopes')&.include?('instagram_manage_insights')}"
          end
          
          return page_token
        end
      end
      
      # Fallback to first page if no match
      data['data'].first&.dig('access_token')
    rescue => e
      Rails.logger.error "Error getting page access token: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  def cached(key, ttl)
    Rails.cache.fetch(key, expires_in: ttl) { yield }
  end

  def mock_summary(range)
    # Only used as fallback when Instagram API is not available
    # Returns zeros instead of fake data to indicate no data available
    {
      engagement_rate: 0.0,
      likes: 0,
      comments: 0,
      shares: 0,
      clicks: 0,
      saves: 0,
      profile_visits: 0,
      total_engagement: 0,
      followers: 0,
      posts_count: 0
    }
  end

  def mock_timeseries(metric, range)
    days = range_days(range)
    start_date = Date.today - (days - 1)
    seed = seed_for("#{metric}_#{range}")
    srand(seed)
    (0...days).map do |i|
      {
        date: (start_date + i).to_s,
        value: base_for(metric) + rand(-base_for(metric) * 0.2..base_for(metric) * 0.2)
      }
    end
  end

  def base_for(metric)
    case metric
    when 'likes' then 500
    when 'comments' then 50
    when 'saves' then 30
    when 'clicks' then 100
    when 'profile_visits' then 200
    when 'engagement' then 90
    else 50
    end
  end

  def range_days(range)
    range.to_s.end_with?('28d') ? 28 : 7
  end

  def seed_for(token)
    token.to_s.hash % 1_000_000
  end
end
