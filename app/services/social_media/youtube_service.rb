module SocialMedia
  class YouTubeService
    BASE_URL = 'https://www.googleapis.com/youtube/v3'
    UPLOAD_URL = 'https://www.googleapis.com/upload/youtube/v3/videos'
    
    def initialize(user)
      @user = user
    end
    
    # Post a video to YouTube
    # @param title [String] The video title
    # @param description [String] The video description
    # @param video_path [String] Local path or URL of the video to post
    # @param tags [Array<String>] Optional tags for the video
    # @return [Hash] Response from YouTube API
    def post_video(title, description, video_path, tags = [])
      unless @user.youtube_access_token.present?
        raise "User does not have YouTube connected"
      end
      
      # Get access token (refresh if needed)
      access_token = get_access_token
      
      # Download video if it's a URL
      local_video_path = video_path
      temp_file = nil
      
      if video_path.start_with?('http://') || video_path.start_with?('https://')
        temp_file = download_video_to_temp(video_path)
        local_video_path = temp_file.path
      end
      
      begin
        # Step 1: Initialize resumable upload
        upload_url = initiate_resumable_upload(access_token, title, description, tags)
        
        # Step 2: Upload video in chunks
        upload_video_in_chunks(upload_url, local_video_path, access_token)
      ensure
        # Clean up temp file if we created one
        if temp_file
          temp_file.close
          temp_file.unlink
        end
      end
    end
    
    private
    
    # Download video from URL to a temporary file
    # @param video_url [String] URL of the video
    # @return [Tempfile] Temporary file object
    def download_video_to_temp(video_url)
      require 'open-uri'
      require 'tempfile'
      
      # Determine file extension from URL
      extension = File.extname(URI.parse(video_url).path)
      extension = '.mp4' if extension.empty?
      
      # Create a temporary file
      temp_file = Tempfile.new(['youtube_video', extension])
      temp_file.binmode
      
      begin
        # Download the video
        URI.open(video_url, 'rb') do |remote_file|
          temp_file.write(remote_file.read)
        end
        
        temp_file.rewind
        temp_file
      rescue => e
        temp_file.close
        temp_file.unlink
        Rails.logger.error "Failed to download video from #{video_url}: #{e.message}"
        raise "Failed to download video: #{e.message}"
      end
    end
    
    # Initiate resumable upload and get upload URL
    # @param access_token [String] OAuth access token
    # @param title [String] Video title
    # @param description [String] Video description
    # @param tags [Array<String>] Video tags
    # @return [String] Upload URL for resumable upload
    def initiate_resumable_upload(access_token, title, description, tags = [])
      # Create video metadata
      video_metadata = {
        snippet: {
          title: title,
          description: description,
          tags: tags,
          categoryId: '22' # People & Blogs
        },
        status: {
          privacyStatus: 'public'
        }
      }
      
      # POST to initiate resumable upload
      response = HTTParty.post(
        "#{UPLOAD_URL}?uploadType=resumable&part=snippet,status",
        headers: {
          'Authorization' => "Bearer #{access_token}",
          'Content-Type' => 'application/json',
          'X-Upload-Content-Type' => 'video/*'
        },
        body: video_metadata.to_json
      )
      
      unless response.success?
        Rails.logger.error "YouTube upload initiation failed: #{response.body}"
        raise "Failed to initiate YouTube upload: #{response.body}"
      end
      
      # Extract upload URL from Location header
      upload_url = response.headers['location']
      unless upload_url
        raise "No upload URL returned from YouTube"
      end
      
      upload_url
    end
    
    # Upload video in chunks using resumable upload
    # @param upload_url [String] Resumable upload URL
    # @param video_path [String] Local path to video file
    # @param access_token [String] OAuth access token
    # @return [Hash] Response from YouTube API
    def upload_video_in_chunks(upload_url, video_path, access_token)
      file_size = File.size(video_path)
      chunk_size = 5 * 1024 * 1024 # 5MB chunks
      
      File.open(video_path, 'rb') do |file|
        bytes_uploaded = 0
        
        while bytes_uploaded < file_size
          chunk = file.read(chunk_size)
          break unless chunk
          
          range_end = [bytes_uploaded + chunk.bytesize - 1, file_size - 1].min
          
          response = HTTParty.put(
            upload_url,
            headers: {
              'Authorization' => "Bearer #{access_token}",
              'Content-Type' => 'video/*',
              'Content-Range' => "bytes #{bytes_uploaded}-#{range_end}/#{file_size}"
            },
            body: chunk
          )
          
          if response.code == 308 # Resume Incomplete
            bytes_uploaded = range_end + 1
          elsif response.success?
            # Upload complete
            return JSON.parse(response.body)
          else
            Rails.logger.error "YouTube chunk upload failed: #{response.body}"
            raise "Failed to upload video chunk: #{response.body}"
          end
        end
      end
    end
    
    # Get access token for YouTube API (refresh if needed)
    # @return [String] OAuth access token
    def get_access_token
      # For now, use the stored access token
      # In production, you'd want to check if it's expired and refresh it
      # For simplicity, we'll refresh it every time to ensure it's valid
      if @user.youtube_refresh_token.present?
        refresh_access_token
      elsif @user.youtube_access_token.present?
        @user.youtube_access_token
      else
        raise "No YouTube access token or refresh token available"
      end
    end
    
    # Refresh YouTube access token using refresh token
    # @return [String] New access token
    def refresh_access_token
      client_id = ENV['GOOGLE_CLIENT_ID']
      client_secret = ENV['GOOGLE_CLIENT_SECRET']
      
      token_url = "https://oauth2.googleapis.com/token"
      
      response = HTTParty.post(
        token_url,
        body: {
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: @user.youtube_refresh_token,
          grant_type: 'refresh_token'
        }
      )
      
      data = JSON.parse(response.body)
      
      if data['access_token']
        # Update user's access token
        @user.update(youtube_access_token: data['access_token'])
        data['access_token']
      else
        Rails.logger.error "Failed to refresh YouTube token: #{data}"
        raise "Failed to refresh YouTube access token: #{data['error'] || 'Unknown error'}"
      end
    end
  end
end

