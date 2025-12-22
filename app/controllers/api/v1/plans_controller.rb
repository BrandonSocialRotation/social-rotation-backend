class Api::V1::PlansController < ApplicationController
  include JsonSerializers
  
  before_action :authenticate_user!, only: [:show]
  
  # GET /api/v1/plans
  # List all available plans (public endpoint)
  # Optional params: plan_type (personal, agency), account_type (personal, agency)
  def index
    # Check if plans table exists (migrations may not have run yet)
    unless ActiveRecord::Base.connection.table_exists?('plans')
      # Check if migrations are pending
      pending_migrations = ActiveRecord::Base.connection.migration_context.needs_migration?
      return render json: { 
        error: 'Plans table does not exist. Please run database migrations.',
        pending_migrations: pending_migrations,
        instructions: pending_migrations ? 'Run: bundle exec rails db:migrate' : 'Migrations may have failed. Check logs.',
        plans: []
      }, status: :service_unavailable
    end
    
    # Determine plan type based on account_type or plan_type param
    account_type = params[:account_type] # 'personal' or 'agency'
    plan_type = params[:plan_type] # Direct filter: 'personal' or 'agency'
    
    # If account_type is provided, filter by that (for showing relevant plans to user)
    # Otherwise use plan_type param if provided
    # If neither is provided, show all plans
    filter_type = account_type.presence || plan_type.presence
    
    plans = Plan.active.ordered
    if filter_type.present?
      # Show personal plans for personal accounts, agency plans for agency accounts
      plans = plans.where(plan_type: filter_type)
      Rails.logger.info "Filtering plans by plan_type: #{filter_type}, found #{plans.count} plans"
    else
      Rails.logger.info "No filter applied, showing all #{plans.count} active plans"
    end
    # If no filter, show all plans (for admin or public viewing)
    
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
end
