class Api::V1::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_account_admin!

  # GET /api/v1/account/features
  # Get account features/permissions
  def features
    if current_user.super_admin?
      # Super admins have unlimited features
      features = {
        allow_marketplace: true,
        allow_rss: true,
        allow_integrations: true,
        allow_watermark: true,
        max_users: 999999,
        max_buckets: 999999,
        max_images_per_bucket: 999999
      }
    else
      features = current_user.account&.account_feature || {}
    end
    
    render json: { features: features }
  end

  # PATCH /api/v1/account/features
  # Update account features (resellers only)
  def update_features
    unless current_user.reseller?
      return render json: { error: 'Only resellers can update features' }, status: :forbidden
    end
    
    account_feature = current_user.account.account_feature
    
    if account_feature.update(feature_params)
      render json: {
        features: account_feature,
        message: 'Account features updated successfully'
      }
    else
      render json: {
        errors: account_feature.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def require_account_admin!
    unless current_user.account_admin? || current_user.super_admin?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end

  def feature_params
    params.require(:features).permit(
      :allow_marketplace,
      :allow_rss,
      :allow_integrations,
      :allow_watermark,
      :max_users,
      :max_buckets,
      :max_images_per_bucket
    )
  end
end
