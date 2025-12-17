module SocialMedia
  class GoogleService
    API_BASE_URL = 'https://mybusiness.googleapis.com/v4'
    
    def initialize(user)
      @user = user
    end
    
    # Post to Google My Business
    # @param message [String] Post text
    # @param image_url [String] Public URL of the image
    # @return [Hash] Response from Google API
    def post_to_gmb(message, image_url)
      unless @user.google_refresh_token.present?
        raise "User does not have Google My Business connected"
      end
      
      unless @user.location_id.present?
        raise "User does not have a Google My Business location selected"
      end
      
      # Get fresh access token from refresh token
      access_token = get_access_token
      
      # Create local post
      url = "#{API_BASE_URL}/#{@user.location_id}/localPosts"
      headers = {
        'Authorization' => "Bearer #{access_token}",
        'Content-Type' => 'application/json'
      }
      
      body = {
        languageCode: 'en-US',
        summary: message,
        media: [
          {
            mediaFormat: 'PHOTO',
            sourceUrl: image_url,
            description: message
          }
        ]
      }
      
      response = HTTParty.post(url, headers: headers, body: body.to_json)
      JSON.parse(response.body)
    end
    
    private
    
    # Get access token from refresh token
    # @return [String] Access token
    def get_access_token
      url = 'https://oauth2.googleapis.com/token'
      
      params = {
        client_id: ENV['GOOGLE_CLIENT_ID'],
        client_secret: ENV['GOOGLE_CLIENT_SECRET'],
        refresh_token: @user.google_refresh_token,
        grant_type: 'refresh_token'
      }
      
      response = HTTParty.post(url, body: params)
      data = JSON.parse(response.body)
      
      if data['access_token']
        data['access_token']
      else
        raise "Failed to refresh Google access token: #{data['error_description']}"
      end
    end
  end
end
