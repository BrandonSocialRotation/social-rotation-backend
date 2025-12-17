require 'rails_helper'

RSpec.describe MarketItem, type: :model do
  describe 'associations' do
    it { should belong_to(:bucket) }
    it { should belong_to(:front_image).class_name('Image').optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:price) }
    it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
  end

  describe 'methods' do
    let(:user) { create(:user) }
    let(:bucket) { create(:bucket, user: user) }
    let(:image) { create(:image, friendly_name: 'Test Image') }
    let(:market_item) { create(:market_item, bucket: bucket, front_image: image) }

    describe '#has_user_market_item?' do
      it 'returns false when user does not own item' do
        expect(market_item.has_user_market_item?(user.id)).to be false
      end

      it 'returns true when user owns item' do
        create(:user_market_item, user: user, market_item: market_item)
        expect(market_item.has_user_market_item?(user.id)).to be true
      end
    end

    describe '#get_front_image_url' do
      before do
        # Ensure test environment generates DigitalOcean URLs
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DO_SPACES_ENDPOINT').and_return(nil)
        allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_ENDPOINT').and_return(nil)
        allow(ENV).to receive(:[]).with('DO_SPACES_BUCKET').and_return(nil)
        allow(ENV).to receive(:[]).with('DIGITAL_OCEAN_SPACES_NAME').and_return(nil)
        # Update image to have test/ prefix
        image.update!(file_path: 'test/' + image.file_path) unless image.file_path.start_with?('test/')
      end
      
      it 'returns front image URL when front_image exists' do
        expect(market_item.get_front_image_url).to include('se1.sfo2.digitaloceanspaces.com')
      end

      it 'returns fallback when no front_image and no bucket images' do
        market_item.update!(front_image: nil)
        expect(market_item.get_front_image_url).to eq('/img/no_image_available.gif')
      end

      it 'returns first bucket image URL when no front_image but bucket has images' do
        market_item.update!(front_image: nil)
        bucket_image = create(:bucket_image, bucket: bucket, image: image, friendly_name: 'First Image')
        
        expect(market_item.get_front_image_url).to include('se1.sfo2.digitaloceanspaces.com')
      end

      it 'returns fallback when no front_image and bucket has no images' do
        market_item.update!(front_image: nil)
        bucket.bucket_images.destroy_all
        
        expect(market_item.get_front_image_url).to eq('/img/no_image_available.gif')
      end
    end

    describe '#get_front_image_friendly_name' do
      it 'returns front image friendly name when front_image exists' do
        expect(market_item.get_front_image_friendly_name).to eq('Test Image')
      end

      it 'returns N/A when no front_image and no bucket images' do
        market_item.update!(front_image: nil)
        expect(market_item.get_front_image_friendly_name).to eq('N/A')
      end

      it 'returns first bucket image friendly name when no front_image but bucket has images' do
        market_item.update!(front_image: nil)
        bucket_image = create(:bucket_image, bucket: bucket, image: image, friendly_name: 'First Image')
        
        expect(market_item.get_front_image_friendly_name).to eq('First Image')
      end

      it 'returns N/A when no front_image and bucket has no images' do
        market_item.update!(front_image: nil)
        bucket.bucket_images.destroy_all
        
        expect(market_item.get_front_image_friendly_name).to eq('N/A')
      end
    end

    describe '#has_hidden_user_market_item?' do
      it 'returns false when user does not own item' do
        expect(market_item.has_hidden_user_market_item?(user.id)).to be false
      end

      it 'returns false when user owns visible item' do
        create(:user_market_item, user: user, market_item: market_item, visible: true)
        expect(market_item.has_hidden_user_market_item?(user.id)).to be false
      end

      it 'returns true when user owns hidden item' do
        create(:user_market_item, user: user, market_item: market_item, visible: false)
        expect(market_item.has_hidden_user_market_item?(user.id)).to be true
      end
    end

    describe 'scope :all_reseller' do
      it 'returns only visible market items' do
        visible_item = create(:market_item, visible: true)
        hidden_item = create(:market_item, visible: false)
        
        expect(MarketItem.all_reseller).to include(visible_item)
        expect(MarketItem.all_reseller).not_to include(hidden_item)
      end
    end

    describe '#get_front_image_url edge cases' do
      it 'handles bucket with no images gracefully' do
        market_item.update!(front_image: nil)
        bucket.bucket_images.destroy_all
        
        expect(market_item.get_front_image_url).to eq('/img/no_image_available.gif')
      end

      it 'handles bucket_image without image association' do
        market_item.update!(front_image: nil)
        bucket_image = create(:bucket_image, bucket: bucket, friendly_name: 'Test')
        bucket_image.update_column(:image_id, 99999) # Non-existent image
        
        expect(market_item.get_front_image_url).to eq('/img/no_image_available.gif')
      end
    end

    describe '#get_front_image_friendly_name edge cases' do
      it 'handles bucket_image without image association' do
        market_item.update!(front_image: nil)
        bucket_image = create(:bucket_image, bucket: bucket, friendly_name: 'Test')
        bucket_image.update_column(:image_id, 99999) # Non-existent image
        
        expect(market_item.get_front_image_friendly_name).to eq('N/A')
      end

      it 'handles nil bucket gracefully' do
        market_item.update!(front_image: nil, bucket: nil)
        expect(market_item.get_front_image_friendly_name).to eq('N/A')
      end
    end
  end
end
