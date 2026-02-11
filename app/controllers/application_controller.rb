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
      render json: { 
        error: 'Authentication token required',
        message: 'Please log in to continue',
        code: 'TOKEN_MISSING'
      }, status: :unauthorized
      return
    end

    decoded = JsonWebToken.decode(token)
    
    if decoded
      @current_user = User.find_by(id: decoded[:user_id])
      
      unless @current_user
        render json: { 
          error: 'User not found',
          message: 'Your account could not be found. Please log in again.',
          code: 'USER_NOT_FOUND'
        }, status: :unauthorized
        return
      end
    else
      # Try to decode without expiration check to see if it's expired or invalid
      begin
        decoded_data = JWT.decode(token, JsonWebToken::SECRET_KEY, false)[0]
        # If we get here, token is valid but expired
        render json: { 
          error: 'Token expired',
          message: 'Your session has expired. Please log in again.',
          code: 'TOKEN_EXPIRED'
        }, status: :unauthorized
      rescue JWT::DecodeError
        # Token is completely invalid (wrong secret, malformed, etc.)
        render json: { 
          error: 'Invalid token',
          message: 'Your session is invalid. This may happen after a server update. Please log in again.',
          code: 'TOKEN_INVALID'
        }, status: :unauthorized
      end
      return
    end
  rescue => e
    Rails.logger.error "Authentication error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { 
      error: 'Authentication failed',
      message: 'Unable to authenticate. Please try logging in again.',
      code: 'AUTH_ERROR'
    }, status: :unauthorized
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
  # Super admins (account_id = 0 or super admin emails) have full access forever
  # Free accounts can access until expiration date
  def require_active_subscription!
    # Skip if no current user (authentication failed or not required)
    return if @current_user.nil?
    
    # List of super admin emails that bypass subscription checks
    # These users have full access even if they convert to agency accounts
    super_admin_emails = [
      'jbickler4@gmail.com',
      'bwolfe317@gmail.com',  # Brandon
      'modonnell1915@gmail.com',
      'cory@socialrotation.com',
      'profjwells@gmail.com'
    ]
    
    # Super admin accounts (account_id = 0) bypass subscription check - full access forever
    # Also check using the super_admin? method for safety
    # ALSO check super admin emails even if account_id != 0 (for super admins who converted to agency)
    if @current_user.account_id == 0 || @current_user.super_admin? || @current_user.email.in?(super_admin_emails)
      Rails.logger.info "Super admin access granted for user #{@current_user.id} (#{@current_user.email})"
      return
    end
    
    # If user has no account yet (account_id = nil), they need to complete payment
    # This enforces payment-first registration - account only created after payment
    # BUT: Skip this check if user is somehow a super admin (defensive check)
    if @current_user.account_id.nil?
      # Double-check if this might be a super admin that wasn't set up correctly
      if @current_user.email.in?(super_admin_emails)
        Rails.logger.warn "Super admin user #{@current_user.email} has nil account_id - allowing access anyway"
        return
      end
      
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
    # BUT: Allow super admin emails even if account is missing
    unless account
      if @current_user.email.in?(super_admin_emails)
        Rails.logger.warn "Super admin user #{@current_user.email} has missing account - allowing access anyway"
        return
      end
      
      render json: {
        error: 'Account not found',
        message: 'Your account could not be found. Please contact support.',
        subscription_required: true,
        redirect_to: '/register'
      }, status: :forbidden
      return
    end
    
    # Check if account has active subscription
    begin
      subscription = account.subscription
      
      if subscription
        is_free_plan = subscription.plan&.name == "Free Access"
        is_expired = subscription.current_period_end && subscription.current_period_end < Time.current
        
        # Free accounts: Allow access if not expired
        if is_free_plan
          if is_expired
            # Free account expired - require payment
            render json: {
              error: 'Free trial expired',
              message: 'Your free trial has ended. Payment information is needed for the app to continue.',
              subscription_required: true,
              subscription_status: 'expired',
              redirect_to: '/profile',
              payment_required: true
            }, status: :forbidden
            return
          else
            # Free account still active - allow access
            return
          end
        end
        
        # Paid accounts: Check if subscription is active
        if account.has_active_subscription?
          # Active subscription - allow access
          return
        else
          # Inactive paid subscription - allow access but show warning
          response.headers['X-Subscription-Status'] = subscription.status || 'inactive'
          response.headers['X-Subscription-Message'] = 'Your subscription is not active. Please update your payment method to continue using the app.'
          return
        end
      else
        # No subscription at all - require payment
        render json: {
          error: 'Subscription required',
          message: 'You need an active subscription to use this app. Please subscribe to continue.',
          subscription_required: true,
          subscription_status: 'missing',
          redirect_to: '/register'
        }, status: :forbidden
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