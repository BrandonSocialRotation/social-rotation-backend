# Authentication Controller
# Handles user registration and login
# Endpoints:
#   POST /api/v1/auth/register - Create new user account
#   POST /api/v1/auth/login - Authenticate existing user
class Api::V1::AuthController < ApplicationController
  # Skip authentication for auth endpoints (otherwise can't login!)
  # Must be called before ApplicationController's before_action callbacks
  skip_before_action :authenticate_user!, only: [:register, :login, :forgot_password, :reset_password], raise: false
  skip_before_action :require_active_subscription!, only: [:register, :login, :forgot_password, :reset_password], raise: false

  # POST /api/v1/auth/register
  # Create pending registration and Stripe checkout session
  # Account and user will be created AFTER successful payment in webhook
  # Params: name, email, password, password_confirmation, account_type, company_name, plan_id, billing_period
  # Returns: checkout_session_id and checkout_url
  def register
    begin
      # Extract account_type and company_name (handle nested params)
      account_type = params[:account_type] || params.dig(:auth, :account_type) || 'personal'
      company_name = params[:company_name] || params.dig(:auth, :company_name)
      
      # Validate company name for agency accounts
      if account_type == 'agency' && company_name.blank?
        return render json: {
          error: 'Company name is required for agency accounts',
          message: 'Please provide a company or agency name',
          field: 'company_name'
        }, status: :unprocessable_entity
      end

      # Extract email (handle nested params)
      email = params[:email] || params.dig(:auth, :email)
      
      # Check if user already exists
      existing_user = User.find_by(email: email)
      if existing_user
        return render json: {
          error: 'Registration failed',
          message: 'Email has already been taken',
          details: ['Email has already been taken']
        }, status: :unprocessable_entity
      end

      # Check if pending registration already exists
      existing_pending = PendingRegistration.find_by(email: email)
      if existing_pending
        if existing_pending.expired?
          existing_pending.destroy
        else
          # If plan_id is provided, use the existing pending registration
          if params[:plan_id].present?
            # Continue with existing pending registration
            pending_registration = existing_pending
          else
            # Return existing pending registration so frontend can proceed to plan selection
            return render json: {
              pending_registration_id: existing_pending.id,
              email: existing_pending.email,
              name: existing_pending.name,
              account_type: existing_pending.account_type,
              message: 'Registration data saved. Please select a plan to continue.'
            }, status: :ok
          end
        end
      end
      
      # Create new pending registration if one doesn't exist
      unless defined?(pending_registration) && pending_registration
        # Extract params (handle both nested and flat params)
        email = params[:email] || params.dig(:auth, :email)
        name = params[:name] || params.dig(:auth, :name)
        password = params[:password] || params.dig(:auth, :password)
        password_confirmation = params[:password_confirmation] || params.dig(:auth, :password_confirmation) || password
        account_type = params[:account_type] || params.dig(:auth, :account_type) || 'personal'
        company_name = params[:company_name] || params.dig(:auth, :company_name)
        
        # Create pending registration (validates email, name, password)
        # This can be done WITHOUT plan_id - plan selection happens next
        pending_registration = PendingRegistration.new(
          email: email,
          name: name,
          password: password,
          password_confirmation: password_confirmation || password, # Fallback to password if confirmation not provided
          account_type: account_type,
          company_name: company_name
        )

        unless pending_registration.save
          return render json: {
            error: 'Registration failed',
            message: pending_registration.errors.full_messages.join('. '),
            details: pending_registration.errors.full_messages,
            errors: pending_registration.errors.as_json
          }, status: :unprocessable_entity
        end
      end

      # If plan_id is provided, create Stripe checkout immediately
      if params[:plan_id].present?
        plan = Plan.find_by(id: params[:plan_id])
        unless plan&.status?
          return render json: {
            error: 'Invalid plan',
            message: 'Selected plan is not available'
          }, status: :bad_request
        end

        # Create Stripe checkout session
        Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || ''
        
        billing_period = params[:billing_period] || 'monthly'
        user_count = params[:user_count]&.to_i || 1

        # Create Stripe customer
        customer = Stripe::Customer.create({
          email: pending_registration.email,
          name: pending_registration.name,
          metadata: {
            pending_registration_id: pending_registration.id.to_s
          }
        })

        # Calculate price and create line items
        if plan.supports_per_user_pricing
          price_cents = plan.calculate_price_for_users(user_count, billing_period)
          stripe_price = Stripe::Price.create({
            unit_amount: price_cents,
            currency: 'usd',
            recurring: {
              interval: billing_period == 'annual' ? 'year' : 'month',
            },
            product_data: {
              name: "#{plan.name} (#{user_count} user#{user_count != 1 ? 's' : ''})"
            }
          })
          line_items = [{ price: stripe_price.id, quantity: 1 }]
        else
          if plan.stripe_price_id.present?
            line_items = [{ price: plan.stripe_price_id, quantity: 1 }]
          else
            price_cents = plan.price_cents || 0
            unless price_cents > 0
              pending_registration.destroy
              return render json: { error: 'Plan does not have a price configured' }, status: :bad_request
            end
            
            stripe_price = Stripe::Price.create({
              unit_amount: price_cents,
              currency: 'usd',
              recurring: {
                interval: billing_period == 'annual' ? 'year' : 'month',
              },
              product_data: {
                name: plan.name
              }
            })
            line_items = [{ price: stripe_price.id, quantity: 1 }]
          end
        end

        # Create checkout session
        frontend_url = ENV['FRONTEND_URL'] || 'https://my.socialrotation.app'
        success_url = "#{frontend_url.chomp('/')}/profile?success=subscription_active&session_id={CHECKOUT_SESSION_ID}"
        cancel_url = "#{frontend_url.chomp('/')}/register?error=subscription_canceled"

        session = Stripe::Checkout::Session.create({
          customer: customer.id,
          payment_method_types: ['card'],
          line_items: line_items,
          mode: 'subscription',
          success_url: success_url,
          cancel_url: cancel_url,
          billing_address_collection: 'required',
          automatic_tax: { enabled: false },
          metadata: {
            pending_registration_id: pending_registration.id.to_s,
            plan_id: plan.id.to_s,
            billing_period: billing_period,
            account_type: pending_registration.account_type,
            company_name: pending_registration.company_name || '',
            user_count: user_count.to_s
          }
        })

        # Store session ID in pending registration (use update_column to skip validations)
        pending_registration.update_column(:stripe_session_id, session.id)

        render json: {
          checkout_session_id: session.id,
          checkout_url: session.url,
          message: 'Please complete payment to create your account'
        }, status: :created
      else
        # No plan_id provided - return pending registration ID for plan selection step
        render json: {
          pending_registration_id: pending_registration.id,
          email: pending_registration.email,
          name: pending_registration.name,
          account_type: pending_registration.account_type,
          message: 'Registration successful. Please select a plan to continue.'
        }, status: :created
      end

    rescue ActiveRecord::RecordNotFound => e
      render json: {
        error: 'Registration failed',
        message: 'Selected plan not found',
        details: [e.message]
      }, status: :not_found
    rescue Stripe::StripeError => e
      pending_registration&.destroy
      Rails.logger.error "Stripe error during registration: #{e.message}"
      render json: {
        error: 'Payment processing error',
        message: e.message
      }, status: :internal_server_error
    rescue => e
      pending_registration&.destroy
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
    
    if user.nil?
      render json: {
        error: 'Account does not exist',
        message: 'No account found with this email address. Please check your email or register for a new account.'
      }, status: :unauthorized
      return
    end
    
    if user&.authenticate(params[:password])
      token = JsonWebToken.encode(user_id: user.id)
      render json: {
        user: user_json(user),
        token: token,
        message: 'Login successful'
      }
    else
      render json: {
        error: 'Invalid password',
        message: 'The password you entered is incorrect. Please try again.'
      }, status: :unauthorized
    end
  end

  # POST /api/v1/auth/forgot_password
  # Request password reset - generates token and sends reset link
  # Params: email
  # Returns: success message (for security, always returns success even if email not found)
  def forgot_password
    email = params[:email]
    
    if email.blank?
      return render json: {
        error: 'Email is required',
        message: 'Please provide your email address'
      }, status: :bad_request
    end
    
    user = User.find_by(email: email)
    
    # For security, always return success message (don't reveal if email exists)
    if user
      user.generate_password_reset_token!
      
      # Generate reset URL
      frontend_url = ENV['FRONTEND_URL'] || 'https://my.socialrotation.app'
      # Remove any trailing slashes and ensure proper URL construction
      base_url = frontend_url.to_s.gsub(/\/+$/, '')
      reset_url = "#{base_url}/reset-password?token=#{user.password_reset_token}"
      
      # Send password reset email
      begin
        PasswordResetMailer.reset_password_email(user, reset_url).deliver_now
        Rails.logger.info "Password reset email sent to #{email}"
        # Log reset URL for debugging (remove in production if security is a concern)
        Rails.logger.info "PASSWORD RESET URL for #{email}: #{reset_url}"
      rescue => e
        Rails.logger.error "Failed to send password reset email to #{email}: #{e.message}"
        # Log the reset URL so it can be retrieved from logs if email isn't configured
        Rails.logger.info "PASSWORD RESET URL for #{email}: #{reset_url}"
        # Still return success for security (don't reveal email delivery issues)
      end
    end
    
    # Always return success for security (don't reveal if email exists)
    render json: {
      message: 'If an account with that email exists, a password reset link has been sent.'
    }
  end

  # POST /api/v1/auth/reset_password
  # Reset password using token
  # Params: token, password, password_confirmation
  # Returns: success message
  def reset_password
    token = params[:token]
    password = params[:password]
    password_confirmation = params[:password_confirmation]
    
    if token.blank?
      return render json: {
        error: 'Reset token is required',
        message: 'Please provide a valid reset token'
      }, status: :bad_request
    end
    
    if password.blank?
      return render json: {
        error: 'Password is required',
        message: 'Please provide a new password'
      }, status: :bad_request
    end
    
    if password != password_confirmation
      return render json: {
        error: 'Passwords do not match',
        message: 'Password and password confirmation must match'
      }, status: :unprocessable_entity
    end
    
    user = User.find_by(password_reset_token: token)
    
    if user.nil?
      return render json: {
        error: 'Invalid reset token',
        message: 'The password reset link is invalid or has expired. Please request a new one.'
      }, status: :unprocessable_entity
    end
    
    unless user.password_reset_token_valid?
      return render json: {
        error: 'Reset token expired',
        message: 'The password reset link has expired. Please request a new one.'
      }, status: :unprocessable_entity
    end
    
    # Update password
    if user.update(password: password, password_confirmation: password_confirmation)
      user.clear_password_reset_token!
      
      render json: {
        message: 'Password has been reset successfully. You can now log in with your new password.'
      }
    else
      render json: {
        error: 'Password reset failed',
        message: user.errors.full_messages.join(', ')
      }, status: :unprocessable_entity
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
