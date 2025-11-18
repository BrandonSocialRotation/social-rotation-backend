class Api::V1::PlansController < ApplicationController
  before_action :authenticate_user!, only: [:show]
  
  # GET /api/v1/plans
  # List all available plans (public endpoint)
  def index
    # Check if plans table exists (migrations may not have run yet)
    unless ActiveRecord::Base.connection.table_exists?('plans')
      return render json: { 
        error: 'Plans table does not exist. Please run database migrations.',
        plans: []
      }, status: :service_unavailable
    end
    
    plan_type = params[:plan_type] # Optional filter: 'location_based' or 'user_seat_based'
    
    plans = Plan.active.ordered
    plans = plans.where(plan_type: plan_type) if plan_type.present?
    
    render json: {
      plans: plans.map { |plan| plan_json(plan) }
    }
  rescue => e
    Rails.logger.error "Plans index error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { 
      error: 'Failed to load plans',
      message: e.message
    }, status: :internal_server_error
  end
  
  # GET /api/v1/plans/:id
  # Get details of a specific plan
  def show
    plan = Plan.find(params[:id])
    
    render json: {
      plan: plan_json(plan)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Plan not found' }, status: :not_found
  end
  
  private
  
  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      plan_type: plan.plan_type,
      price_cents: plan.price_cents,
      price_dollars: plan.price_dollars,
      formatted_price: plan.formatted_price,
      max_locations: plan.max_locations,
      max_users: plan.max_users,
      max_buckets: plan.max_buckets,
      max_images_per_bucket: plan.max_images_per_bucket,
      features: plan.features_hash,
      stripe_price_id: plan.stripe_price_id,
      stripe_product_id: plan.stripe_product_id,
      display_name: plan.display_name
    }
  end
end
