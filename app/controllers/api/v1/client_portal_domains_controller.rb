# frozen_string_literal: true

# Reseller-only: assign pool hostnames to client sub-accounts and set branding JSON.
class Api::V1::ClientPortalDomainsController < ApplicationController
  before_action :require_reseller!
  before_action :set_domain, only: [:update, :destroy]

  # GET /api/v1/client_portal_domains
  def index
    scope = domain_scope
    render json: { client_portal_domains: scope.includes(:user).map { |d| domain_json(d) } }
  end

  # POST /api/v1/client_portal_domains
  def create
    user = find_authorized_client_user(params.dig(:client_portal_domain, :user_id))
    return if performed?

    raw = params.require(:client_portal_domain)
    hostname = raw[:hostname]
    branding = raw[:branding]
    branding = branding.to_unsafe_h if branding.respond_to?(:to_unsafe_h)
    branding = {} unless branding.is_a?(Hash)

    domain = ClientPortalDomain.new(
      hostname: hostname,
      user: user,
      account_id: user.account_id,
      branding: branding.stringify_keys
    )

    if domain.save
      render json: { client_portal_domain: domain_json(domain) }, status: :created
    else
      render json: { errors: domain.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/client_portal_domains/:id
  def update
    raw = params.require(:client_portal_domain)
    attrs = {}
    attrs[:hostname] = raw[:hostname] if raw.key?(:hostname)
    if raw.key?(:branding)
      b = raw[:branding]
      b = b.to_unsafe_h if b.respond_to?(:to_unsafe_h)
      attrs[:branding] = @domain.branding.merge((b.is_a?(Hash) ? b : {}).stringify_keys) if b.is_a?(Hash) || b.respond_to?(:to_unsafe_h)
    end

    if @domain.update(attrs)
      render json: { client_portal_domain: domain_json(@domain) }
    else
      render json: { errors: @domain.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/client_portal_domains/:id
  def destroy
    @domain.destroy
    render json: { message: 'Domain assignment removed' }
  end

  private

  def domain_scope
    if current_user.super_admin?
      ClientPortalDomain.where(account_id: current_user.account_id || 0)
    else
      ClientPortalDomain.where(account_id: current_user.account_id)
    end
  end

  def require_reseller!
    unless current_user.reseller? || current_user.super_admin?
      render json: { error: 'Only agencies can manage client portal domains' }, status: :forbidden
    end
  end

  def set_domain
    @domain = domain_scope.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def find_authorized_client_user(user_id)
    user = User.find_by(id: user_id)
    unless user
      render json: { error: 'User not found' }, status: :not_found
      return nil
    end

    if current_user.super_admin?
      unless user.account_id == (current_user.account_id || 0) && !user.is_account_admin?
        render json: { error: 'Unauthorized' }, status: :forbidden
        return nil
      end
    elsif current_user.account_users.include?(user)
      # ok — sub-account under same agency
    else
      render json: { error: 'User is not a sub-account in your agency' }, status: :forbidden
      return nil
    end
    user
  end

  def domain_json(domain)
    {
      id: domain.id,
      hostname: domain.hostname,
      user_id: domain.user_id,
      account_id: domain.account_id,
      branding: domain.branding_payload,
      created_at: domain.created_at,
      updated_at: domain.updated_at
    }
  end
end
