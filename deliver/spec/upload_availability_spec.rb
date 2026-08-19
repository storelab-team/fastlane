require 'deliver/upload_availability'

describe Deliver::UploadAvailability do
  let(:app) { double('app') }
  let(:uploader) { Deliver::UploadAvailability.new }

  def territory_availability(id, code, available)
    double("territory_availability_#{code}", id: id, available: available, territory: double('territory', id: code))
  end

  before do
    allow(Deliver).to receive(:cache).and_return({ app: app })
  end

  describe '#upload' do
    context 'when no availability options are set' do
      it 'does nothing' do
        expect(app).not_to receive(:get_app_availabilities)
        uploader.upload({})
      end
    end

    context 'when the app has no availability yet' do
      before do
        allow(app).to receive(:get_app_availabilities).and_return(nil)
      end

      it 'creates availability for the requested territories' do
        expect(app).to receive(:update_availability).with(
          territory_ids: ["USA", "GBR"],
          available_in_new_territories: true
        )

        uploader.upload({ available_countries: ["USA", "GBR"], available_in_new_territories: true })
      end

      it 'defaults available_in_new_territories to true when unspecified' do
        expect(app).to receive(:update_availability).with(
          territory_ids: ["USA"],
          available_in_new_territories: true
        )

        uploader.upload({ available_countries: ["USA"] })
      end

      it 'errors when only available_in_new_territories is set' do
        expect(app).not_to receive(:update_availability)
        expect do
          uploader.upload({ available_in_new_territories: true })
        end.to raise_error(FastlaneCore::Interface::FastlaneError, /please also specify `available_countries`/)
      end

      it 'errors on an empty territory list' do
        expect(app).not_to receive(:update_availability)
        expect do
          uploader.upload({ available_countries: [] })
        end.to raise_error(FastlaneCore::Interface::FastlaneError, /at least one territory/)
      end
    end

    context 'when the app already has availability' do
      let(:existing) { double('availability', available_in_new_territories: true) }

      before do
        allow(app).to receive(:get_app_availabilities).and_return(existing)
      end

      it 'enables and disables territories to match the requested list' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true),
                                                                            territory_availability("ta_gbr", "GBR", false),
                                                                            territory_availability("ta_jpn", "JPN", true)
                                                                          ])

        expect(app).to receive(:patch_territory_availability).with(territory_availability_id: "ta_gbr", available: true)
        expect(app).to receive(:patch_territory_availability).with(territory_availability_id: "ta_jpn", available: false)
        expect(app).not_to receive(:patch_territory_availability).with(hash_including(territory_availability_id: "ta_usa"))

        uploader.upload({ available_countries: ["USA", "GBR"] })
      end

      it 'never calls update_availability on an existing app' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true)
                                                                          ])
        expect(app).not_to receive(:update_availability)

        uploader.upload({ available_countries: ["USA"] })
      end

      it 'makes no requests when availability already matches' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true),
                                                                            territory_availability("ta_gbr", "GBR", false)
                                                                          ])
        expect(app).not_to receive(:patch_territory_availability)

        uploader.upload({ available_countries: ["USA"] })
      end

      it 'refuses to remove the app from every territory' do
        expect(app).not_to receive(:patch_territory_availability)
        expect do
          uploader.upload({ available_countries: [] })
        end.to raise_error(FastlaneCore::Interface::FastlaneError, /every App Store territory/)
      end

      it 'reports the territories that failed instead of aborting on the first one' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_gbr", "GBR", false),
                                                                            territory_availability("ta_bra", "BRA", false)
                                                                          ])
        allow(app).to receive(:patch_territory_availability).with(territory_availability_id: "ta_gbr", available: true)
        allow(app).to receive(:patch_territory_availability)
          .with(territory_availability_id: "ta_bra", available: true)
          .and_raise("BRAZIL_REQUIRED_TAX_ID")

        expect do
          uploader.upload({ available_countries: ["GBR", "BRA"] })
        end.to raise_error(FastlaneCore::Interface::FastlaneError, /BRA: BRAZIL_REQUIRED_TAX_ID/)
      end

      it 'warns that available_in_new_territories cannot be changed' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true)
                                                                          ])
        expect(FastlaneCore::UI).to receive(:important).with(/cannot be changed to false/)

        uploader.upload({ available_countries: ["USA"], available_in_new_territories: false })
      end

      it 'stays silent when available_in_new_territories already matches' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true)
                                                                          ])
        expect(FastlaneCore::UI).not_to receive(:important)

        uploader.upload({ available_countries: ["USA"], available_in_new_territories: true })
      end

      it 'warns about requested territories App Store Connect did not return' do
        allow(app).to receive(:fetch_territory_availabilities).and_return([
                                                                            territory_availability("ta_usa", "USA", true)
                                                                          ])
        expect(FastlaneCore::UI).to receive(:important).with(/not returned by App Store Connect.*ZZZ/)

        uploader.upload({ available_countries: ["USA", "ZZZ"] })
      end
    end

    context 'when fetching current availability fails' do
      it 'does not fall through to creating availability' do
        allow(app).to receive(:get_app_availabilities)
          .and_raise(Spaceship::UnexpectedResponse.new("500 Internal Server Error"))
        expect(app).not_to receive(:update_availability)

        expect do
          uploader.upload({ available_countries: ["USA"] })
        end.to raise_error(Spaceship::UnexpectedResponse)
      end
    end
  end
end
