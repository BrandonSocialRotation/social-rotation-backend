require 'rails_helper'

RSpec.describe RssPost, type: :model do
  describe 'associations' do
    it { should belong_to(:rss_feed) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:rss_feed_id) }
  end

  describe 'scopes' do
    let!(:viewed_post) { create(:rss_post, is_viewed: true) }
    let!(:unviewed_post) { create(:rss_post, is_viewed: false) }

    it 'returns viewed posts' do
      expect(RssPost.viewed).to include(viewed_post)
      expect(RssPost.viewed).not_to include(unviewed_post)
    end

    it 'returns unviewed posts' do
      expect(RssPost.unviewed).to include(unviewed_post)
      expect(RssPost.unviewed).not_to include(viewed_post)
    end

    it 'returns recent posts' do
      old_post = create(:rss_post, published_at: 2.days.ago)
      recent_post = create(:rss_post, published_at: 1.hour.ago)
      
      expect(RssPost.recent).to include(recent_post)
      expect(RssPost.recent).not_to include(old_post)
    end
  end

  describe '#has_image?' do
    it 'returns true when image_url is present' do
      post = create(:rss_post, image_url: "https://example.com/image.jpg")
      expect(post.has_image?).to be true
    end

    it 'returns false when image_url is nil' do
      post = create(:rss_post, image_url: nil)
      expect(post.has_image?).to be false
    end
  end

  describe '#mark_as_viewed!' do
    it 'marks post as viewed' do
      post = create(:rss_post, is_viewed: false)
      post.mark_as_viewed!
      
      expect(post.is_viewed).to be true
    end
  end

  describe '#short_title' do
    it 'returns full title when less than max length' do
      post = create(:rss_post, title: "Short title")
      expect(post.short_title(50)).to eq("Short title")
    end

    it 'truncates long titles' do
      post = create(:rss_post, title: "This is a very long title that needs to be truncated")
      expect(post.short_title(20)).to eq("This is a very lo...")
    end
  end

  describe '#short_description' do
    it 'returns full description when less than max length' do
      post = create(:rss_post, description: "Short desc")
      expect(post.short_description(50)).to eq("Short desc")
    end

    it 'truncates long descriptions' do
      post = create(:rss_post, description: "This is a very long description that needs to be truncated")
      expect(post.short_description(20)).to eq("This is a very lo...")
    end

    it 'returns empty string when description is blank' do
      post = create(:rss_post, description: nil)
      expect(post.short_description).to eq('')
    end

    it 'uses default limit of 150' do
      long_desc = 'A' * 200
      post = create(:rss_post, description: long_desc)
      result = post.short_description
      expect(result.length).to eq(150)
      expect(result).to end_with('...')
    end
  end

  describe '#short_title' do
    it 'returns empty string when title is blank' do
      post = create(:rss_post, title: nil)
      expect(post.short_title).to eq('')
    end

    it 'uses default limit of 100' do
      long_title = 'A' * 150
      post = create(:rss_post, title: long_title)
      result = post.short_title
      expect(result.length).to eq(100)
      expect(result).to end_with('...')
    end
  end

  describe '#display_image_url' do
    it 'returns image_url when image exists' do
      post = create(:rss_post, image_url: 'https://example.com/image.jpg')
      expect(post.display_image_url).to eq('https://example.com/image.jpg')
    end

    it 'returns placeholder when no image' do
      post = create(:rss_post, image_url: nil)
      expect(post.display_image_url).to eq('/img/no_image_available.gif')
    end

    it 'returns placeholder when image_url is empty string' do
      post = create(:rss_post, image_url: '')
      expect(post.display_image_url).to eq('/img/no_image_available.gif')
    end
  end

  describe '#formatted_published_at' do
    it 'formats published date correctly' do
      time = Time.parse('2024-12-17 14:30:00')
      post = create(:rss_post, published_at: time)
      formatted = post.formatted_published_at
      expect(formatted).to include('December')
      expect(formatted).to include('17')
      expect(formatted).to include('2024')
      expect(formatted).to include('02:30 PM')
    end
  end

  describe '#relative_published_at' do
    it 'returns relative time string' do
      post = create(:rss_post, published_at: 2.hours.ago)
      result = post.relative_published_at
      expect(result).to include('ago')
      expect(result).to match(/\d+ (minutes?|hours?|days?|months?) ago/)
    end

    it 'handles very recent posts' do
      post = create(:rss_post, published_at: 30.seconds.ago)
      result = post.relative_published_at
      expect(result).to include('less than a minute ago')
    end

    it 'handles posts from minutes ago' do
      post = create(:rss_post, published_at: 5.minutes.ago)
      result = post.relative_published_at
      expect(result).to include('minutes ago')
    end

    it 'handles posts from hours ago' do
      post = create(:rss_post, published_at: 3.hours.ago)
      result = post.relative_published_at
      expect(result).to include('hours ago')
    end

    it 'handles posts from days ago' do
      post = create(:rss_post, published_at: 5.days.ago)
      result = post.relative_published_at
      expect(result).to include('days ago')
    end

    it 'handles posts from months ago' do
      post = create(:rss_post, published_at: 2.months.ago)
      result = post.relative_published_at
      expect(result).to include('months ago')
    end
  end

  describe '#recent?' do
    it 'returns true for posts within last 7 days' do
      post = create(:rss_post, published_at: 3.days.ago)
      expect(post.recent?).to be true
    end

    it 'returns false for posts older than 7 days' do
      post = create(:rss_post, published_at: 8.days.ago)
      expect(post.recent?).to be false
    end

    it 'returns false for posts exactly 7 days ago' do
      post = create(:rss_post, published_at: 7.days.ago)
      expect(post.recent?).to be false
    end
  end

  describe '#social_media_content' do
    it 'combines title and description' do
      post = create(:rss_post, title: 'Test Title', description: 'Test Description')
      expect(post.social_media_content).to eq('Test Title - Test Description')
    end

    it 'uses short description in content' do
      long_desc = 'A' * 300
      post = create(:rss_post, title: 'Title', description: long_desc)
      content = post.social_media_content
      expect(content).to start_with('Title -')
      expect(content).to include('...')
      # Should be truncated to 200 chars for description
      expect(content.length).to be < 350
    end

    it 'returns only title when description is blank' do
      post = create(:rss_post, title: 'Test Title', description: nil)
      expect(post.social_media_content).to eq('Test Title')
    end

    it 'returns only description when title is blank' do
      post = create(:rss_post, title: nil, description: 'Test Description')
      expect(post.social_media_content).to eq('Test Description')
    end

    it 'returns empty string when both are blank' do
      post = create(:rss_post, title: nil, description: nil)
      expect(post.social_media_content).to eq('')
    end
  end

  describe 'scope :with_images' do
    it 'returns posts with image_url' do
      post_with_image = create(:rss_post, image_url: 'https://example.com/image.jpg')
      post_without_image = create(:rss_post, image_url: nil)
      
      expect(RssPost.with_images).to include(post_with_image)
      expect(RssPost.with_images).not_to include(post_without_image)
    end

    it 'excludes posts with empty string image_url' do
      post_with_empty = create(:rss_post, image_url: '')
      post_with_image = create(:rss_post, image_url: 'https://example.com/image.jpg')
      
      expect(RssPost.with_images).not_to include(post_with_empty)
      expect(RssPost.with_images).to include(post_with_image)
    end
  end
end

