# Authentication Controller
# Handles user registration and login
# Endpoints:
#   POST /api/v1/auth/register - Create new user account
#   POST /api/v1/auth/login - Authenticate existing user
class Api::V1::AuthController < ApplicationController
  # Skip authentication for auth endpoints (otherwise can't login!)
  # Must be called before ApplicationController's before_action callbacks
  skip_before_action :authenticate_user!, only: [:register, :login], raise: false
  skip_before_action :require_active_subscription!, only: [:register, :login], raise: false

  # POST /api/v1/auth/register
  # Create pending registration and Stripe checkout session
  # Account and user will be created AFTER successful payment in webhook
  # Params: name, email, password, password_confirmation, account_type, company_name, plan_id, billing_period
  # Returns: checkout_session_id and checkout_url
  def register
    begin
      # Validate company name for agency accounts
      if params[:account_type] == 'agency' && params[:company_name].blank?
        return render json: {
          error: 'Company name is required for agency accounts',
          message: 'Please provide a company or agency name',
          field: 'company_name'
        }, status: :unprocessable_entity
      end

      # Check if user already exists
      existing_user = User.find_by(email: params[:email])
      if existing_user
        return render json: {
          error: 'Registration failed',
          message: 'Email has already been taken',
          details: ['Email has already been taken']
        }, status: :unprocessable_entity
      end

      # Check if pending registration already exists
      existing_pending = PendingRegistration.find_by(email: params[:email])
      if existing_pending && !existing_pending.expired?
        # Delete expired pending registration
        existing_pending.destroy if existing_pending.expired?
      end

      # Validate plan_id is provided
      unless params[:plan_id].present?
        return render json: {
          error: 'Plan selection required',
          message: 'Please select a subscription plan'
        }, status: :bad_request
      end

      plan = Plan.find_by(id: params[:plan_id])
      unless plan&.status?
        return render json: {
          error: 'Invalid plan',
          message: 'Selected plan is not available'
        }, status: :bad_request
      end

      # Create pending registration (validates email, name, password)
      pending_registration = PendingRegistration.new(
        email: params[:email],
        name: params[:name],
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        account_type: params[:account_type] || 'personal',
        company_name: params[:company_name]
      )

      unless pending_registration.save
        return render json: {
          error: 'Registration failed',
          message: pending_registration.errors.full_messages.join('. '),
          details: pending_registration.errors.full_messages,
          errors: pending_registration.errors.as_json
        }, status: :unprocessable_entity
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

      # Store session ID in pending registration
      pending_registration.update!(stripe_session_id: session.id)

      render json: {
        checkout_session_id: session.id,
        checkout_url: session.url,
        message: 'Please complete payment to create your account'
      }, status: :created

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
