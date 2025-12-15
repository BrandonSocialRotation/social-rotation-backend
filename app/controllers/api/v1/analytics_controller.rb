class Api::V1::AnalyticsController < ApplicationController
  # Overall analytics across all platforms
  def overall_summary
    range = params[:range].presence || '7d'
    service = ComprehensiveAnalyticsService.new(current_user)
    data = service.overall_summary(range)
    render json: data
  end

  # Platform-specific analytics
  def platform_summary
    platform = params[:platform].presence || 'instagram'
    range = params[:range].presence || '7d'
    service = ComprehensiveAnalyticsService.new(current_user)
    data = service.platform_summary(platform, range)
    
    if data
      render json: data
    else
      render json: { error: 'Invalid platform' }, status: :bad_request
    end
  end

  # Timeseries data for graphs
  def timeseries
    platform = params[:platform].presence || 'overall'
    metric = params[:metric].presence || 'engagement'
    range = params[:range].presence || '28d'
    service = ComprehensiveAnalyticsService.new(current_user)
    data = service.timeseries(platform, metric, range)
    render json: { platform: platform, metric: metric, range: range, points: data }
  end

  # Legacy Instagram endpoints (kept for backward compatibility)
  def instagram_summary
    range = params[:range].presence || '7d'
    service = MetaInsightsService.new(current_user)
    data = service.summary(range)
    render json: { range: range, metrics: data }
  end

  def instagram_timeseries
    metric = params[:metric].presence || 'engagement'
    range = params[:range].presence || '28d'
    service = MetaInsightsService.new(current_user)
    data = service.timeseries(metric, range)
    render json: { metric: metric, range: range, points: data }
  end
end


