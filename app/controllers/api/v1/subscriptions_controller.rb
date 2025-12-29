class Api::V1::SubscriptionsController < ApplicationController
  include JsonSerializers
  
  skip_before_action :authenticate_user!, only: [:webhook, :test_stripe, :checkout_session_for_pending]
  before_action :require_account_admin!, only: [:create, :cancel]
  before_action :check_stripe_configured!, only: [:checkout_session, :checkout_session_for_pending, :cancel, :webhook]
  skip_before_action :require_active_subscription!, only: [:index, :show, :create, :checkout_session, :checkout_session_for_pending, :cancel, :webhook, :test_stripe]
  
  # GET /api/v1/subscriptions/test_stripe
  # Test Stripe connection and configuration
  def test_stripe
    check_stripe_configured!
    return if performed?
    
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    
    begin
      # Test 1: List products (works with restricted keys)
      products = Stripe::Product.list(limit: 10)
      
      # Test 2: List prices (works with restricted keys)
      prices = Stripe::Price.list(limit: 10)
      
      # Test 3: Try to retrieve account (may fail with restricted keys, that's OK)
      account_info = nil
      begin
        account = Stripe::Account.retrieve
        account_info = {
          id: account.id,
          email: account.email,
          country: account.country,
          default_currency: account.default_currency
        }
      rescue Stripe::PermissionError => e
        account_info = {
          error: 'Account endpoint requires additional permissions',
          message: 'Using restricted API key (this is OK for most operations)',
          note: 'Products and prices can still be accessed'
        }
      end
      
      render json: {
        status: 'success',
        message: 'Stripe is connected and working!',
        api_key_type: ENV['STRIPE_SECRET_KEY']&.start_with?('rk_') ? 'restricted' : 'secret',
        account: account_info,
        products_count: products.data.length,
        prices_count: prices.data.length,
        products: products.data.map { |p| { 
          id: p.id, 
          name: p.name, 
          active: p.active,
          description: p.description
        } },
        prices: prices.data.map { |pr| { 
          id: pr.id, 
          amount: pr.unit_amount, 
          currency: pr.currency, 
          active: pr.active,
          recurring: pr.recurring ? { interval: pr.recurring.interval } : nil
        } }
      }
    rescue Stripe::AuthenticationError => e
      render json: {
        status: 'error',
        message: 'Stripe authentication failed',
        error: e.message,
        details: 'Check your STRIPE_SECRET_KEY environment variable - it may be invalid or expired'
      }, status: :unauthorized
    rescue Stripe::PermissionError => e
      render json: {
        status: 'partial_success',
        message: 'Stripe is connected but using restricted key',
        error: e.message,
        note: 'Your API key works but has limited permissions. This is normal for restricted keys.',
        suggestion: 'You can still create checkout sessions and process payments'
      }
    rescue Stripe::StripeError => e
      render json: {
        status: 'error',
        message: 'Stripe API error',
        error: e.message,
        error_type: e.class.name
      }, status: :bad_request
    rescue => e
      render json: {
        status: 'error',
        message: 'Unexpected error',
        error: e.message,
        backtrace: Rails.env.development? ? e.backtrace.first(5) : nil
      }, status: :internal_server_error
    end
  end

  # POST /api/v1/subscriptions/checkout_session_for_pending
  # Create Stripe checkout session for pending registration (after plan selection)
  # Params: pending_registration_id, plan_id, billing_period (optional), user_count (optional)
  def checkout_session_for_pending
    pending_registration = PendingRegistration.find_by(id: params[:pending_registration_id])
    unless pending_registration
      return render json: { error: 'Pending registration not found' }, status: :not_found
    end

    if pending_registration.expired?
      pending_registration.destroy
      return render json: { error: 'Registration session expired. Please register again.' }, status: :unprocessable_entity
    end

    plan = Plan.find_by(id: params[:plan_id])
    unless plan&.status?
      return render json: { error: 'Plan is not available' }, status: :bad_request
    end

    Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || ''
    billing_period = params[:billing_period] || 'monthly'
    user_count = params[:user_count]&.to_i || 1

    begin
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
      frontend_url = ENV['FRONTEND_URL']
      
      # Validate and clean the frontend URL
      if frontend_url.blank?
        frontend_url = 'https://my.socialrotation.app'
        Rails.logger.warn "FRONTEND_URL not set, using default: #{frontend_url}"
      else
        frontend_url = frontend_url.to_s.strip.chomp('/')
        unless frontend_url.match?(/\Ahttps?:\/\/.+\z/)
          Rails.logger.error "Invalid FRONTEND_URL format: #{frontend_url.inspect}"
          # Fallback to default if invalid
          frontend_url = 'https://my.socialrotation.app'
          Rails.logger.warn "Using default FRONTEND_URL: #{frontend_url}"
        end
      end
      
      success_url = "#{frontend_url}/profile?success=subscription_active&session_id={CHECKOUT_SESSION_ID}"
      cancel_url = "#{frontend_url}/register?error=subscription_canceled"
      
      Rails.logger.info "Creating checkout session with success_url: #{success_url}, cancel_url: #{cancel_url}"

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
      }
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: "Payment processing error: #{e.message}" }, status: :internal_server_error
    rescue => e
      Rails.logger.error "Checkout session error: #{e.message}"
      render json: { error: "Failed to create checkout session" }, status: :internal_server_error
    end
  end

  # POST /api/v1/subscriptions/checkout_session
  # Create Stripe Checkout Session for a plan
  # Params: plan_id, billing_period (optional, default: 'monthly'), account_type, company_name, user_count
  # Note: Account is NOT created here - it will be created in webhook after successful payment
  def checkout_session
    plan = Plan.find(params[:plan_id])
    billing_period = params[:billing_period] || 'monthly'
    account_type = params[:account_type] || 'personal'
    company_name = params[:company_name]
    user_count = params[:user_count]&.to_i || 1
    
    unless plan.status?
      return render json: { error: 'Plan is not available' }, status: :bad_request
    end
    
    # Validate company name for agency accounts
    if account_type == 'agency' && company_name.blank?
      return render json: { error: 'Company name is required for agency accounts' }, status: :bad_request
    end
    
    # Set Stripe API key
    Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || ''
    
    begin
      # Get or create Stripe customer
      # For existing accounts, try to reuse customer ID from subscription
      customer = nil
      if current_user.account_id && current_user.account_id > 0 && current_user.account&.subscription&.stripe_customer_id.present?
        begin
          customer = Stripe::Customer.retrieve(current_user.account.subscription.stripe_customer_id)
        rescue Stripe::StripeError
          # Customer doesn't exist, create new one
        end
      end
      
      # Create new customer if we don't have one
      unless customer
        customer = Stripe::Customer.create({
          email: current_user.email,
          name: current_user.name,
          metadata: {
            user_id: current_user.id.to_s
          }
        })
      end
      
      # Check if there's a pending registration for this user (shouldn't happen, but handle it)
      pending_registration = PendingRegistration.find_by(email: current_user.email)
      if pending_registration && !pending_registration.expired?
        # User already exists but has pending registration - clean it up
        pending_registration.destroy
      end
      
      # Calculate price based on plan type
      if plan.supports_per_user_pricing
        # For per-user pricing, calculate based on provided user count
        price_cents = plan.calculate_price_for_users(user_count, billing_period)
        
        # Create a recurring price for this specific subscription
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
        
        line_items = [{
          price: stripe_price.id,
          quantity: 1,
        }]
      else
        # For fixed-price plans, use the plan's stripe_price_id if available
        # Otherwise, create a price dynamically
        if plan.stripe_price_id.present?
          line_items = [{
            price: plan.stripe_price_id,
            quantity: 1,
          }]
        else
          # Create a price dynamically for fixed-price plans
          price_cents = plan.price_cents || 0
          unless price_cents > 0
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
          
          line_items = [{
            price: stripe_price.id,
            quantity: 1,
          }]
        end
      end
      
      # Create Checkout Session
      # Store registration info in metadata - account will be created in webhook
      success_url = "#{frontend_url}/profile?success=subscription_active&session_id={CHECKOUT_SESSION_ID}"
      cancel_url = "#{frontend_url}/register?error=subscription_canceled"
      
      Rails.logger.info "Creating Stripe checkout session with success_url: #{success_url}, cancel_url: #{cancel_url}"
      
      session = Stripe::Checkout::Session.create({
        customer: customer.id,
        # Only allow card payments (no Link, Apple Pay, Google Pay, etc.)
        payment_method_types: ['card'],
        line_items: line_items,
        mode: 'subscription',
        success_url: success_url,
        cancel_url: cancel_url,
        # Disable Pay with Link explicitly (removed invalid require_cvc parameter)
        # Collect billing address (can help reduce fraud checks)
        billing_address_collection: 'required',
        # Disable automatic tax (if not needed)
        automatic_tax: {
          enabled: false
        },
        metadata: {
          user_id: current_user.id.to_s,
          plan_id: plan.id.to_s,
          billing_period: billing_period,
          account_type: account_type,
          company_name: company_name || '',
          user_count: user_count.to_s
        }
      })
      
      render json: {
        checkout_session_id: session.id,
        checkout_url: session.url
      }
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: "Payment processing error: #{e.message}" }, status: :internal_server_error
    rescue => e
      Rails.logger.error "Subscription error: #{e.message}"
      render json: { error: "Failed to create checkout session" }, status: :internal_server_error
    end
  end
  
  # GET /api/v1/subscriptions
  # Get current subscription for the user's account
  def index
    begin
      # Handle personal accounts (account_id = 0) - they don't have an Account record
      if current_user.account_id.nil? || current_user.account_id == 0
        return render json: {
          subscription: nil
        }
      end
      
      # Get account - this might return nil if account_id doesn't exist
      account = current_user.account
      
      if account.nil?
        return render json: {
          subscription: nil
        }
      end
      
      # Safely get subscription - might be nil
      subscription = account.subscription rescue nil
      
      if subscription && subscription.persisted?
        begin
          render json: {
            subscription: subscription_json(subscription)
          }
        rescue => e
          Rails.logger.error "Error serializing subscription: #{e.message}"
          render json: {
            subscription: nil
          }
        end
      else
        render json: {
          subscription: nil
        }
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "Subscriptions index - Account not found: #{e.message}"
      render json: {
        subscription: nil
      }
    rescue => e
      Rails.logger.error "Subscriptions index error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { 
        error: 'Failed to load subscription',
        message: e.message
      }, status: :internal_server_error
    end
  end

  # POST /api/v1/subscriptions
  # Create subscription (called after successful Stripe checkout)
  def create
    # This is typically called via webhook, but can be used for manual creation
    account = current_user.account
    plan = Plan.find(params[:plan_id])
    
    # Check if account already has an active subscription
    if account.subscription&.active?
      return render json: { 
        error: 'Account already has an active subscription',
        subscription: subscription_json(account.subscription)
      }, status: :conflict
    end
    
    subscription = account.build_subscription(
      plan: plan,
      stripe_customer_id: params[:stripe_customer_id],
      stripe_subscription_id: params[:stripe_subscription_id],
      status: params[:status] || Subscription::STATUS_ACTIVE,
      current_period_start: params[:current_period_start] ? Time.at(params[:current_period_start]) : Time.current,
      current_period_end: params[:current_period_end] ? Time.at(params[:current_period_end]) : 1.month.from_now
    )
    
    if subscription.save
      # Update account with plan
      account.update!(plan: plan)
      
      render json: {
        subscription: subscription_json(subscription),
        message: 'Subscription created successfully'
      }, status: :created
    else
      render json: {
        errors: subscription.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  # GET /api/v1/subscriptions
  # Get current account's subscription
  def show
    account = current_user.account
    
    if account.subscription
      render json: {
        subscription: subscription_json(account.subscription)
      }
    else
      render json: {
        subscription: nil,
        message: 'No active subscription'
      }
    end
  end
  
  # POST /api/v1/subscriptions/cancel
  # Cancel current subscription
  def cancel
    account = current_user.account
    subscription = account.subscription
    
    unless subscription&.active?
      return render json: { error: 'No active subscription to cancel' }, status: :bad_request
    end
    
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    
    begin
      # Cancel subscription at period end in Stripe
      stripe_subscription = Stripe::Subscription.update(
        subscription.stripe_subscription_id,
        cancel_at_period_end: true
      )
      
      # Update local subscription
      subscription.update!(
        cancel_at_period_end: true,
        status: stripe_subscription.status
      )
      
      render json: {
        subscription: subscription_json(subscription),
        message: 'Subscription will be canceled at the end of the current period'
      }
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe cancel error: #{e.message}"
      render json: { error: "Failed to cancel subscription: #{e.message}" }, status: :internal_server_error
    end
  end
  
  # POST /api/v1/subscriptions/webhook
  # Handle Stripe webhooks (no authentication required - uses webhook secret)
  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']
    
    unless endpoint_secret.present?
      Rails.logger.error "STRIPE_WEBHOOK_SECRET not configured"
      # Still return 200 to prevent Stripe from retrying
      return head :ok
    end
    
    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error "Webhook JSON parse error: #{e.message}"
      # Return 200 to prevent Stripe from retrying invalid JSON
      return head :ok
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Webhook signature verification error: #{e.message}"
      # Return 200 to prevent Stripe from retrying signature failures
      return head :ok
    end
    
    # Handle the event
    begin
      case event.type
      when 'checkout.session.completed'
        handle_checkout_completed(event.data.object)
      when 'customer.subscription.updated'
        handle_subscription_updated(event.data.object)
      when 'customer.subscription.deleted'
        handle_subscription_deleted(event.data.object)
      when 'invoice.payment_succeeded'
        handle_payment_succeeded(event.data.object)
      when 'invoice.payment_failed'
        handle_payment_failed(event.data.object)
      else
        Rails.logger.info "Unhandled webhook event type: #{event.type}"
      end
    rescue => e
      # Log error but still return 200 to prevent Stripe from retrying
      # This allows us to investigate and fix issues without webhook failures
      Rails.logger.error "Webhook handler error for #{event.type}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    head :ok
  end
  
  private
  
  def require_account_admin!
    # Allow during registration (user might not be account admin yet)
    return if params[:skip_admin_check] == 'true'
    
    unless current_user.account_admin? || current_user.super_admin?
      render json: { error: 'Only account admins can manage subscriptions' }, status: :forbidden
    end
  end
  
  def check_stripe_configured!
    unless ENV['STRIPE_SECRET_KEY'].present?
      render json: { error: 'Stripe is not configured. Please set STRIPE_SECRET_KEY environment variable.' }, status: :service_unavailable
      return
    end
  rescue => e
    Rails.logger.error "Stripe configuration check failed: #{e.message}"
    render json: { error: 'Stripe service unavailable' }, status: :service_unavailable
    return
  end
  
  def frontend_url
    url = ENV['FRONTEND_URL'] || 'https://social-rotation-frontend-f4mwb.ondigitalocean.app'
    # Remove any whitespace and trailing slashes
    url = url.strip.chomp('/')
    # Ensure URL is valid and starts with http:// or https://
    unless url.match?(/\Ahttps?:\/\//)
      Rails.logger.error "Invalid FRONTEND_URL format: #{url}"
      url = 'https://my.socialrotation.app'
    end
    Rails.logger.info "Frontend URL: #{url}"
    url
  end
  
  def get_or_create_stripe_customer(account)
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    
    # Check if account already has a customer ID
    if account.subscription&.stripe_customer_id.present?
      begin
        return Stripe::Customer.retrieve(account.subscription.stripe_customer_id)
      rescue Stripe::StripeError
        # Customer doesn't exist, create new one
      end
    end
    
    # Create new Stripe customer
    customer = Stripe::Customer.create({
      email: current_user.email,
      name: account.name || current_user.name,
      metadata: {
        account_id: account.id,
        user_id: current_user.id
      }
    })
    
    customer
  end
  
  def handle_checkout_completed(session)
    plan_id = session.metadata['plan_id'].to_i
    billing_period = session.metadata['billing_period'] || 'monthly'
    account_type = session.metadata['account_type'] || 'personal'
    company_name = session.metadata['company_name']
    user_count = session.metadata['user_count']&.to_i || 1
    
    plan = Plan.find_by(id: plan_id)
    return unless plan

    # Check if this is a new registration (pending_registration_id) or existing user (user_id)
    pending_registration_id = session.metadata['pending_registration_id']
    user_id = session.metadata['user_id']&.to_i
    
    user = nil
    
    if pending_registration_id.present?
      # New registration - create user from pending registration
      pending_registration = PendingRegistration.find_by(id: pending_registration_id)
      return unless pending_registration
      
      # Check if user already exists (race condition protection)
      user = User.find_by(email: pending_registration.email)
      unless user
        # Create user from pending registration
        user = pending_registration.create_user!
      end
      
      # Clean up pending registration
      pending_registration.destroy
    elsif user_id > 0
      # Existing user - find by ID
      user = User.find_by(id: user_id)
      return unless user
    else
      # No user identifier - can't proceed
      Rails.logger.error "Checkout completed but no user_id or pending_registration_id in metadata"
      return
    end
    
    # Create account NOW (after successful payment)
    if account_type == 'agency' && company_name.present?
      account = Account.create!(
        name: company_name,
        is_reseller: true,
        status: true
      )
      user.update!(
        account_id: account.id,
        is_account_admin: true,
        role: 'reseller'
      )
    else
      # Personal account
      account = Account.create!(
        name: "#{user.name}'s Account",
        is_reseller: false,
        status: true
      )
      user.update!(
        account_id: account.id,
        is_account_admin: true
      )
    end
    
    # Get subscription from Stripe
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    stripe_subscription = Stripe::Subscription.list(customer: session.customer, limit: 1).data.first
    
    return unless stripe_subscription
    
    # Create subscription
    subscription = account.create_subscription!(
      plan: plan,
      stripe_customer_id: session.customer,
      stripe_subscription_id: stripe_subscription.id,
      status: stripe_subscription.status,
      billing_period: billing_period,
      user_count_at_subscription: user_count,
      current_period_start: Time.at(stripe_subscription.current_period_start),
      current_period_end: Time.at(stripe_subscription.current_period_end),
      cancel_at_period_end: stripe_subscription.cancel_at_period_end
    )
    
    # Update account with plan
    account.update!(plan: plan)
    
    Rails.logger.info "Account #{account.id} created for user #{user.id} after successful payment"
  end
  
  def handle_subscription_updated(stripe_subscription)
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription.id)
    return unless subscription
    
    subscription.update!(
      status: stripe_subscription.status,
      current_period_start: Time.at(stripe_subscription.current_period_start),
      current_period_end: Time.at(stripe_subscription.current_period_end),
      cancel_at_period_end: stripe_subscription.cancel_at_period_end,
      canceled_at: stripe_subscription.canceled_at ? Time.at(stripe_subscription.canceled_at) : nil
    )
  end
  
  def handle_subscription_deleted(stripe_subscription)
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription.id)
    return unless subscription
    
    subscription.update!(
      status: Subscription::STATUS_CANCELED,
      canceled_at: Time.current
    )
  end
  
  def handle_payment_succeeded(invoice)
    # Update subscription period if needed
    stripe_subscription_id = invoice.subscription
    return unless stripe_subscription_id
    
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription_id)
    return unless subscription
    
    # Refresh subscription from Stripe
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)
    
    subscription.update!(
      status: stripe_subscription.status,
      current_period_start: Time.at(stripe_subscription.current_period_start),
      current_period_end: Time.at(stripe_subscription.current_period_end)
    )
  end
  
  def handle_payment_failed(invoice)
    stripe_subscription_id = invoice.subscription
    return unless stripe_subscription_id
    
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription_id)
    return unless subscription
    
    subscription.update!(status: Subscription::STATUS_PAST_DUE)
  end
  
end
