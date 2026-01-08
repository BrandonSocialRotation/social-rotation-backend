class ApplicationController < ActionController::API
  include ActionController::Cookies

  # Skip CSRF for API (use token authentication instead)
  # ActionController::API doesn't have CSRF protection by default

  # Handle authentication
  # Note: Individual controllers can skip this with skip_before_action
  before_action :authenticate_user!
  
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

  # Check if user has active subscription (for blocking specific actions like posting/scheduling)
  # Returns true if subscription is active, false otherwise
  def has_active_subscription?
    return false if @current_user.nil?
    return true if @current_user.account_id == 0 # Super admin bypass
    
    account = @current_user.account
    return false unless account
    
    account.has_active_subscription? rescue false
  end

  # Require active subscription for specific actions (like posting/scheduling)
  # Returns 403 if subscription is not active
  def require_active_subscription_for_action!
    return if has_active_subscription?
    
    account = @current_user&.account
    subscription = account&.subscription
    
    # Check if free subscription expired
    is_expired = subscription&.current_period_end && subscription.current_period_end < Time.current
    is_free_plan = subscription&.plan&.name == "Free Access"
    
    if is_expired && is_free_plan
      render json: {
        error: 'Free trial expired',
        message: 'Your free trial has ended. Payment information is needed for the app to continue.',
        subscription_required: true,
        subscription_status: 'expired',
        redirect_to: '/profile',
        payment_required: true
      }, status: :forbidden
      return
    elsif subscription && subscription.canceled?
      render json: {
        error: 'Subscription needed to post',
        message: 'Subscription needed to post',
        subscription_required: true,
        subscription_status: 'canceled',
        redirect_to: '/profile'
      }, status: :forbidden
      return
    elsif subscription
      render json: {
        error: 'Subscription needed to post',
        message: 'Subscription needed to post',
        subscription_required: true,
        subscription_status: subscription.status,
        redirect_to: '/profile'
      }, status: :forbidden
      return
    else
      render json: {
        error: 'Subscription needed to post',
        message: 'Subscription needed to post',
        subscription_required: true,
        subscription_status: 'missing',
        redirect_to: '/register'
      }, status: :forbidden
      return
    end
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
    # Check if we're in AuthController (all actions skip auth)
    return true if self.class.name == 'Api::V1::AuthController' || self.class.name.start_with?('Api::V1::AuthController')
    
    # For OAuthController, only skip auth for callback actions
    if self.class.name == 'Api::V1::OauthController' || self.class.name.start_with?('Api::V1::OauthController')
      return params[:action]&.end_with?('_callback') || false
    end
    
    # Also check params for route-based detection (fallback)
    controller_path = params[:controller] || ''
    action_name = params[:action] || ''
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
  # Allows users with existing accounts to log in even if subscription is suspended/canceled
  # (so they can manage their subscription), but shows a warning message
  def require_active_subscription!
    # Skip if no current user (authentication failed or not required)
    return if @current_user.nil?
    
    # Super admin accounts (account_id = 0) bypass subscription check
    # Note: account_id = 0 is the old format for personal accounts, should bypass check
    if @current_user.account_id == 0
      return
    end
    
    # If user has no account yet (account_id = nil), they need to complete payment
    # This enforces payment-first registration - account only created after payment
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
    # Allow access but add warning headers for frontend to display
    begin
      subscription = account.subscription
      if subscription
        # Check if subscription is expired (past current_period_end)
        is_expired = subscription.current_period_end && subscription.current_period_end < Time.current
        is_free_plan = subscription.plan&.name == "Free Access"
        
        # If subscription exists but is not active (suspended/canceled, or expired)
        unless account.has_active_subscription?
          # Special handling for expired free accounts - redirect to payment
          if is_expired && is_free_plan
            render json: {
              error: 'Free trial expired',
              message: 'Your free trial has ended. Payment information is needed for the app to continue.',
              subscription_required: true,
              subscription_status: 'expired',
              redirect_to: '/profile', # Redirect to profile/subscription page
              payment_required: true
            }, status: :forbidden
            return
          end
          
          # For other inactive subscriptions, allow access but show warning
          response.headers['X-Subscription-Status'] = subscription.status || 'inactive'
          response.headers['X-Subscription-Message'] = 'Your subscription is not active. Please update your payment method to continue using the app.'
          return
        end
      else
        # No subscription at all - allow access but show message
        # This shouldn't happen with payment-first registration, but handle it
        response.headers['X-Subscription-Status'] = 'missing'
        response.headers['X-Subscription-Message'] = 'You need an active subscription to use this feature. Please subscribe to continue.'
        return
      end
    rescue => e
      Rails.logger.error "Subscription check error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # If there's an error checking subscription, allow access but log the error
      response.headers['X-Subscription-Status'] = 'error'
      return
    end
  end
end