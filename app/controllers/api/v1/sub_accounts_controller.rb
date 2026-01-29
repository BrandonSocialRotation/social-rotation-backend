class Api::V1::SubAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_reseller!, except: [:switch]
  before_action :set_sub_account, only: [:show, :update, :destroy]

  # GET /api/v1/sub_accounts
  # List all sub-accounts for the current reseller
  def index
    # For super admins, show all sub-accounts they created (account_id = 0 or their agency account)
    if current_user.super_admin?
      # Super admins can see sub-accounts with account_id = 0 (created when they were super admin)
      # OR sub-accounts in their agency account (if they converted to agency)
      sub_accounts = User.where(account_id: current_user.account_id || 0)
                        .where.not(is_account_admin: true)
                        .where.not(id: current_user.id)
    else
      # Regular resellers see sub-accounts in their account
      sub_accounts = current_user.account_users.where.not(is_account_admin: true)
    end
    
    render json: {
      sub_accounts: sub_accounts.map { |user| sub_account_json(user) }
    }
  end

  # POST /api/v1/sub_accounts
  # Create a new sub-account under the current reseller
  def create
    # For super admins, skip account limit check (they can add unlimited users)
    unless current_user.super_admin?
      # Check if reseller can add more users
      unless current_user.account&.can_add_user?
        return render json: { 
          error: 'Maximum users reached for your account' 
        }, status: :forbidden
      end
    end
    
    sub_account = User.new(sub_account_params)
    # For super admins, use their account_id (which may be 0 or an agency account)
    # For regular resellers, use their account_id
    sub_account.account_id = current_user.account_id || 0
    sub_account.is_account_admin = false
    sub_account.role = 'sub_account'
    sub_account.status = 1
    
    if sub_account.save
      render json: {
        sub_account: sub_account_json(sub_account),
        message: 'Sub-account created successfully'
      }, status: :created
    else
      render json: {
        errors: sub_account.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/sub_accounts/:id
  # Get details of a specific sub-account
  def show
    render json: {
      sub_account: sub_account_json(@sub_account)
    }
  end

  # PATCH /api/v1/sub_accounts/:id
  # Update a sub-account
  def update
    if @sub_account.update(sub_account_update_params)
      render json: {
        sub_account: sub_account_json(@sub_account),
        message: 'Sub-account updated successfully'
      }
    else
      render json: {
        errors: @sub_account.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/sub_accounts/:id
  # Delete a sub-account
  def destroy
    @sub_account.destroy
    render json: { message: 'Sub-account deleted successfully' }
  end

  # POST /api/v1/sub_accounts/switch/:id
  # Switch context to act as a sub-account (for account admins)
  def switch
    target_user = User.find(params[:id])
    
    # Verify user has permission to switch to this account
    if current_user.super_admin?
      # Super admins can switch to any sub-account they created (same account_id and not an admin)
      unless target_user.account_id == (current_user.account_id || 0) && !target_user.is_account_admin?
        return render json: { error: 'Unauthorized' }, status: :forbidden
      end
    else
      # Regular resellers can only switch to sub-accounts in their account
      unless current_user.account_users.include?(target_user)
        return render json: { error: 'Unauthorized' }, status: :forbidden
      end
    end
    
    # Generate new JWT token for the target user
    token = JsonWebToken.encode(user_id: target_user.id, switched_by: current_user.id)
    
    render json: {
      user: user_json(target_user),
      token: token,
      message: "Switched to #{target_user.name}'s account",
      switched_from: current_user.id
    }
  end

  private

  def require_reseller!
    unless current_user.reseller? || current_user.super_admin?
      render json: { error: 'Only resellers can manage sub-accounts' }, status: :forbidden
    end
  end

  def set_sub_account
    # For super admins, allow accessing sub-accounts they created (account_id = 0 or their agency account)
    if current_user.super_admin?
      @sub_account = User.where(account_id: current_user.account_id || 0)
                        .where.not(is_account_admin: true)
                        .find(params[:id])
    else
      @sub_account = current_user.account_users.find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Sub-account not found' }, status: :not_found
  end

  def sub_account_params
    params.require(:sub_account).permit(:name, :email, :password, :password_confirmation)
  end

  def sub_account_update_params
    params.require(:sub_account).permit(:name, :email, :status)
  end

  def sub_account_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      status: user.status,
      role: user.role,
      created_at: user.created_at,
      buckets_count: user.buckets.count,
      schedules_count: user.bucket_schedules.count
    }
  end
  
  def user_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      account_id: user.account_id,
      is_account_admin: user.is_account_admin,
      role: user.role
    }
  end
end
