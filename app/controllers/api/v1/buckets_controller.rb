class Api::V1::BucketsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_bucket, only: [:show, :update, :destroy, :page, :randomize, :images, :single_image, :upload_image, :add_image, :videos, :upload_video]
  before_action :set_bucket_for_image_actions, only: [:update_image, :delete_image]
  before_action :set_bucket_image, only: [:update_image, :delete_image]
  
  # Maximum file size limits for ZIP uploads
  MAX_ZIP_SIZE = 50.megabytes
  MAX_FILE_SIZE = 10.megabytes

  # GET /api/v1/buckets
  def index
    # Eager load (cover_image only if migration has been run)
    base_includes = [:bucket_schedules, bucket_images: :image]
    base_includes = [:cover_image] + base_includes if Bucket.column_names.include?('cover_image_id')
    user_buckets = current_user.buckets.user_owned.includes(*base_includes)
    global_buckets = Bucket.global.includes(*base_includes, :user)

    render json: {
      buckets: user_buckets.map { |bucket| bucket_json(bucket) },
      global_buckets: global_buckets.map { |bucket| bucket_json(bucket, include_owner: true) }
    }
  end

  # GET /api/v1/buckets/:id
  def show
    # Allow access to global buckets for all users, or user's own buckets
    unless @bucket.is_global || @bucket.user_id == current_user.id
      return render json: { error: 'Bucket not found' }, status: :not_found
    end
    
    # Eager load for bucket_json cover_image_url (only if migration run)
    load_includes = [:bucket_images => :image]
    load_includes = [:cover_image, bucket_images: :image] if Bucket.column_names.include?('cover_image_id')
    @bucket = Bucket.includes(load_includes).find(@bucket.id)
    # Filter out bucket_images with missing image records (orphaned records)
    bucket_images = @bucket.bucket_images.select { |bi| bi.image.present? }
    
    render json: {
      bucket: bucket_json(@bucket, include_owner: @bucket.is_global),
      bucket_images: bucket_images.map { |bi| bucket_image_json(bi) },
      bucket_videos: @bucket.bucket_videos.includes(:video).select { |bv| bv.video.present? }.map { |bv| bucket_video_json(bv) },
      bucket_schedules: @bucket.bucket_schedules.map { |bs| bucket_schedule_json(bs) }
    }
  end

  # POST /api/v1/buckets
  def create
    @bucket = current_user.buckets.build(bucket_params)
    
    # Only super admins can create global buckets
    if params[:bucket][:is_global] == true || params[:bucket][:is_global] == 'true'
      unless current_user.super_admin?
        return render json: {
          error: 'Only super admins can create global buckets'
        }, status: :forbidden
      end
      @bucket.is_global = true
    end
    
    if @bucket.save
      render json: {
        bucket: bucket_json(@bucket),
        message: 'Bucket created successfully'
      }, status: :created
    else
      render json: {
        errors: @bucket.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/buckets/:id
  def update
    # Only super admins can update global buckets, or users can update their own buckets
    if @bucket.is_global && !current_user.super_admin?
      return render json: { error: 'Only super admins can update global buckets' }, status: :forbidden
    end
    
    unless @bucket.user_id == current_user.id || (@bucket.is_global && current_user.super_admin?)
      return render json: { error: 'Bucket not found' }, status: :not_found
    end
    
    # Only super admins can change is_global status
    update_params = bucket_params
    if params[:bucket][:is_global].present? && !current_user.super_admin?
      update_params = update_params.except(:is_global)
    end
    
    if @bucket.update(update_params)
      render json: {
        bucket: bucket_json(@bucket, include_owner: @bucket.is_global),
        message: 'Bucket updated successfully'
      }
    else
      render json: {
        errors: @bucket.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/buckets/:id
  def destroy
    # Only super admins can delete global buckets, or users can delete their own buckets
    if @bucket.is_global && !current_user.super_admin?
      return render json: { error: 'Only super admins can delete global buckets' }, status: :forbidden
    end
    
    unless @bucket.user_id == current_user.id || (@bucket.is_global && current_user.super_admin?)
      return render json: { error: 'Bucket not found' }, status: :not_found
    end
    
    @bucket.destroy
    render json: { message: 'Bucket deleted successfully' }
  end

  # GET /api/v1/buckets/:id/page/:page_num
  def page
    page_num = params[:page_num].to_i
    row_size = 4
    rows_to_show = 3
    skip = row_size * rows_to_show * (page_num - 1)
    take = row_size * rows_to_show

    @bucket_images = @bucket.bucket_images
                           .includes(:image)
                           .order(:friendly_name)
                           .offset(skip)
                           .limit(take)

    render json: {
      bucket_images: @bucket_images.map { |bi| bucket_image_json(bi) },
      pagination: {
        page: page_num,
        row_size: row_size,
        rows_to_show: rows_to_show,
        total: @bucket.bucket_images.count
      }
    }
  end

  # GET /api/v1/buckets/:id/images
  def images
    # Filter out bucket_images with missing image records (orphaned records)
    # Use left_joins to include images, then filter out nil images
    @bucket_images = @bucket.bucket_images
                          .includes(:image)
                          .where.not(image_id: nil)
                          .order(:friendly_name)
                          .to_a
                          .select { |bi| bi.image.present? }
    
    render json: {
      bucket_images: @bucket_images.map { |bi| bucket_image_json(bi) }
    }
  end

  # GET /api/v1/buckets/:id/videos
  def videos
    @bucket_videos = @bucket.bucket_videos.includes(:video).order(:friendly_name)
    render json: {
      bucket_videos: @bucket_videos.map { |bv| bucket_video_json(bv) }
    }
  end

  # POST /api/v1/buckets/:id/videos/upload
  # Uploads a video to a bucket
  # Creates both a Video record and a BucketVideo record
  def upload_video
    if params[:file].blank?
      return render json: { error: 'No file provided' }, status: :bad_request
    end

    uploaded_file = params[:file]
    
    # Validate file type
    allowed_types = ['video/mp4', 'video/mpeg', 'video/quicktime', 'video/x-msvideo', 'video/webm']
    unless allowed_types.include?(uploaded_file.content_type) || ['.mp4', '.mov', '.avi', '.webm'].include?(File.extname(uploaded_file.original_filename).downcase)
      return render json: { error: 'Invalid video file type. Supported formats: MP4, MOV, AVI, WEBM' }, status: :bad_request
    end
    
    # Generate a unique filename to prevent collisions
    file_extension = File.extname(uploaded_file.original_filename)
    unique_filename = "#{SecureRandom.uuid}#{file_extension}"
    
    # Extract friendly name from original filename (without extension)
    friendly_name = File.basename(uploaded_file.original_filename, file_extension)
    
    begin
      # Store file based on environment
      if Rails.env.production?
        # Support both naming conventions
        spaces_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
        if spaces_key.present?
          # Production: Upload to DigitalOcean Spaces
          relative_path = upload_to_spaces(uploaded_file, unique_filename, 'videos')
        else
          # Production without DigitalOcean: Use a placeholder URL
          Rails.logger.warn "DigitalOcean Spaces not configured, using placeholder video"
          relative_path = "placeholder/videos/#{unique_filename}"
        end
      else
        # Development/Test: Store locally
        relative_path = upload_locally(uploaded_file, unique_filename, 'videos')
      end
      
      # Create Video record
      video = Video.new(
        user: current_user,
        file_path: relative_path,
        friendly_name: friendly_name,
        status: Video::STATUS_PROCESSED
      )
      
      if video.save
        # Create BucketVideo record linking the video to this bucket
        bucket_video = @bucket.bucket_videos.build(
          video_id: video.id,
          friendly_name: friendly_name,
          description: params[:description] || '',
          twitter_description: params[:twitter_description] || '',
          post_to: params[:post_to] || 0,
          use_watermark: params[:use_watermark] == '1' || params[:use_watermark] == true
        )
        
        if bucket_video.save
          render json: {
            bucket_video: bucket_video_json(bucket_video),
            message: 'Video uploaded successfully'
          }, status: :created
        else
          # If bucket_video fails to save, clean up the video
          video.destroy
          render json: {
            errors: bucket_video.errors.full_messages
          }, status: :unprocessable_entity
        end
      else
        render json: {
          errors: video.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Video upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Video upload failed: #{e.message}" }, status: :internal_server_error
    end
  end

  # GET /api/v1/buckets/:id/images/:image_id
  def single_image
    @bucket_image = @bucket.bucket_images.find(params[:image_id])
    render json: {
      bucket_image: bucket_image_json(@bucket_image)
    }
  end

  # POST /api/v1/buckets/:id/images/upload
  # Uploads an image or ZIP file of images to a bucket
  # Creates both an Image record and a BucketImage record for each image
  def upload_image
    if params[:file].blank?
      return render json: { error: 'No file provided' }, status: :bad_request
    end

    uploaded_file = params[:file]
    file_extension = File.extname(uploaded_file.original_filename).downcase
    
    # Check if it's a ZIP file
    if file_extension == '.zip'
      upload_zip_file(uploaded_file)
    else
      upload_single_image(uploaded_file)
    end
  end
  
  # Upload a single image file
  def upload_single_image(uploaded_file)
    # Generate a unique filename to prevent collisions
    file_extension = File.extname(uploaded_file.original_filename)
    unique_filename = "#{SecureRandom.uuid}#{file_extension}"
    
    # Extract friendly name from original filename (without extension)
    friendly_name = File.basename(uploaded_file.original_filename, file_extension)
    
    begin
      # Store file based on environment
      if Rails.env.production?
        # Support both naming conventions
        spaces_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
        if spaces_key.present?
          # Production: Upload to DigitalOcean Spaces
          relative_path = upload_to_spaces(uploaded_file, unique_filename)
        else
          # Production without DigitalOcean: Use a placeholder URL
          Rails.logger.warn "DigitalOcean Spaces not configured, using placeholder image"
          relative_path = "placeholder/#{unique_filename}"
        end
      else
        # Development/Test: Store locally
        relative_path = upload_locally(uploaded_file, unique_filename)
      end
      
      # Create Image record
      image = Image.new(
        file_path: relative_path,
        friendly_name: friendly_name
      )
      
      if image.save
        # Create BucketImage record linking the image to this bucket
        bucket_image = @bucket.bucket_images.build(
          image_id: image.id,
          friendly_name: friendly_name
        )
        
        if bucket_image.save
          render json: {
            bucket_image: bucket_image_json(bucket_image),
            message: 'Image uploaded successfully'
          }, status: :created
        else
          # If bucket_image fails to save, clean up the image
          image.destroy
          render json: {
            errors: bucket_image.errors.full_messages
          }, status: :unprocessable_entity
        end
      else
        render json: {
          errors: image.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Upload failed: #{e.message}" }, status: :internal_server_error
    end
  end
  
  # Upload and extract images from a ZIP file
  def upload_zip_file(uploaded_file)
    require 'zip'
    
    # Validate ZIP file size
    if uploaded_file.size > MAX_ZIP_SIZE
      return render json: { 
        error: "ZIP file too large. Maximum size is #{MAX_ZIP_SIZE / 1.megabyte}MB" 
      }, status: :bad_request
    end
    
    uploaded_images = []
    errors = []
    temp_dir = nil
    zip_temp_path = nil
    
    begin
      # Save uploaded file to temp location for ZIP processing
      zip_temp_path = Tempfile.new(['zip_upload', '.zip'])
      zip_temp_path.binmode
      zip_temp_path.write(uploaded_file.read)
      zip_temp_path.rewind
      
      # Create temporary directory for extraction
      temp_dir = Dir.mktmpdir('zip_upload_')
      
      # Extract ZIP file
      Zip::File.open(zip_temp_path.path) do |zip_file|
        zip_file.each do |entry|
          # Skip directories and hidden files
          next if entry.name.end_with?('/') || File.basename(entry.name).start_with?('.')
          
          # Validate file extension (only images)
          file_ext = File.extname(entry.name).downcase
          unless ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].include?(file_ext)
            errors << "Skipped non-image file: #{entry.name}"
            next
          end
          
          # Validate file size
          if entry.size > MAX_FILE_SIZE
            errors << "File too large (skipped): #{entry.name} (#{(entry.size / 1.megabyte).round(2)}MB)"
            next
          end
          
          # Extract file to temp directory
          extracted_path = File.join(temp_dir, File.basename(entry.name))
          entry.extract(extracted_path) { true } # Overwrite if exists
          
          # Upload each image
          begin
            # Read file content into memory so it can be read multiple times
            file_content = File.binread(extracted_path)
            
            # Create an object that mimics ActionDispatch::Http::UploadedFile interface
            mock_uploaded_file = Object.new
            mock_uploaded_file.define_singleton_method(:original_filename) { File.basename(entry.name) }
            mock_uploaded_file.define_singleton_method(:content_type) { "image/#{file_ext[1..-1]}" }
            mock_uploaded_file.define_singleton_method(:size) { file_content.bytesize }
            mock_uploaded_file.define_singleton_method(:read) { file_content.dup }
            mock_uploaded_file.define_singleton_method(:path) { extracted_path }
            
            # Upload this image using the single image upload logic
            result = process_single_image_from_zip(mock_uploaded_file, File.basename(entry.name, file_ext))
            uploaded_images << result if result
          rescue => e
            errors << "Failed to upload #{entry.name}: #{e.message}"
            Rails.logger.error "Failed to upload #{entry.name}: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          end
        end
      end
      
      if uploaded_images.empty?
        return render json: { 
          error: 'No valid images found in ZIP file',
          errors: errors
        }, status: :bad_request
      end
      
      render json: {
        bucket_images: uploaded_images.map { |bi| bucket_image_json(bi) },
        uploaded_count: uploaded_images.length,
        errors: errors.presence,
        message: "Successfully uploaded #{uploaded_images.length} image#{'s' if uploaded_images.length != 1} from ZIP file"
      }, status: :created
      
    rescue Zip::Error => e
      Rails.logger.error "ZIP extraction error: #{e.message}"
      render json: { error: "Invalid ZIP file: #{e.message}" }, status: :bad_request
    rescue => e
      Rails.logger.error "ZIP upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "ZIP upload failed: #{e.message}" }, status: :internal_server_error
    ensure
      # Clean up temp files
      zip_temp_path&.close
      zip_temp_path&.unlink
      if temp_dir && Dir.exist?(temp_dir)
        FileUtils.rm_rf(temp_dir)
      end
    end
  end
  
  # Process a single image file extracted from ZIP
  def process_single_image_from_zip(extracted_file, friendly_name)
    file_extension = File.extname(extracted_file.original_filename)
    unique_filename = "#{SecureRandom.uuid}#{file_extension}"
    
    # Store file based on environment
    if Rails.env.production?
      spaces_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
      if spaces_key.present?
        relative_path = upload_to_spaces(extracted_file, unique_filename)
      else
        Rails.logger.warn "DigitalOcean Spaces not configured, using placeholder image"
        relative_path = "placeholder/#{unique_filename}"
      end
    else
      relative_path = upload_locally(extracted_file, unique_filename)
    end
    
    # Create Image record
    image = Image.create!(
      file_path: relative_path,
      friendly_name: friendly_name
    )
    
    # Create BucketImage record
    @bucket.bucket_images.create!(
      image_id: image.id,
      friendly_name: friendly_name
    )
  end
  
  # Upload file to DigitalOcean Spaces
  def upload_to_spaces(uploaded_file, unique_filename, folder = 'images')
    require 'aws-sdk-s3'
    
    # Support both naming conventions
    access_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
    secret_key = ENV['DO_SPACES_SECRET'] || ENV['DIGITAL_OCEAN_SPACES_SECRET']
    endpoint = ENV['DO_SPACES_ENDPOINT'] || ENV['DIGITAL_OCEAN_SPACES_ENDPOINT'] || 'https://sfo2.digitaloceanspaces.com'
    region = ENV['DO_SPACES_REGION'] || ENV['DIGITAL_OCEAN_SPACES_REGION'] || 'sfo2'
    bucket_name = ENV['DO_SPACES_BUCKET'] || ENV['DIGITAL_OCEAN_SPACES_NAME']
    
    # Configure AWS SDK for DigitalOcean Spaces
    s3_client = Aws::S3::Client.new(
      access_key_id: access_key,
      secret_access_key: secret_key,
      endpoint: endpoint,
      region: region,
      force_path_style: false
    )
    key = "#{Rails.env}/#{folder}/#{unique_filename}"
    
    # Upload the file
    s3_client.put_object(
      bucket: bucket_name,
      key: key,
      body: uploaded_file.read,
      acl: 'public-read'
    )
    
    # Return the path for DigitalOcean Spaces URL
    key
  end
  
  # Upload file locally (development/test)
  def upload_locally(uploaded_file, unique_filename, folder = 'images')
    # Create directory if it doesn't exist
    upload_dir = Rails.root.join('public', 'uploads', Rails.env.to_s, folder)
    FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
    
    # Save the file
    file_path = upload_dir.join(unique_filename)
    File.open(file_path, 'wb') do |file|
      file.write(uploaded_file.read)
    end
    
    # Return relative path for database
    "uploads/#{Rails.env}/#{folder}/#{unique_filename}"
  end

  # POST /api/v1/buckets/:id/images (add existing image by ID)
  def add_image
    image_id = params[:image_id]
    friendly_name = params[:friendly_name]
    
    unless image_id.present?
      return render json: { error: 'image_id is required' }, status: :bad_request
    end
    
    image = Image.find_by(id: image_id)
    unless image
      return render json: { error: 'Image not found' }, status: :not_found
    end
    
    # Create BucketImage record linking the image to this bucket
    bucket_image = @bucket.bucket_images.build(
      image_id: image.id,
      friendly_name: friendly_name || image.friendly_name
    )
    
    if bucket_image.save
      Rails.logger.info "Added image #{image.id} to bucket #{@bucket.id} as bucket_image #{bucket_image.id}"
      render json: {
        bucket_image: bucket_image_json(bucket_image),
        message: 'Image added successfully'
      }, status: :created
    else
      Rails.logger.error "Failed to add image to bucket: #{bucket_image.errors.full_messages.join(', ')}"
      render json: {
        errors: bucket_image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/buckets/:id/images/:image_id
  def update_image
    # Check if a new file is being uploaded (for image editing)
    if params[:file].present?
      uploaded_file = params[:file]
      
      # Generate a unique filename
      # Get extension from filename, or try content type, or default to .jpg
      file_extension = File.extname(uploaded_file.original_filename)
      if file_extension.blank?
        # Try to detect from content type
        content_type = uploaded_file.content_type
        file_extension = case content_type
                        when 'image/png' then '.png'
                        when 'image/gif' then '.gif'
                        when 'image/webp' then '.webp'
                        else '.jpg' # Default to .jpg for JPEG images
                        end
        Rails.logger.info "Image update: No extension in filename '#{uploaded_file.original_filename}', using #{file_extension} based on content type #{content_type}"
      end
      unique_filename = "#{SecureRandom.uuid}#{file_extension}"
      
      begin
        # Store file based on environment (same logic as upload_single_image)
        if Rails.env.production?
          spaces_key = ENV['DO_SPACES_KEY'] || ENV['DIGITAL_OCEAN_SPACES_KEY']
          if spaces_key.present?
            # Production: Upload to DigitalOcean Spaces
            relative_path = upload_to_spaces(uploaded_file, unique_filename)
          else
            # Production without DigitalOcean: Use a placeholder URL
            Rails.logger.warn "DigitalOcean Spaces not configured, using placeholder image"
            relative_path = "placeholder/#{unique_filename}"
          end
        else
          # Development/Test: Store locally
          relative_path = upload_locally(uploaded_file, unique_filename)
        end
        
        # Delete old file if it exists (only for local files)
        if Rails.env.development? || Rails.env.test?
          old_file_path = Rails.root.join('public', @bucket_image.image.file_path)
          File.delete(old_file_path) if File.exist?(old_file_path)
        end
        # Note: For Spaces, we don't delete old files to avoid complexity
        
        # Update the image record with new file path
        @bucket_image.image.update(file_path: relative_path)
        
        render json: {
          bucket_image: bucket_image_json(@bucket_image),
          message: 'Image updated successfully'
        }
      rescue => e
        Rails.logger.error "Image update error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: "Image update failed: #{e.message}" }, status: :internal_server_error
      end
    elsif bucket_image_params.present?
      # Update metadata only
      if @bucket_image.update(bucket_image_params)
        render json: {
          bucket_image: bucket_image_json(@bucket_image),
          message: 'Image updated successfully'
        }
      else
        render json: {
          errors: @bucket_image.errors.full_messages
        }, status: :unprocessable_entity
      end
    else
      render json: { error: 'No data provided' }, status: :bad_request
    end
  end

  # DELETE /api/v1/buckets/:id/images/:image_id
  def delete_image
    # Delete associated schedules first
    @bucket_image.bucket_schedules.destroy_all
    @bucket_image.destroy
    render json: { message: 'Image deleted successfully' }
  end

  # GET /api/v1/buckets/:id/randomize
  def randomize
    @bucket_images = @bucket.bucket_images.to_a
    return render json: { error: 'No images found in the bucket' }, status: :unprocessable_entity if @bucket_images.empty?

    # Shuffle friendly names
    friendly_names = @bucket_images.map(&:friendly_name).shuffle
    
    @bucket_images.each_with_index do |bucket_image, index|
      bucket_image.update!(friendly_name: friendly_names[index])
    end

    render json: { message: 'Bucket successfully randomized' }
  end

  # GET /api/v1/buckets/for_scheduling
  def for_scheduling
    ignore_post_now = params[:ignore_post_now] == 'true'
    
    # Get user's own buckets
    user_buckets = current_user.buckets.user_owned
    if ignore_post_now
      user_buckets = user_buckets.where(post_once_bucket: false)
    end
    
    # Get global buckets (available to all users)
    global_buckets = Bucket.global
    if ignore_post_now
      global_buckets = global_buckets.where(post_once_bucket: false)
    end

    render json: {
      buckets: user_buckets.map { |bucket| bucket_json(bucket) },
      global_buckets: global_buckets.map { |bucket| bucket_json(bucket, include_owner: true) }
    }
  end

  private

  def set_bucket
    # Allow access to global buckets or user's own buckets
    @bucket = Bucket.find_by(id: params[:id])
    
    unless @bucket && (@bucket.is_global || @bucket.user_id == current_user.id)
      render json: { error: 'Bucket not found' }, status: :not_found
    end
  end

  def set_bucket_for_image_actions
    # Only allow modifying images in user's own buckets or global buckets (if super admin)
    @bucket = Bucket.find_by(id: params[:id])
    
    unless @bucket
      return render json: { error: 'Bucket not found' }, status: :not_found
    end
    
    # Users can only modify their own buckets, super admins can modify global buckets
    if @bucket.is_global
      unless current_user.super_admin?
        return render json: { error: 'Only super admins can modify global buckets' }, status: :forbidden
      end
    elsif @bucket.user_id != current_user.id
      return render json: { error: 'Bucket not found' }, status: :not_found
    end
  end

  def set_bucket_image
    @bucket_image = @bucket.bucket_images.find(params[:image_id])
  end

  def bucket_params
    # Only super admins can set is_global
    permitted = [:name, :description, :use_watermark, :post_once_bucket, :cover_image_id]
    permitted << :is_global if current_user&.super_admin?
    params.require(:bucket).permit(*permitted)
  end

  def bucket_image_params
    params.require(:bucket_image).permit(:description, :twitter_description, :use_watermark, :force_send_date, :repeat, :post_to)
  end

  def bucket_json(bucket, include_owner: false)
    json = {
      id: bucket.id,
      user_id: bucket.user_id,
      name: bucket.name,
      description: bucket.description,
      use_watermark: bucket.use_watermark,
      post_once_bucket: bucket.post_once_bucket,
      is_global: bucket.is_global || false,
      created_at: bucket.created_at,
      updated_at: bucket.updated_at,
      images_count: bucket.bucket_images.count,
      schedules_count: bucket.bucket_schedules.count
    }
    # Cover image: use column if present, else compute from first bucket_image (works even if schema cache is stale)
    if Bucket.column_names.include?('cover_image_id')
      json[:cover_image_url] = bucket.cover_image_url
      json[:cover_image_id] = bucket.cover_image_id
    end
    # Fallback: if no cover_image_url yet, use first image from preloaded bucket_images so cards always show an image when bucket has images
    if json[:cover_image_url].blank?
      first_bi = bucket.bucket_images.to_a.sort_by(&:id).first
      json[:cover_image_url] = first_bi&.image&.get_source_url if first_bi&.image
    end

    # Include owner info for global buckets
    if include_owner && bucket.is_global && bucket.user
      json[:owner] = {
        id: bucket.user.id,
        name: bucket.user.name,
        email: bucket.user.email
      }
    end
    
    json
  end

  def bucket_image_json(bucket_image)
    # Handle missing image gracefully
    image_data = if bucket_image.image.present?
      {
        id: bucket_image.image.id,
        file_path: bucket_image.image.file_path,
        source_url: bucket_image.image.get_source_url
      }
    else
      {
        id: nil,
        file_path: nil,
        source_url: nil
      }
    end
    
    {
      id: bucket_image.id,
      friendly_name: bucket_image.friendly_name,
      description: bucket_image.description,
      twitter_description: bucket_image.twitter_description,
      force_send_date: bucket_image.force_send_date,
      repeat: bucket_image.repeat,
      post_to: bucket_image.post_to,
      use_watermark: bucket_image.use_watermark,
      image: image_data,
      created_at: bucket_image.created_at,
      updated_at: bucket_image.updated_at
    }
  end

  def bucket_video_json(bucket_video)
    {
      id: bucket_video.id,
      friendly_name: bucket_video.friendly_name,
      description: bucket_video.description,
      twitter_description: bucket_video.twitter_description,
      post_to: bucket_video.post_to,
      use_watermark: bucket_video.use_watermark,
      video: {
        id: bucket_video.video.id,
        file_path: bucket_video.video.file_path,
        source_url: bucket_video.video.get_source_url,
        friendly_name: bucket_video.video.friendly_name,
        status: bucket_video.video.status
      },
      created_at: bucket_video.created_at,
      updated_at: bucket_video.updated_at
    }
  end

  def bucket_schedule_json(bucket_schedule)
    {
      id: bucket_schedule.id,
      schedule: bucket_schedule.schedule,
      schedule_type: bucket_schedule.schedule_type,
      post_to: bucket_schedule.post_to,
      description: bucket_schedule.description,
      twitter_description: bucket_schedule.twitter_description,
      times_sent: bucket_schedule.times_sent,
      skip_image: bucket_schedule.skip_image,
      bucket_image_id: bucket_schedule.bucket_image_id,
      created_at: bucket_schedule.created_at,
      updated_at: bucket_schedule.updated_at
    }
  end
end
