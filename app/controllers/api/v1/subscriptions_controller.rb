class Api::V1::SubscriptionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:webhook]
  before_action :authenticate_user!, except: [:webhook]
  before_action :require_account_admin!, only: [:create, :checkout_session, :cancel]
  before_action :check_stripe_configured!, only: [:checkout_session, :cancel, :webhook]
  
  # POST /api/v1/subscriptions/checkout_session
  # Create Stripe Checkout Session for a plan
  # Params: plan_id, billing_period (optional, default: 'monthly')
  def checkout_session
    plan = Plan.find(params[:plan_id])
    billing_period = params[:billing_period] || 'monthly'
    
    unless plan.status?
      return render json: { error: 'Plan is not available' }, status: :bad_request
    end
    
    account = current_user.account
    
    # Set Stripe API key
    Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || ''
    
    begin
      # Create or retrieve Stripe customer
      customer = get_or_create_stripe_customer(account)
      
      # Calculate price based on plan type
      if plan.supports_per_user_pricing
        # For per-user pricing, calculate based on current user count
        user_count = account.users.active.count
        price_cents = plan.calculate_price_for_users(user_count, billing_period)
        
        # Create a one-time price for this specific subscription
        # Or use a recurring price if you prefer
        stripe_price = Stripe::Price.create({
          unit_amount: price_cents,
          currency: 'usd',
          recurring: {
            interval: billing_period == 'annual' ? 'year' : 'month',
          },
          product_data: {
            name: "#{plan.name} (#{user_count} user#{user_count != 1 ? 's' : ''})",
            description: "Subscription for #{user_count} user#{user_count != 1 ? 's' : ''}"
          }
        })
        
        line_items = [{
          price: stripe_price.id,
          quantity: 1,
        }]
      else
        # For fixed-price plans, use the plan's stripe_price_id
        unless plan.stripe_price_id.present?
          return render json: { error: 'Plan does not have a Stripe price configured' }, status: :bad_request
        end
        
        line_items = [{
          price: plan.stripe_price_id,
          quantity: 1,
        }]
      end
      
      # Create Checkout Session
      session = Stripe::Checkout::Session.create({
        customer: customer.id,
        payment_method_types: ['card'],
        line_items: line_items,
        mode: 'subscription',
        success_url: "#{frontend_url}/profile?success=subscription_active",
        cancel_url: "#{frontend_url}/profile?error=subscription_canceled",
        metadata: {
          account_id: account.id,
          plan_id: plan.id,
          user_id: current_user.id,
          billing_period: billing_period,
          user_count: plan.supports_per_user_pricing ? account.users.active.count : nil
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
    account = current_user.account
    
    # Handle personal accounts (account_id = 0) - they don't have an Account record
    if account.nil? || (current_user.account_id == 0)
      return render json: {
        subscription: nil
      }
    end
    
    subscription = account.subscription
    
    if subscription
      render json: {
        subscription: subscription_json(subscription)
      }
    else
      render json: {
        subscription: nil
      }
    end
  rescue => e
    Rails.logger.error "Subscriptions index error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { 
      error: 'Failed to load subscription',
      message: e.message
    }, status: :internal_server_error
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
      return head :bad_request
    end
    
    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error "Webhook JSON parse error: #{e.message}"
      return head :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Webhook signature verification error: #{e.message}"
      return head :bad_request
    end
    
    # Handle the event
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
    
    head :ok
  end
  
  private
  
  def require_account_admin!
    unless current_user.account_admin? || current_user.super_admin?
      render json: { error: 'Only account admins can manage subscriptions' }, status: :forbidden
    end
  end
  
  def check_stripe_configured!
    unless ENV['STRIPE_SECRET_KEY'].present?
      render json: { error: 'Stripe is not configured. Please set STRIPE_SECRET_KEY environment variable.' }, status: :service_unavailable
    end
  rescue => e
    Rails.logger.error "Stripe configuration check failed: #{e.message}"
    render json: { error: 'Stripe service unavailable' }, status: :service_unavailable
  end
  
  def frontend_url
    ENV['FRONTEND_URL'] || 'https://social-rotation-frontend-f4mwb.ondigitalocean.app'
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
      name: account.name,
      metadata: {
        account_id: account.id
      }
    })
    
    customer
  end
  
  def handle_checkout_completed(session)
    account_id = session.metadata['account_id'].to_i
    plan_id = session.metadata['plan_id'].to_i
    billing_period = session.metadata['billing_period'] || 'monthly'
    user_count = session.metadata['user_count']&.to_i
    
    account = Account.find_by(id: account_id)
    plan = Plan.find_by(id: plan_id)
    
    return unless account && plan
    
    # Get subscription from Stripe
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    stripe_subscription = Stripe::Subscription.list(customer: session.customer, limit: 1).data.first
    
    return unless stripe_subscription
    
    # Create or update subscription
    subscription = account.subscription || account.build_subscription
    subscription.assign_attributes(
      plan: plan,
      stripe_customer_id: session.customer,
      stripe_subscription_id: stripe_subscription.id,
      status: stripe_subscription.status,
      billing_period: billing_period,
      user_count_at_subscription: user_count || account.users.active.count,
      current_period_start: Time.at(stripe_subscription.current_period_start),
      current_period_end: Time.at(stripe_subscription.current_period_end),
      cancel_at_period_end: stripe_subscription.cancel_at_period_end
    )
    subscription.save!
    
    # Update account with plan
    account.update!(plan: plan)
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
  
  def subscription_json(subscription)
    {
      id: subscription.id,
      plan: {
        id: subscription.plan.id,
        name: subscription.plan.name,
        plan_type: subscription.plan.plan_type
      },
      status: subscription.status,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      days_remaining: subscription.days_remaining,
      active: subscription.active?,
      will_cancel: subscription.will_cancel?
    }
  end
end
