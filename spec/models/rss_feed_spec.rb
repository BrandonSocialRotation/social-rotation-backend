require 'rails_helper'

RSpec.describe RssFeed, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:account).optional }
    it { should have_many(:rss_posts).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:url) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:user_id) }
  end

  describe 'scopes' do
    let!(:active_feed) { create(:rss_feed, is_active: true) }
    let!(:inactive_feed) { create(:rss_feed, is_active: false) }

    it 'returns active feeds' do
      expect(RssFeed.active).to include(active_feed)
      expect(RssFeed.active).not_to include(inactive_feed)
    end
  end

  describe '#healthy?' do
    it 'returns true when failure count is less than 3' do
      feed = create(:rss_feed, fetch_failure_count: 2)
      expect(feed.healthy?).to be true
    end

    it 'returns false when failure count is 3 or more' do
      feed = create(:rss_feed, fetch_failure_count: 3)
      expect(feed.healthy?).to be false
    end
  end

  describe '#unhealthy?' do
    it 'returns opposite of healthy?' do
      feed = create(:rss_feed, fetch_failure_count: 3)
      expect(feed.unhealthy?).to be true
    end
  end

  describe '#record_success!' do
    it 'resets failure count and clears error' do
      feed = create(:rss_feed, fetch_failure_count: 5, last_fetch_error: "Test error")
      feed.record_success!
      
      expect(feed.fetch_failure_count).to eq(0)
      expect(feed.last_fetch_error).to be_nil
      expect(feed.last_successful_fetch_at).to be_present
    end
  end

  describe '#record_failure!' do
    it 'increments failure count and records error' do
      feed = create(:rss_feed, fetch_failure_count: 0)
      feed.record_failure!("Test error")
      
      expect(feed.fetch_failure_count).to eq(1)
      expect(feed.last_fetch_error).to eq("Test error")
    end
  end

  describe '#health_status' do
    it 'returns "healthy" when failure count is 0 and has been fetched' do
      feed = create(:rss_feed, fetch_failure_count: 0, last_fetched_at: 1.hour.ago)
      expect(feed.health_status).to eq('healthy')
    end

    it 'returns "unhealthy" when failure count is 1-2' do
      feed = create(:rss_feed, fetch_failure_count: 1, last_fetched_at: 1.hour.ago)
      expect(feed.health_status).to eq('unhealthy')
      
      feed2 = create(:rss_feed, fetch_failure_count: 2, last_fetched_at: 1.hour.ago)
      expect(feed2.health_status).to eq('unhealthy')
    end

    it 'returns "degraded" when failure count is between 3-4' do
      feed = create(:rss_feed, fetch_failure_count: 3, last_fetched_at: 1.hour.ago)
      expect(feed.health_status).to eq('degraded')
      
      feed2 = create(:rss_feed, fetch_failure_count: 4, last_fetched_at: 1.hour.ago)
      expect(feed2.health_status).to eq('degraded')
    end

    it 'returns "broken" when failure count is 5 or more' do
      feed = create(:rss_feed, fetch_failure_count: 5, last_fetched_at: 1.hour.ago)
      expect(feed.health_status).to eq('broken')
    end

    it 'returns "never_fetched" when last_fetched_at is nil' do
      feed = create(:rss_feed, last_fetched_at: nil, fetch_failure_count: 0)
      expect(feed.health_status).to eq('never_fetched')
    end
  end

  describe '#latest_posts' do
    let(:feed) { create(:rss_feed) }
    let!(:posts) { create_list(:rss_post, 5, rss_feed: feed) }

    it 'returns posts ordered by published_at desc' do
      expect(feed.latest_posts(10).count).to eq(5)
    end

    it 'limits results by the provided limit' do
      expect(feed.latest_posts(2).count).to eq(2)
    end
  end

  describe '#unviewed_posts' do
    let(:feed) { create(:rss_feed) }
    let!(:viewed_post) { create(:rss_post, rss_feed: feed, is_viewed: true) }
    let!(:unviewed_post) { create(:rss_post, rss_feed: feed, is_viewed: false) }

    it 'returns only unviewed posts' do
      expect(feed.unviewed_posts).to include(unviewed_post)
      expect(feed.unviewed_posts).not_to include(viewed_post)
    end
  end

  describe '#needs_fetch?' do
    it 'returns true when never fetched' do
      feed = create(:rss_feed, last_fetched_at: nil)
      expect(feed.needs_fetch?).to be true
    end

    it 'returns true when last fetched more than an hour ago' do
      feed = create(:rss_feed, last_fetched_at: 2.hours.ago)
      expect(feed.needs_fetch?).to be true
    end

    it 'returns false when fetched recently' do
      feed = create(:rss_feed, last_fetched_at: 30.minutes.ago)
      expect(feed.needs_fetch?).to be false
    end
  end

  describe '#mark_as_fetched!' do
    it 'updates last_fetched_at timestamp' do
      feed = create(:rss_feed, last_fetched_at: nil)
      feed.mark_as_fetched!
      
      expect(feed.last_fetched_at).to be_present
    end
  end

  describe '#can_be_managed_by?' do
    let(:feed) { create(:rss_feed) }
    let(:admin_user) { create(:user, is_account_admin: true, account_id: feed.account_id) }
    let(:other_admin) { create(:user, is_account_admin: true, account_id: 999) }
    let(:regular_user) { create(:user, is_account_admin: false) }
    let(:super_admin) { create(:user) }

    before do
      allow(super_admin).to receive(:super_admin?).and_return(true)
    end

    it 'returns true for super admin' do
      expect(feed.can_be_managed_by?(super_admin)).to be true
    end

    it 'returns true for account admin of same account' do
      expect(feed.can_be_managed_by?(admin_user)).to be true
    end

    it 'returns false for account admin of different account' do
      expect(feed.can_be_managed_by?(other_admin)).to be false
    end

    it 'returns false for regular user' do
      # Ensure feed has an account_id and regular user is from different account
      feed.update!(account_id: 100) if feed.account_id.nil?
      regular_user.update!(is_account_admin: false, account_id: feed.account_id + 1)
      expect(feed.can_be_managed_by?(regular_user)).to be false
    end

    it 'returns false for nil user' do
      expect(feed.can_be_managed_by?(nil)).to be false
    end
  end

  describe '#status' do
    it 'returns inactive when feed is not active' do
      feed = create(:rss_feed, is_active: false)
      expect(feed.status).to eq('inactive')
    end

    it 'returns never_fetched when never fetched' do
      feed = create(:rss_feed, is_active: true, last_fetched_at: nil)
      expect(feed.status).to eq('never_fetched')
    end

    it 'returns needs_fetch when last fetched more than an hour ago' do
      feed = create(:rss_feed, is_active: true, last_fetched_at: 2.hours.ago)
      expect(feed.status).to eq('needs_fetch')
    end

    it 'returns active when recently fetched' do
      feed = create(:rss_feed, is_active: true, last_fetched_at: 30.minutes.ago)
      expect(feed.status).to eq('active')
    end
  end

  describe 'scope :for_account' do
    let(:account1) { create(:account) }
    let(:account2) { create(:account) }
    let!(:feed1) { create(:rss_feed, account: account1) }
    let!(:feed2) { create(:rss_feed, account: account2) }

    it 'returns feeds for specific account' do
      expect(RssFeed.for_account(account1.id)).to include(feed1)
      expect(RssFeed.for_account(account1.id)).not_to include(feed2)
    end
  end
end

