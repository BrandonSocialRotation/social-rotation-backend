class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    render json: { message: 'Social Rotation API', version: '1.0', status: 'online' }
  end
end
