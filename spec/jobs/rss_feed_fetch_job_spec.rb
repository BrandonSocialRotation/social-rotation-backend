require 'rails_helper'

RSpec.describe RssFeedFetchJob, type: :job do
  describe '#perform' do
    let(:rss_fetch_service) { instance_double(RssFetchService) }
    let(:feed) { create(:rss_feed, is_active: true) }

    before do
      allow(RssFetchService).to receive(:new).and_return(rss_fetch_service)
    end

    context 'when feed_id is provided' do
      it 'fetches a specific feed if it exists and is active' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: true,
          posts_saved: 5
        })

        RssFeedFetchJob.new.perform(feed.id)

        expect(RssFetchService).to have_received(:new).with(feed)
        expect(rss_fetch_service).to have_received(:fetch_and_parse)
      end

      it 'does not fetch if feed does not exist' do
        RssFeedFetchJob.new.perform(99999)

        expect(RssFetchService).not_to have_received(:new)
      end

      it 'does not fetch if feed is not active' do
        inactive_feed = create(:rss_feed, is_active: false)

        RssFeedFetchJob.new.perform(inactive_feed.id)

        expect(RssFetchService).not_to have_received(:new)
      end
    end

    context 'when feed_id is nil' do
      let!(:active_feed1) { create(:rss_feed, is_active: true) }
      let!(:active_feed2) { create(:rss_feed, is_active: true) }
      let!(:inactive_feed) { create(:rss_feed, is_active: false) }

      it 'fetches all active feeds' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: true,
          posts_saved: 3
        })
        allow_any_instance_of(RssFeed).to receive(:record_success!)

        RssFeedFetchJob.new.perform(nil)

        expect(RssFetchService).to have_received(:new).at_least(:twice)
      end

      it 'skips inactive feeds' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: true,
          posts_saved: 3
        })

        RssFeedFetchJob.new.perform(nil)

        # Should only call for active feeds
        expect(RssFetchService).to have_received(:new).exactly(2).times
      end
    end

    context 'when fetch is successful' do
      it 'records success on the feed' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: true,
          posts_saved: 5
        })

        RssFeedFetchJob.new.perform(feed.id)

        feed.reload
        expect(feed.health_status).to eq('healthy')
      end

      it 'logs success message' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: true,
          posts_saved: 5
        })
        allow(Rails.logger).to receive(:info)

        RssFeedFetchJob.new.perform(feed.id)

        expect(Rails.logger).to have_received(:info).with(
          match(/Successfully fetched 5 posts/)
        )
      end
    end

    context 'when fetch fails' do
      it 'records failure on the feed' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: false,
          error: 'Network error'
        })

        RssFeedFetchJob.new.perform(feed.id)

        feed.reload
        expect(feed.health_status).to eq('unhealthy')
      end

      it 'logs error message' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_return({
          success: false,
          error: 'Network error'
        })
        allow(Rails.logger).to receive(:error)

        RssFeedFetchJob.new.perform(feed.id)

        expect(Rails.logger).to have_received(:error).with(
          match(/Failed to fetch.*Network error/)
        )
      end
    end

    context 'when an exception is raised' do
      it 'records failure with exception message' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_raise(StandardError.new('Unexpected error'))
        allow(Rails.logger).to receive(:error)

        RssFeedFetchJob.new.perform(feed.id)

        feed.reload
        expect(feed.health_status).to eq('unhealthy')
        expect(Rails.logger).to have_received(:error).with(
          match(/Error fetching.*Unexpected error/)
        )
      end

      it 'handles exceptions gracefully' do
        allow(rss_fetch_service).to receive(:fetch_and_parse).and_raise(StandardError.new('Unexpected error'))

        expect {
          RssFeedFetchJob.new.perform(feed.id)
        }.not_to raise_error
      end
    end
  end
end
