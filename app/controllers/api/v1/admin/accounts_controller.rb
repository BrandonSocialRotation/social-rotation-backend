# frozen_string_literal: true

class Api::V1::Admin::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_super_admin!

  # GET /api/v1/admin/accounts — list all users for platform overview (super admins only)
  def index
    users = User.includes(:account).order(:id)
    render json: {
      accounts: users.map { |u| account_row(u) }
    }
  end

  private

  def require_super_admin!
    return if current_user&.super_admin?

    render json: { error: 'Forbidden' }, status: :forbidden
  end

  def account_row(user)
    account = user.account
    {
      id: user.id,
      username: user.email,
      name: user.name,
      account_type: account_type_label(user, account),
      active: user.status.to_i == 1
    }
  end

  def account_type_label(user, account)
    return 'Super admin' if user.super_admin?
    return 'Client portal' if user.respond_to?(:client_portal_only?) && user.client_portal_only?

    account&.is_reseller ? 'Agency' : 'Personal'
  end
end
