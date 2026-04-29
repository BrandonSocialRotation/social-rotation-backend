# frozen_string_literal: true

class Api::V1::Admin::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_super_admin!

  # GET /api/v1/admin/accounts — grouped by billing/account org (super admins only).
  # Reseller/agency accounts: admins first, then sub-accounts under the same group.
  def index
    users = User.includes(:account).order(:account_id, :is_account_admin, :id).to_a
    by_account_id = users.group_by(&:account_id)

    ordered_keys = sort_account_keys(by_account_id.keys)
    groups = ordered_keys.filter_map do |account_key|
      members = by_account_id[account_key]
      next if members.blank?

      account = account_key.present? ? Account.find_by(id: account_key) : nil
      main_users, sub_users = partition_main_and_subs(account, members)

      {
        account_id: account_key,
        account_title: account_group_title(account, account_key, members),
        account_kind: account_kind_for_group(account, members),
        main_users: main_users.map { |u| user_payload(u, :main, account) },
        sub_accounts: sub_users.map { |u| user_payload(u, :sub, account) }
      }
    end

    render json: { groups: groups }
  end

  private

  def require_super_admin!
    return if current_user&.super_admin?

    render json: { error: 'Forbidden' }, status: :forbidden
  end

  # Keys sorted: platform account id 0 first, then by account name, then nil last.
  def sort_account_keys(keys)
    ids = keys.compact
    ids.sort_by! do |aid|
      acc = Account.find_by(id: aid)
      segment = aid.to_i == Account::SUPER_ADMIN_ACCOUNT_ID ? 0 : 1
      [segment, acc&.name.to_s.downcase, aid.to_i]
    end
    ordered = ids
    ordered << nil if keys.include?(nil)
    ordered
  end

  def partition_main_and_subs(account, members)
    # Agencies/resellers: account admins are “main”; everyone else under that org is a sub-account.
    if account&.is_reseller
      mains = members.select(&:is_account_admin)
      subs = members.reject(&:is_account_admin)
      return [mains, subs]
    end

    # Personal / single-tenant groups: everyone listed together under “main” (no sub rows).
    [members, []]
  end

  def account_group_title(account, account_key, members)
    return 'No attached account' if account_key.nil?

    if account_key.to_i == Account::SUPER_ADMIN_ACCOUNT_ID
      return 'Platform (super admins)'
    end

    account&.name.presence || "Account ##{account_key}"
  end

  def account_kind_for_group(account, members)
    return 'Super admin' if members.any?(&:super_admin?)

    account&.is_reseller ? 'Agency' : 'Personal'
  end

  def user_payload(user, slot, account)
    {
      id: user.id,
      username: user.email,
      name: user.name,
      role: role_label(user, slot, account),
      account_type: account_type_label(user, user.account),
      active: user.status.to_i == 1
    }
  end

  def role_label(user, slot, account)
    if slot == :sub
      client_portal = user.respond_to?(:client_portal_only?) && user.client_portal_only?
      return client_portal ? 'Sub-account (client portal)' : 'Sub-account'
    end

    return 'Super admin' if user.super_admin?
    return 'Account admin' if user.is_account_admin

    account&.is_reseller ? 'Account admin' : 'Personal'
  end

  def account_type_label(user, account)
    return 'Super admin' if user.super_admin?
    return 'Client portal' if user.respond_to?(:client_portal_only?) && user.client_portal_only?

    account&.is_reseller ? 'Agency' : 'Personal'
  end
end
