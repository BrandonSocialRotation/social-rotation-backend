# WatermarkService
# Applies user's watermark logo to images before posting to social media
class WatermarkService
  def initialize(user)
    @user = user
  end
  
  # Apply watermark to an image file
  # @param image_path [String] Local path to the image file
  # @param use_watermark [Boolean] Whether to apply watermark (from bucket_image or bucket setting)
  # @return [String] Path to watermarked image (temp file if original was modified)
  def apply_watermark(image_path, use_watermark: true)
    return image_path unless use_watermark
    return image_path unless @user.watermark_logo.present?
    
    # Get watermark logo path
    watermark_path = get_watermark_path
    return image_path unless watermark_path && File.exist?(watermark_path)
    
    begin
      require 'mini_magick'
      
      # Load the main image
      main_image = MiniMagick::Image.open(image_path)
      
      # Load the watermark
      watermark = MiniMagick::Image.open(watermark_path)
      
      # Calculate watermark size based on user's scale setting
      scale = (@user.watermark_scale || 20).to_f / 100.0 # Default 20% of image width
      watermark_width = (main_image.width * scale).to_i
      watermark.resize "#{watermark_width}x#{watermark_width}>" # Maintain aspect ratio, don't upscale
      
      # Set opacity if specified
      opacity = @user.watermark_opacity || 80
      if opacity < 100
        watermark.alpha('set')
        watermark.channel('a').evaluate(:multiply, opacity / 100.0)
      end
      
      # Calculate position (default: bottom-right corner)
      offset_x = @user.watermark_offset_x || 10
      offset_y = @user.watermark_offset_y || 10
      
      # Composite watermark onto main image
      result = main_image.composite(watermark) do |c|
        c.gravity 'SouthEast' # Bottom-right corner
        c.geometry "+#{offset_x}+#{offset_y}"
      end
      
      # Save to temp file
      temp_file = Tempfile.new(['watermarked', File.extname(image_path)])
      temp_file.binmode
      result.write(temp_file.path)
      temp_file.rewind
      
      # Return temp file path
      temp_file.path
    rescue => e
      Rails.logger.error "Watermark application failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Return original image if watermarking fails
      image_path
    end
  end
  
  private
  
  # Get local path to watermark logo
  # Downloads from DigitalOcean Spaces if needed
  def get_watermark_path
    if Rails.env.production?
      # In production, download from DigitalOcean Spaces to temp file
      watermark_url = @user.get_digital_ocean_watermark_path
      return nil unless watermark_url.present?
      
      begin
        require 'open-uri'
        temp_file = Tempfile.new(['watermark', File.extname(@user.watermark_logo)])
        temp_file.binmode
        temp_file.write(URI.open(watermark_url).read)
        temp_file.rewind
        temp_file.path
      rescue => e
        Rails.logger.error "Failed to download watermark: #{e.message}"
        nil
      end
    else
      # In development, use local file
      @user.get_absolute_watermark_logo_path
    end
  end
end

