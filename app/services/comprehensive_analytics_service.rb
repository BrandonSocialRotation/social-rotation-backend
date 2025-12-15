class ComprehensiveAnalyticsService
  # Comprehensive analytics service that aggregates data from all platforms
  # Similar to Hootsuite's analytics dashboard

  def initialize(user)
    @user = user
  end

  # Get overall analytics across all platforms
  def overall_summary(range = '7d')
    days = range_to_days(range)
    start_date = Time.current.beginning_of_day - (days - 1).days
    end_date = Time.current.end_of_day

    # Get post counts from send history
    all_histories = BucketSendHistory
      .joins(:bucket)
      .where(buckets: { user_id: @user.id })
      .where(sent_at: start_date..end_date)

    # Calculate platform-specific post counts
    facebook_posts = count_posts_for_platform(all_histories, BucketSchedule::BIT_FACEBOOK)
    instagram_posts = count_posts_for_platform(all_histories, BucketSchedule::BIT_INSTAGRAM)
    twitter_posts = count_posts_for_platform(all_histories, BucketSchedule::BIT_TWITTER)
    linkedin_posts = count_posts_for_platform(all_histories, BucketSchedule::BIT_LINKEDIN)

    # Get engagement and followers from platform APIs
    facebook_data = fetch_facebook_analytics(range)
    instagram_data = fetch_instagram_analytics(range)
    twitter_data = fetch_twitter_analytics(range)
    linkedin_data = fetch_linkedin_analytics(range)

    {
      range: range,
      posts: {
        total: all_histories.count,
        facebook: facebook_posts,
        instagram: instagram_posts,
        twitter: twitter_posts,
        linkedin: linkedin_posts
      },
      engagement: {
        total: (facebook_data[:engagement] || 0) + 
               (instagram_data[:engagement] || 0) + 
               (twitter_data[:engagement] || 0) + 
               (linkedin_data[:engagement] || 0),
        facebook: facebook_data[:engagement] || 0,
        instagram: instagram_data[:engagement] || 0,
        twitter: twitter_data[:engagement] || 0,
        linkedin: linkedin_data[:engagement] || 0
      },
      followers: {
        total: (facebook_data[:followers] || 0) + 
               (instagram_data[:followers] || 0) + 
               (twitter_data[:followers] || 0) + 
               (linkedin_data[:followers] || 0),
        facebook: facebook_data[:followers] || 0,
        instagram: instagram_data[:followers] || 0,
        twitter: twitter_data[:followers] || 0,
        linkedin: linkedin_data[:followers] || 0
      },
      new_followers: {
        total: (facebook_data[:new_followers] || 0) + 
               (instagram_data[:new_followers] || 0) + 
               (twitter_data[:new_followers] || 0) + 
               (linkedin_data[:new_followers] || 0),
        facebook: facebook_data[:new_followers] || 0,
        instagram: instagram_data[:new_followers] || 0,
        twitter: twitter_data[:new_followers] || 0,
        linkedin: linkedin_data[:new_followers] || 0
      },
      platforms: {
        facebook: facebook_data,
        instagram: instagram_data,
        twitter: twitter_data,
        linkedin: linkedin_data
      }
    }
  end

  # Get platform-specific analytics
  def platform_summary(platform, range = '7d')
    days = range_to_days(range)
    start_date = Time.current.beginning_of_day - (days - 1).days
    end_date = Time.current.end_of_day

    bit_flag = platform_bit_flag(platform)
    return nil unless bit_flag

    # Get post counts
    histories = BucketSendHistory
      .joins(:bucket)
      .where(buckets: { user_id: @user.id })
      .where(sent_at: start_date..end_date)
      .where('sent_to & ? > 0', bit_flag)

    post_count = histories.count

    # Get platform-specific analytics
    platform_data = case platform
    when 'facebook'
      fetch_facebook_analytics(range)
    when 'instagram'
      fetch_instagram_analytics(range)
    when 'twitter'
      fetch_twitter_analytics(range)
    when 'linkedin'
      fetch_linkedin_analytics(range)
    else
      {}
    end

    {
      platform: platform,
      range: range,
      posts: post_count,
      engagement: platform_data[:engagement] || 0,
      followers: platform_data[:followers] || 0,
      new_followers: platform_data[:new_followers] || 0,
      likes: platform_data[:likes] || 0,
      comments: platform_data[:comments] || 0,
      shares: platform_data[:shares] || 0,
      details: platform_data
    }
  end

  # Get timeseries data for graphs
  def timeseries(platform, metric, range = '28d')
    days = range_to_days(range)
    start_date = Time.current.beginning_of_day - (days - 1).days

    case platform
    when 'overall'
      overall_timeseries(metric, days, start_date)
    when 'facebook'
      facebook_timeseries(metric, range)
    when 'instagram'
      instagram_timeseries(metric, range)
    when 'twitter'
      twitter_timeseries(metric, range)
    when 'linkedin'
      linkedin_timeseries(metric, range)
    else
      []
    end
  end

  private

  def count_posts_for_platform(histories, bit_flag)
    histories.count { |h| (h.sent_to & bit_flag) > 0 }
  end

  def platform_bit_flag(platform)
    case platform.to_s.downcase
    when 'facebook'
      BucketSchedule::BIT_FACEBOOK
    when 'instagram'
      BucketSchedule::BIT_INSTAGRAM
    when 'twitter'
      BucketSchedule::BIT_TWITTER
    when 'linkedin'
      BucketSchedule::BIT_LINKEDIN
    else
      nil
    end
  end

  def fetch_facebook_analytics(range)
    return {} unless @user.fb_user_access_key.present?

    begin
      # Get page access token
      page_token = get_facebook_page_token
      return {} unless page_token

      # Fetch page info first to get current follower count
      page_id = get_facebook_page_id
      return {} unless page_id

      # Get current page fans (followers) count
      page_info_url = "https://graph.facebook.com/v18.0/#{page_id}"
      page_info_params = {
        access_token: page_token,
        fields: 'fan_count,followers_count'
      }

      page_info_response = HTTParty.get(page_info_url, query: page_info_params)
      current_followers = 0
      
      if page_info_response.success?
        page_data = JSON.parse(page_info_response.body)
        # Try both fan_count and followers_count (different API versions use different fields)
        current_followers = page_data['fan_count'] || page_data['followers_count'] || 0
        Rails.logger.info "Facebook page followers: #{current_followers}"
      else
        Rails.logger.error "Failed to fetch Facebook page info: #{page_info_response.code} - #{page_info_response.body}"
      end

      # Fetch engagement insights for the range
      url = "https://graph.facebook.com/v18.0/#{page_id}/insights"
      params = {
        access_token: page_token,
        metric: 'page_engaged_users,page_post_engagements',
        period: 'day',
        since: (Time.current.beginning_of_day - (range_to_days(range) - 1).days).to_i,
        until: Time.current.end_of_day.to_i
      }

      response = HTTParty.get(url, query: params)
      engagement_data = parse_facebook_insights(response.success? ? JSON.parse(response.body) : {}, range)
      
      # Get follower growth from insights
      follower_growth_url = "https://graph.facebook.com/v18.0/#{page_id}/insights"
      follower_growth_params = {
        access_token: page_token,
        metric: 'page_fans',
        period: 'day',
        since: (Time.current.beginning_of_day - (range_to_days(range) - 1).days).to_i,
        until: Time.current.end_of_day.to_i
      }

      follower_growth_response = HTTParty.get(follower_growth_url, query: follower_growth_params)
      new_followers = 0
      
      if follower_growth_response.success?
        growth_data = JSON.parse(follower_growth_response.body)
        if growth_data['data'] && growth_data['data'].first
          values = growth_data['data'].first['values'] || []
          if values.length >= 2
            first_value = values.first['value'] || 0
            last_value = values.last['value'] || 0
            new_followers = [0, last_value - first_value].max
          end
        end
      end

      {
        engagement: engagement_data[:engagement] || 0,
        followers: current_followers,
        new_followers: new_followers,
        engaged_users: engagement_data[:engaged_users] || 0,
        likes: 0,
        comments: 0,
        shares: 0
      }
    rescue => e
      Rails.logger.error "Error fetching Facebook analytics: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      {}
    end
  end

  def fetch_instagram_analytics(range)
    return {} unless @user.instagram_business_id.present?

    begin
      service = MetaInsightsService.new(@user)
      data = service.summary(range)
      {
        engagement: data[:engagement] || 0,
        followers: data[:followers] || 0,
        new_followers: data[:new_followers] || 0,
        likes: data[:likes] || 0,
        comments: data[:comments] || 0,
        shares: data[:shares] || 0,
        saves: data[:saves] || 0
      }
    rescue => e
      Rails.logger.error "Error fetching Instagram analytics: #{e.message}"
      {}
    end
  end

  def fetch_twitter_analytics(range)
    return {} unless @user.twitter_oauth_token.present?

    begin
      # Twitter API v2 doesn't provide free analytics
      # Return basic data structure for now
      {
        engagement: 0,
        followers: 0,
        new_followers: 0,
        likes: 0,
        comments: 0,
        shares: 0
      }
    rescue => e
      Rails.logger.error "Error fetching Twitter analytics: #{e.message}"
      {}
    end
  end

  def fetch_linkedin_analytics(range)
    return {} unless @user.linkedin_access_token.present?

    begin
      # LinkedIn API has limited analytics access
      # Return basic data structure for now
      {
        engagement: 0,
        followers: 0,
        new_followers: 0,
        likes: 0,
        comments: 0,
        shares: 0
      }
    rescue => e
      Rails.logger.error "Error fetching LinkedIn analytics: #{e.message}"
      {}
    end
  end

  def get_facebook_page_token
    url = "https://graph.facebook.com/v18.0/me/accounts"
    params = {
      access_token: @user.fb_user_access_key,
      fields: 'id,name,access_token,instagram_business_account'
    }

    response = HTTParty.get(url, query: params)
    return nil unless response.success?

    data = JSON.parse(response.body)
    return nil unless data['data'] && data['data'].first

    data['data'].first['access_token']
  end

  def get_facebook_page_id
    url = "https://graph.facebook.com/v18.0/me/accounts"
    params = {
      access_token: @user.fb_user_access_key,
      fields: 'id'
    }

    response = HTTParty.get(url, query: params)
    return nil unless response.success?

    data = JSON.parse(response.body)
    return nil unless data['data'] && data['data'].first

    data['data'].first['id']
  end

  def parse_facebook_insights(data, range)
    engaged_users = 0
    post_engagements = 0

    if data['data']
      data['data'].each do |insight|
        metric_name = insight['name']
        values = insight['values'] || []
        
        case metric_name
        when 'page_engaged_users'
          engaged_users = values.sum { |v| v['value'] || 0 }
        when 'page_post_engagements'
          post_engagements = values.sum { |v| v['value'] || 0 }
        end
      end
    end

    {
      engagement: post_engagements,
      engaged_users: engaged_users,
      likes: 0, # Would need separate API call
      comments: 0, # Would need separate API call
      shares: 0 # Would need separate API call
    }
  end

  def instagram_timeseries(metric, range)
    return [] unless @user.instagram_business_id.present?

    begin
      service = MetaInsightsService.new(@user)
      service.timeseries(metric, range)
    rescue => e
      Rails.logger.error "Error fetching Instagram timeseries: #{e.message}"
      []
    end
  end

  def facebook_timeseries(metric, range)
    # TODO: Implement Facebook timeseries
    []
  end

  def twitter_timeseries(metric, range)
    # TODO: Implement Twitter timeseries
    []
  end

  def linkedin_timeseries(metric, range)
    # TODO: Implement LinkedIn timeseries
    []
  end

  def overall_timeseries(metric, days, start_date)
    # Aggregate timeseries across all platforms
    (0...days).map do |i|
      date = (start_date + i.days).to_s
      {
        date: date,
        value: 0 # Would aggregate from all platforms
      }
    end
  end

  def range_to_days(range)
    case range.to_s
    when '7d', '7'
      7
    when '28d', '28'
      28
    when '90d', '90'
      90
    else
      7
    end
  end
end

