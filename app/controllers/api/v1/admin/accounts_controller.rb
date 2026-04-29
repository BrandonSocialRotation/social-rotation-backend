# frozen_string_literal: true

class Api::V1::Admin::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_super_admin!

  # GET /api/v1/admin/accounts — grouped by billing/account org (super admins only).
  # Reseller/agency accounts: admins first, then sub-accounts under the same group.
  def index
    users = User.includes(:account).order(:account_id, :is_account_admin, :id).to_a
    by_account_id = users.group_by(&:account_id)
    account_ids = by_account_id.keys.compact
    accounts_by_id = Account.where(id: account_ids).includes(subscription: :plan).index_by(&:id)

    ordered_keys = sort_account_keys(by_account_id.keys, accounts_by_id)
    groups = ordered_keys.filter_map do |account_key|
      members = by_account_id[account_key]
      next if members.blank?

      account = account_key.present? ? accounts_by_id[account_key] : nil
      member_count = members.size
      billing_detail = billing_detail_for(account, member_count)

      main_users, sub_users = partition_main_and_subs(account, members)

      {
        account_id: account_key,
        account_title: account_group_title(account, account_key, members),
        account_kind: account_kind_for_group(account, members),
        billing_summary: billing_detail,
        main_users: main_users.map { |u| user_payload(u, :main, account, billing_detail) },
        sub_accounts: sub_users.map { |u| user_payload(u, :sub, account, billing_detail) }
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
  def sort_account_keys(keys, accounts_by_id)
    ids = keys.compact
    ids.sort_by! do |aid|
      acc = accounts_by_id[aid]
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

  def user_payload(user, slot, account, billing_detail)
    {
      id: user.id,
      username: user.email,
      name: user.name,
      role: role_label(user, slot, account),
      account_type: account_type_label(user, user.account, billing_detail),
      active: user.status.to_i == 1
    }
  end

  # Plan name + amount + billing interval (monthly vs annual), based on stored plan/subscription.
  def billing_detail_for(account, member_count)
    return nil unless account

    sub = account.subscription
    return nil unless sub&.plan

    plan = sub.plan
    bp = sub.billing_period.presence || 'monthly'
    seats = plan.supports_per_user_pricing ? [member_count, 1].max : 1

    cents = if plan.supports_per_user_pricing
              plan.calculate_price_for_users(seats, bp)
            else
              c = plan.price_cents
              bp == 'annual' ? (c * 10).round : c
            end

    interval_word = bp == 'annual' ? 'year' : 'month'
    amount = "$#{format('%.2f', cents / 100.0)}/#{interval_word}"

    status_note =
      case sub.status
      when Subscription::STATUS_TRIALING then ' · trial'
      when Subscription::STATUS_PAST_DUE then ' · past due'
      when Subscription::STATUS_CANCELED then ' · canceled'
      else ''
      end

    "#{plan.name} · #{amount}#{status_note}"
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

  def account_type_label(user, account, billing_detail)
    base =
      if user.super_admin?
        'Super admin'
      elsif user.respond_to?(:client_portal_only?) && user.client_portal_only?
        'Client portal'
      elsif account&.is_reseller
        'Agency'
      else
        'Personal'
      end

    return base if billing_detail.blank?

    "#{base} · #{billing_detail}"
  end
end
