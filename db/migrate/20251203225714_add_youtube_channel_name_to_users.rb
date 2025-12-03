class AddYoutubeChannelNameToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :youtube_channel_name, :string
  end
end
