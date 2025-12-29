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
    ENV['META_APP_ID'].present? && ENV['META_APP_SECRET'].present?
  end

  def fetch_live_summary(range)
    # TODO: Implement Graph API calls using page token and ig_business_account_id
    # Placeholder until credentials/tokens are wired
    mock_summary(range)
  end

  def fetch_live_timeseries(metric, range)
    # TODO: Implement Graph API timeseries
    mock_timeseries(metric, range)
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
