class Api::V1::ScheduleItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_bucket_schedule
  before_action :set_schedule_item, only: [:update, :destroy]

  # POST /api/v1/bucket_schedules/:bucket_schedule_id/schedule_items
  def create
    require_active_subscription_for_action!
    
    @schedule_item = @bucket_schedule.schedule_items.build(schedule_item_params)
    @schedule_item.position = @bucket_schedule.schedule_items.count
    
    if @schedule_item.save
      render json: {
        schedule_item: schedule_item_json(@schedule_item),
        message: 'Schedule item created successfully'
      }, status: :created
    else
      render json: {
        errors: @schedule_item.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/bucket_schedules/:bucket_schedule_id/schedule_items/:id
  def update
    require_active_subscription_for_action!
    
    if @schedule_item.update(schedule_item_params)
      render json: {
        schedule_item: schedule_item_json(@schedule_item),
        message: 'Schedule item updated successfully'
      }
    else
      render json: {
        errors: @schedule_item.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/bucket_schedules/:bucket_schedule_id/schedule_items/:id
  def destroy
    @schedule_item.destroy
    render json: { message: 'Schedule item deleted successfully' }
  end

  private

  def set_bucket_schedule
    @bucket_schedule = current_user.bucket_schedules.find(params[:bucket_schedule_id])
  end

  def set_schedule_item
    @schedule_item = @bucket_schedule.schedule_items.find(params[:id])
  end

  def schedule_item_params
    params.require(:schedule_item).permit(
      :bucket_image_id, :schedule, :description, :twitter_description, :position
    )
  end

  def schedule_item_json(item)
    {
      id: item.id,
      bucket_image_id: item.bucket_image_id,
      schedule: item.schedule,
      description: item.description,
      twitter_description: item.twitter_description,
      position: item.position,
      bucket_image: item.bucket_image ? {
        id: item.bucket_image.id,
        friendly_name: item.bucket_image.friendly_name
      } : nil,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end
end
