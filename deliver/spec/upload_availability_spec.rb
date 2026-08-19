require 'deliver/upload_availability'

describe Deliver::UploadAvailability do
  let(:app) { double('app') }
  let(:uploader) { Deliver::UploadAvailability.new }

  before do
    allow(Deliver).to receive(:cache).and_return({ app: app })
  end

  describe '#upload' do
    context 'when no availability options are set' do
      it 'does nothing' do
        options = {}
        expect(app).not_to receive(:update_availability)
        uploader.upload(options)
      end
    end

    context 'when available_countries is set' do
      it 'updates availability with specific territories' do
        allow(app).to receive(:get_app_availabilities).and_return(nil)
        expect(app).to receive(:update_availability).with(
          territory_ids: ["USA", "GBR"],
          available_in_new_territories: true
        )

        uploader.upload({ available_countries: ["USA", "GBR"], available_in_new_territories: true })
      end
    end

    context 'when only available_in_new_territories is set' do
      let(:all_territories) { [double('territory', id: "USA"), double('territory', id: "GBR")] }

      it 'fetches all territories and updates' do
        allow(Spaceship::ConnectAPI::Territory).to receive(:all).and_return(all_territories)
        allow(app).to receive(:get_app_availabilities).and_return(nil)
        expect(app).to receive(:update_availability).with(
          territory_ids: ["USA", "GBR"],
          available_in_new_territories: true
        )

        uploader.upload({ available_in_new_territories: true })
      end
    end
  end
end
