class MetaInsightsService
  # Service for Instagram insights via Meta Graph API
  BASE_URL = 'https://graph.facebook.com/v18.0'

  def initialize(user)
    @user = user
  end

  # Returns aggregate metrics for a given range (e.g., '7d', '28d')
  def summary(range)
    cached("ig_summary_#{@user.id}_#{range}", 15.minutes) do
      if instagram_connected?
        fetch_live_summary(range)
      else
        mock_summary(range)
      end
    end
  end

  # Returns [{date:, value:}] points for metric over range
  def timeseries(metric, range)
    cached("ig_ts_#{@user.id}_#{metric}_#{range}", 15.minutes) do
      if instagram_connected?
        fetch_live_timeseries(metric, range)
      else
        mock_timeseries(metric, range)
      end
    end
  end

  private

  def instagram_connected?
    @user.instagram_business_id.present? && @user.fb_user_access_key.present?
  end

  def fetch_live_summary(range)
    period = range_to_period(range)
    
    # Get page access token for the Instagram Business Account
    page_token = get_page_access_token
    
    unless page_token
      Rails.logger.warn "Could not get page access token for Instagram Business Account"
      return mock_summary(range)
    end

    ig_business_id = @user.instagram_business_id
    
    # Fetch current follower count
    followers_count = fetch_followers_count(ig_business_id, page_token)
    
    # Fetch engagement metrics (likes, comments, shares, saves)
    engagement_data = fetch_engagement_metrics(ig_business_id, page_token, period)
    
    # Fetch new followers (follower growth)
    new_followers = fetch_new_followers(ig_business_id, page_token, period)
    
    result = {
      engagement: engagement_data[:total] || 0,
      followers: followers_count || 0,
      new_followers: new_followers || 0,
      likes: engagement_data[:likes] || 0,
      comments: engagement_data[:comments] || 0,
      shares: engagement_data[:shares] || 0,
      saves: engagement_data[:saves] || 0
    }
    
    Rails.logger.info "Instagram analytics fetched successfully: followers=#{result[:followers]}, engagement=#{result[:engagement]}"
    result
  rescue => e
    Rails.logger.error "Error fetching Instagram analytics: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Return empty data on error, not mock data
    {
      engagement: 0,
      followers: 0,
      new_followers: 0,
      likes: 0,
      comments: 0,
      shares: 0,
      saves: 0
    }
  end

  def fetch_live_timeseries(metric, range)
    period = range_to_period(range)
    page_token = get_page_access_token
    
    unless page_token
      return mock_timeseries(metric, range)
    end

    ig_business_id = @user.instagram_business_id
    days = range_days(range)
    
    case metric
    when 'engagement'
      fetch_engagement_timeseries(ig_business_id, page_token, period, days)
    when 'followers'
      fetch_followers_timeseries(ig_business_id, page_token, period, days)
    when 'new_followers'
      fetch_new_followers_timeseries(ig_business_id, page_token, period, days)
    else
      mock_timeseries(metric, range)
    end
  rescue => e
    Rails.logger.error "Error fetching Instagram timeseries: #{e.message}"
    mock_timeseries(metric, range)
  end

  def get_page_access_token
    # Get the page access token that has access to the Instagram Business Account
    # First, get all pages the user manages
    url = "#{BASE_URL}/me/accounts"
    params = {
      access_token: @user.fb_user_access_key,
      fields: 'id,name,access_token,instagram_business_account'
    }
    
    response = HTTParty.get(url, query: params)
    
    unless response.success?
      Rails.logger.error "Failed to fetch pages: #{response.code} - #{response.body}"
      return nil
    end
    
    data = JSON.parse(response.body)
    
    if data['data']
      # Find the page that has the Instagram Business Account
      page = data['data'].find do |p|
        p['instagram_business_account'] && 
        p['instagram_business_account']['id'] == @user.instagram_business_id
      end
      
      return page['access_token'] if page
    end
    
    nil
  end

  def fetch_followers_count(ig_business_id, access_token)
    url = "#{BASE_URL}/#{ig_business_id}"
    params = {
      access_token: access_token,
      fields: 'followers_count,username'
    }
    
    response = HTTParty.get(url, query: params)
    
    if response.success?
      data = JSON.parse(response.body)
      followers = data['followers_count'] || 0
      Rails.logger.info "Instagram followers fetched: #{followers} for account #{data['username'] || ig_business_id}"
      followers
    else
      Rails.logger.error "Failed to fetch Instagram followers count: #{response.code} - #{response.body}"
      error_data = begin
        JSON.parse(response.body)
      rescue
        {}
      end
      Rails.logger.error "Instagram API error: #{error_data['error'] || response.body}"
      0
    end
  end

  def fetch_engagement_metrics(ig_business_id, access_token, period)
    # Fetch insights for engagement metrics
    url = "#{BASE_URL}/#{ig_business_id}/insights"
    params = {
      access_token: access_token,
      metric: 'likes,comments,shares,saves',
      period: period
    }
    
    response = HTTParty.get(url, query: params)
    
    unless response.success?
      Rails.logger.error "Failed to fetch engagement metrics: #{response.code} - #{response.body}"
      return { total: 0, likes: 0, comments: 0, shares: 0, saves: 0 }
    end
    
    data = JSON.parse(response.body)
    
    # Parse the insights response
    likes = 0
    comments = 0
    shares = 0
    saves = 0
    
    if data['data']
      data['data'].each do |insight|
        metric_name = insight['name']
        values = insight['values'] || []
        value = values.first ? (values.first['value'] || 0) : 0
        
        case metric_name
        when 'likes'
          likes = value
        when 'comments'
          comments = value
        when 'shares'
          shares = value
        when 'saves'
          saves = value
        end
      end
    end
    
    {
      total: likes + comments + shares + saves,
      likes: likes,
      comments: comments,
      shares: shares,
      saves: saves
    }
  end

  def fetch_new_followers(ig_business_id, access_token, period)
    # Fetch follower growth
    url = "#{BASE_URL}/#{ig_business_id}/insights"
    params = {
      access_token: access_token,
      metric: 'follower_count',
      period: period
    }
    
    response = HTTParty.get(url, query: params)
    
    unless response.success?
      Rails.logger.error "Failed to fetch new followers: #{response.code} - #{response.body}"
      return 0
    end
    
    data = JSON.parse(response.body)
    
    if data['data'] && data['data'].first
      values = data['data'].first['values'] || []
      if values.length >= 2
        # Calculate difference between first and last value
        first_value = values.first['value'] || 0
        last_value = values.last['value'] || 0
        return [0, last_value - first_value].max
      elsif values.length == 1
        return values.first['value'] || 0
      end
    end
    
    0
  end

  def fetch_engagement_timeseries(ig_business_id, access_token, period, days)
    url = "#{BASE_URL}/#{ig_business_id}/insights"
    since_time = (Time.current.beginning_of_day - (days - 1).days).to_i
    until_time = Time.current.end_of_day.to_i
    params = {
      access_token: access_token,
      metric: 'likes,comments,shares,saves',
      period: 'day',
      since: since_time,
      until: until_time
    }
    
    response = HTTParty.get(url, query: params)
    
    unless response.success?
      Rails.logger.error "Failed to fetch engagement timeseries: #{response.code} - #{response.body}"
      return mock_timeseries('engagement', days == 28 ? '28d' : '7d')
    end
    
    data = JSON.parse(response.body)
    
    # Aggregate daily engagement
    daily_engagement = {}
    
    if data['data']
      data['data'].each do |insight|
        values = insight['values'] || []
        values.each do |value|
          date_str = value['end_time'] || value['start_time']
          next unless date_str
          
          begin
            date_key = Time.parse(date_str).to_date.to_s
            daily_engagement[date_key] ||= 0
            daily_engagement[date_key] += (value['value'] || 0)
          rescue => e
            Rails.logger.warn "Failed to parse date: #{date_str} - #{e.message}"
          end
        end
      end
    end
    
    # Fill in missing days with 0
    start_date = Time.current.beginning_of_day.to_date - (days - 1).days
    (0...days).map do |i|
      date = (start_date + i.days).to_s
      {
        date: date,
        value: daily_engagement[date] || 0
      }
    end
  end

  def fetch_followers_timeseries(ig_business_id, access_token, period, days)
    url = "#{BASE_URL}/#{ig_business_id}/insights"
    since_time = (Time.current.beginning_of_day - (days - 1).days).to_i
    until_time = Time.current.end_of_day.to_i
    params = {
      access_token: access_token,
      metric: 'follower_count',
      period: 'day',
      since: since_time,
      until: until_time
    }
    
    response = HTTParty.get(url, query: params)
    
    unless response.success?
      return mock_timeseries('followers', days == 28 ? '28d' : '7d')
    end
    
    data = JSON.parse(response.body)
    
    daily_followers = {}
    
    if data['data'] && data['data'].first
      values = data['data'].first['values'] || []
      values.each do |value|
        date_str = value['end_time'] || value['start_time']
        next unless date_str
        
        begin
          date_key = Time.parse(date_str).to_date.to_s
          daily_followers[date_key] = value['value'] || 0
        rescue => e
          Rails.logger.warn "Failed to parse date: #{date_str} - #{e.message}"
        end
      end
    end
    
    start_date = Time.current.beginning_of_day.to_date - (days - 1).days
    (0...days).map do |i|
      date = (start_date + i.days).to_s
      {
        date: date,
        value: daily_followers[date] || 0
      }
    end
  end

  def fetch_new_followers_timeseries(ig_business_id, access_token, period, days)
    # Calculate daily new followers from follower_count timeseries
    followers_ts = fetch_followers_timeseries(ig_business_id, access_token, period, days)
    
    return followers_ts if followers_ts.empty?
    
    # Calculate daily differences
    result = []
    followers_ts.each_with_index do |point, index|
      if index == 0
        result << { date: point[:date], value: 0 }
      else
        prev_value = followers_ts[index - 1][:value] || 0
        curr_value = point[:value] || 0
        new_followers = [0, curr_value - prev_value].max
        result << { date: point[:date], value: new_followers }
      end
    end
    
    result
  end

  def range_to_period(range)
    # Convert range to Instagram API period
    case range.to_s
    when '7d', '7'
      'day'
    when '28d', '28'
      'day'
    else
      'day'
    end
  end

  def cached(key, ttl)
    Rails.cache.fetch(key, expires_in: ttl) { yield }
  end

  def mock_summary(range)
    seed = seed_for(range)
    srand(seed)
    {
      engagement: rand(300..2_400),
      followers: rand(1_000..25_000),
      new_followers: rand(10..200),
      likes: rand(200..1_500),
      comments: rand(50..400),
      shares: rand(20..200),
      saves: rand(30..300)
    }
  end

  def mock_timeseries(metric, range)
    days = range_days(range)
    start_date = Time.current.beginning_of_day.to_date - (days - 1).days
    seed = seed_for("#{metric}_#{range}")
    srand(seed)
    (0...days).map do |i|
      {
        date: (start_date + i.days).to_s,
        value: base_for(metric) + rand(-base_for(metric) * 0.2..base_for(metric) * 0.2)
      }
    end
  end

  def base_for(metric)
    case metric
    when 'engagement' then 90
    when 'followers' then 5000
    when 'new_followers' then 20
    else 50
    end
  end

  def range_days(range)
    range.to_s.end_with?('28d') || range.to_s == '28' ? 28 : 7
  end

  def seed_for(token)
    token.to_s.hash % 1_000_000
  end
end


