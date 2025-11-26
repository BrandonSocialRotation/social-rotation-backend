# Authentication Controller
# Handles user registration and login
# Endpoints:
#   POST /api/v1/auth/register - Create new user account
#   POST /api/v1/auth/login - Authenticate existing user
class Api::V1::AuthController < ApplicationController
  # Skip authentication for auth endpoints (otherwise can't login!)
  skip_before_action :authenticate_user!, only: [:register, :login]

  # POST /api/v1/auth/register
  # Create new user account
  # Params: name, email, password, password_confirmation, account_type, company_name
  # Returns: user object and JWT token
  def register
    begin
      # Handle agency/reseller account creation
      if params[:account_type] == 'agency'
        # Validate company name for agency accounts
        if params[:company_name].blank?
          return render json: {
            error: 'Company name is required for agency accounts',
            message: 'Please provide a company or agency name',
            field: 'company_name'
          }, status: :unprocessable_entity
        end
        
        account = Account.new(
          name: params[:company_name],
          is_reseller: true,
          status: true
        )
        
        unless account.save
          return render json: {
            error: 'Failed to create agency account',
            message: account.errors.full_messages.join(', '),
            details: account.errors.full_messages,
            errors: account.errors.as_json
          }, status: :unprocessable_entity
        end
        
        user = User.new(user_params.merge(
          account_id: account.id,
          is_account_admin: true,
          role: 'reseller'
        ))
      else
        # Personal account (account_id defaults to 0)
        user = User.new(user_params)
      end
      
      if user.save
        token = JsonWebToken.encode(user_id: user.id)
        render json: {
          user: user_json(user),
          token: token,
          message: 'Account created successfully'
        }, status: :created
      else
        # Provide detailed error messages
        error_messages = user.errors.full_messages
        error_details = user.errors.details
        
        # Create user-friendly error messages
        friendly_message = error_messages.join('. ')
        
        # Log errors for debugging
        Rails.logger.error "Registration validation errors: #{error_messages.inspect}"
        Rails.logger.error "User errors details: #{user.errors.as_json.inspect}"
        
        render json: {
          error: 'Registration failed',
          message: friendly_message,
          details: error_messages,
          errors: user.errors.as_json
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Registration error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        error: 'Registration failed',
        message: "An unexpected error occurred: #{e.message}",
        details: [e.message]
      }, status: :internal_server_error
    end
  end

  # POST /api/v1/auth/login
  # Authenticate user with email and password
  # Params: email, password
  # Returns: user object and JWT token
  def login
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      token = JsonWebToken.encode(user_id: user.id)
      render json: {
        user: user_json(user),
        token: token,
        message: 'Login successful'
      }
    else
      render json: {
        error: 'Invalid email or password'
      }, status: :unauthorized
    end
  end

  private

  # Permit only safe user parameters
  def user_params
    params.permit(:name, :email, :password, :password_confirmation)
  end

  # Format user data for JSON response (exclude sensitive fields)
  def user_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      account_id: user.account_id,
      is_account_admin: user.is_account_admin,
      role: user.role,
      super_admin: user.super_admin?,
      reseller: user.reseller?,
      can_access_marketplace: user.can_access_marketplace?,
      can_create_marketplace_item: user.can_create_marketplace_item?,
      can_create_sub_account: user.can_create_sub_account?,
      can_manage_rss_feeds: user.can_manage_rss_feeds?,
      can_access_rss_feeds: user.can_access_rss_feeds?,
      created_at: user.created_at
    }
  end
end
