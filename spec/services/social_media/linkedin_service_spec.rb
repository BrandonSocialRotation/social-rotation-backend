require 'rails_helper'

RSpec.describe SocialMedia::LinkedinService do
  let(:user) { create(:user, linkedin_access_token: 'test_token', linkedin_profile_id: 'profile123') }
  let(:service) { SocialMedia::LinkedinService.new(user) }
  
  before do
    stub_request(:get, /api\.linkedin\.com/).to_return(status: 200, body: '{}')
    stub_request(:post, /api\.linkedin\.com/).to_return(status: 200, body: '{}')
  end
  
  describe '#post_with_image' do
    context 'when user has LinkedIn connected' do
      before do
        stub_request(:post, /api\.linkedin\.com\/v2\/assets/)
          .to_return(status: 200, body: {
            value: {
              asset: 'urn:li:digitalmediaAsset:123',
              uploadMechanism: {
                'com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest' => {
                  uploadUrl: 'https://upload.linkedin.com/upload'
                }
              }
            }
          }.to_json)
        stub_request(:post, /upload\.linkedin\.com/)
          .to_return(status: 200, body: 'OK')
        stub_request(:post, /api\.linkedin\.com\/v2\/ugcPosts/)
          .to_return(status: 200, body: { id: 'post123' }.to_json)
      end
      
      it 'posts with image successfully' do
        # Create a test image file
        image_path = Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')
        FileUtils.mkdir_p(File.dirname(image_path))
        File.write(image_path, 'fake image data') unless File.exist?(image_path)
        
        result = service.post_with_image('Test message', image_path.to_s)
        expect(result).to be_a(Hash)
      end
    end
    
    context 'when user does not have LinkedIn connected' do
      before do
        user.update(linkedin_access_token: nil)
      end
      
      it 'raises an error' do
        expect {
          service.post_with_image('Test', '/path/to/image.jpg')
        }.to raise_error(/does not have LinkedIn connected/)
      end
    end
  end
  
  describe '#fetch_organizations' do
    context 'when user has LinkedIn connected' do
      before do
        stub_request(:get, /api\.linkedin\.com\/v2\/organizationalEntityAcls/)
          .to_return(status: 200, body: {
            elements: [
              { organizationalTarget: 'urn:li:organization:123' }
            ]
          }.to_json)
        stub_request(:get, /api\.linkedin\.com\/v2\/organizations\/123/)
          .to_return(status: 200, body: {
            id: '123',
            localizedName: 'Test Organization'
          }.to_json)
      end
      
      it 'fetches organizations successfully' do
        orgs = service.fetch_organizations
        expect(orgs).to be_an(Array)
        expect(orgs.first).to have_key(:id)
        expect(orgs.first).to have_key(:name)
        expect(orgs.first).to have_key(:urn)
      end
    end
    
    context 'when user does not have LinkedIn connected' do
      before do
        user.update(linkedin_access_token: nil)
      end
      
      it 'raises an error' do
        expect {
          service.fetch_organizations
        }.to raise_error(/does not have LinkedIn connected/)
      end
    end
    
    context 'with API errors' do
      before do
        stub_request(:get, /api\.linkedin\.com\/v2\/organizationalEntityAcls/)
          .to_return(status: 401, body: 'Unauthorized')
      end
      
      it 'returns empty array' do
        orgs = service.fetch_organizations
        expect(orgs).to eq([])
      end
    end
  end
  
  describe '#get_personal_profile_urn' do
    context 'when profile ID exists' do
      it 'returns personal profile URN' do
        urn = service.get_personal_profile_urn
        expect(urn).to eq('urn:li:person:profile123')
      end
    end
    
    context 'when profile ID does not exist' do
      before do
        user.update(linkedin_profile_id: nil)
        stub_request(:get, /api\.linkedin\.com\/v2\/me/)
          .to_return(status: 200, body: { id: 'new_profile_id' }.to_json)
      end
      
      it 'fetches and returns profile URN' do
        urn = service.get_personal_profile_urn
        expect(urn).to include('urn:li:person:')
      end
    end
  end
end

