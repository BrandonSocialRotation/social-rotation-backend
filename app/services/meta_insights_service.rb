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
    return mock_summary(range) unless live_available?
    
    begin
      page_token = get_page_access_token
      return mock_summary(range) unless page_token
      
      period = range == '28d' ? 'day' : 'day'
      metric_list = 'impressions,reach,likes,comments,shares,saved,profile_views,website_clicks'
      
      # Get insights for the specified range
      insights_url = "https://graph.facebook.com/v18.0/#{@user.instagram_business_id}/insights"
      insights_params = {
        metric: metric_list,
        period: period,
        access_token: page_token
      }
      
      # Add date range
      if range == '28d'
        insights_params[:since] = 28.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      else
        insights_params[:since] = 7.days.ago.to_i
        insights_params[:until] = Time.now.to_i
      end
      
      response = HTTParty.get(insights_url, query: insights_params)
      
      unless response.success?
        Rails.logger.error "Instagram Insights API error: #{response.body}"
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
      account_data = account_response.success? ? JSON.parse(account_response.body) : {}
      
      followers = account_data['followers_count']&.to_i || 0
      posts_count = account_data['media_count']&.to_i || 0
      
      # Calculate Hootsuite-style metrics
      likes = metrics_hash['likes'] || 0
      comments = metrics_hash['comments'] || 0
      shares = 0 # Instagram doesn't provide shares directly, calculate from engagement
      clicks = metrics_hash['website_clicks'] || 0
      saves = metrics_hash['saved'] || 0
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
                     when 'engagement' then 'engagement'
                     when 'reach' then 'reach'
                     when 'impressions' then 'impressions'
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
      return nil unless response.success?
      
      data = JSON.parse(response.body)
      return nil unless data['data']&.any?
      
      # Find the page that has the Instagram account
      data['data'].each do |page|
        if page['instagram_business_account'] && page['instagram_business_account']['id'] == @user.instagram_business_id
          return page['access_token']
        end
      end
      
      # Fallback to first page if no match
      data['data'].first&.dig('access_token')
    rescue => e
      Rails.logger.error "Error getting page access token: #{e.message}"
      nil
    end
  end

  def cached(key, ttl)
    Rails.cache.fetch(key, expires_in: ttl) { yield }
  end

  def mock_summary(range)
    seed = seed_for(range)
    srand(seed)
    
    # Hootsuite-style analytics metrics
    likes = rand(500..5_000)
    comments = rand(50..500)
    shares = rand(20..200)
    clicks = rand(100..1_000)
    saves = rand(30..300)
    profile_visits = rand(200..2_000)
    
    total_engagement = likes + comments + shares + saves
    engagement_rate = followers = rand(1_000..25_000)
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
      posts_count: rand(5..50)
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
    when 'reach' then 600
    when 'impressions' then 1200
    when 'engagement' then 90
    when 'followers' then 20
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
