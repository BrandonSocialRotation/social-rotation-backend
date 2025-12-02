class ApplicationController < ActionController::API
  include ActionController::Cookies

  # Skip CSRF for API (use token authentication instead)
  # ActionController::API doesn't have CSRF protection by default

  # Handle authentication
  before_action :authenticate_user!, unless: :auth_or_oauth_controller?
  
  # Require active subscription for all authenticated routes (except subscription management)
  before_action :require_active_subscription!, unless: :skip_subscription_check?

  # Handle exceptions
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :record_invalid
  rescue_from ActionController::ParameterMissing, with: :parameter_missing

  private

  # Authenticate user using JWT token from Authorization header
  # Expects: "Authorization: Bearer <token>"
  # Sets @current_user if valid token
  # Returns 401 if missing or invalid token
  def authenticate_user!
    token = request.headers['Authorization']&.split(' ')&.last
    
    if token.blank?
      render json: { error: 'Authentication token required' }, status: :unauthorized
      return
    end

    decoded = JsonWebToken.decode(token)
    
    if decoded
      @current_user = User.find_by(id: decoded[:user_id])
      
      unless @current_user
        render json: { error: 'User not found' }, status: :unauthorized
      end
    else
      render json: { error: 'Invalid or expired token' }, status: :unauthorized
    end
  rescue => e
    render json: { error: 'Authentication failed' }, status: :unauthorized
  end

  protected

  # Get current authenticated user
  # Available in all controllers after authenticate_user! runs
  def current_user
    @current_user
  end

  def record_not_found(exception)
    render json: { error: 'Record not found' }, status: :not_found
  end

  def record_invalid(exception)
    render json: { 
      error: 'Validation failed', 
      details: exception.record.errors.full_messages 
    }, status: :unprocessable_entity
  end

  def parameter_missing(exception)
    render json: { 
      error: 'Missing required parameter', 
      parameter: exception.param 
    }, status: :bad_request
  end

  # Check if the current controller is AuthController or OauthController callback actions
  def auth_or_oauth_controller?
    controller_path = params[:controller]
    action_name = params[:action]
    
    # Skip authentication for auth controller and OAuth callback actions only
    controller_path.start_with?('api/v1/auth') || 
    (controller_path.start_with?('api/v1/oauth') && action_name.end_with?('_callback'))
  end
  
  # Check if subscription check should be skipped
  # Allow subscription management routes and user info to check subscription status
  def skip_subscription_check?
    controller_path = params[:controller]
    action_name = params[:action]
    
    # Skip subscription check for:
    # - Auth and OAuth controllers (already handled by auth_or_oauth_controller?)
    # - Subscriptions controller (to allow viewing/managing subscriptions)
    # - User info controller (to allow viewing profile/subscription status)
    # - Plans controller (to allow viewing available plans)
    auth_or_oauth_controller? ||
    controller_path.start_with?('api/v1/subscriptions') ||
    controller_path.start_with?('api/v1/user_info') ||
    controller_path.start_with?('api/v1/plans')
  end
  
  # Require active subscription for accessing the app
  # Returns 403 if account doesn't have an active subscription
  # Allows suspended accounts (past_due/canceled) to access subscription management
  def require_active_subscription!
    return if @current_user.nil? # Already handled by authenticate_user!
    
    # Super admin accounts (account_id = 0) bypass subscription check
    # Note: account_id = 0 is the old format for personal accounts, should bypass check
    if @current_user.account_id == 0
      return
    end
    
    # If user has no account yet (account_id = nil), they need to complete payment
    if @current_user.account_id.nil?
      render json: {
        error: 'Account not activated',
        message: 'Please complete payment to activate your account.',
        subscription_required: true,
        redirect_to: '/register'
      }, status: :forbidden
      return
    end
    
    account = @current_user.account
    
    # If account doesn't exist (shouldn't happen, but handle gracefully)
    unless account
      render json: {
        error: 'Account not found',
        message: 'Your account could not be found. Please contact support.',
        subscription_required: true,
        redirect_to: '/register'
      }, status: :forbidden
      return
    end
    
    # Check if account has active subscription
    if account.subscription
      # If subscription exists but is not active (suspended), allow access to subscription management
      # but block other features
      unless account.has_active_subscription?
        # Check if this is a subscription management route (already handled by skip_subscription_check?)
        # If we get here, it's not a subscription route, so block access
        render json: {
          error: 'Subscription suspended',
          message: 'Your subscription is not active. Please update your payment method to continue using the app.',
          subscription_required: true,
          subscription_suspended: true,
          redirect_to: '/profile' # Frontend should show subscription management
        }, status: :forbidden
        return
      end
    else
      # No subscription at all - need to subscribe
      render json: {
        error: 'Subscription required',
        message: 'You need an active subscription to access this feature. Please subscribe to continue.',
        subscription_required: true,
        redirect_to: '/register'
      }, status: :forbidden
      return
    end
  rescue => e
    Rails.logger.error "Subscription check error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # If there's an error checking subscription, block access (fail closed for security)
    render json: {
      error: 'Subscription verification failed',
      message: 'Unable to verify subscription status. Please contact support.',
      subscription_required: true
    }, status: :forbidden
  end
end