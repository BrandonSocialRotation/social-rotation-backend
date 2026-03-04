module SocialMedia
  class PinterestService
    API_BASE = 'https://api.pinterest.com/v5'
    TITLE_MAX = 100
    DESCRIPTION_MAX = 500

    def initialize(user)
      @user = user
    end

    # Create a pin on a board.
    # @param title [String] Pin title (max 100 chars)
    # @param description [String] Pin description (max 500 chars)
    # @param image_url [String] Public URL of the image (must be accessible by Pinterest)
    # @param link [String] Destination URL when users click the pin (optional, defaults to image_url)
    # @param board_id [String] Pinterest board ID (optional; if nil, uses first board)
    # @return [Hash] API response with pin data
    def create_pin(title, description, image_url, link: nil, board_id: nil)
      unless @user.respond_to?(:pinterest_access_token) && @user.pinterest_access_token.present?
        raise "User does not have Pinterest connected"
      end

      board_id ||= first_board_id
      raise "No Pinterest board found. Please create a board on Pinterest or set one in the schedule." unless board_id

      title = title.to_s[0...TITLE_MAX]
      description = description.to_s[0...DESCRIPTION_MAX]
      link = link.presence || image_url

      payload = {
        board_id: board_id,
        title: title,
        description: description,
        link: link,
        media_source: {
          source_type: 'image_url',
          url: image_url
        }
      }

      response = HTTParty.post(
        "#{API_BASE}/pins",
        body: payload.to_json,
        headers: {
          'Authorization' => "Bearer #{@user.pinterest_access_token}",
          'Content-Type' => 'application/json'
        },
        timeout: 30
      )

      Rails.logger.info "Pinterest create pin response: #{response.code} #{response.body[0..300]}"

      unless response.success?
        error_msg = response.body.presence || "HTTP #{response.code}"
        Rails.logger.error "Pinterest create pin failed: #{error_msg}"
        raise "Failed to create Pinterest pin: #{error_msg}"
      end

      JSON.parse(response.body)
    end

    # Get the user's boards (for board picker or default board).
    # @return [Array<Hash>] List of boards
    def list_boards
      unless @user.respond_to?(:pinterest_access_token) && @user.pinterest_access_token.present?
        return []
      end

      response = HTTParty.get(
        "#{API_BASE}/boards",
        query: { page_size: 100 },
        headers: { 'Authorization' => "Bearer #{@user.pinterest_access_token}" },
        timeout: 10
      )
      return [] unless response.success?

      data = JSON.parse(response.body)
      items = data['items'] || data['boards'] || []
      items.is_a?(Array) ? items : []
    rescue => e
      Rails.logger.warn "Pinterest list boards error: #{e.message}"
      []
    end

    private

    def first_board_id
      boards = list_boards
      return nil if boards.empty?
      board = boards.first
      board['id'] || board['board_id']
    end
  end
end
