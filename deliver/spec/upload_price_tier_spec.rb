require 'deliver/upload_price_tier'

describe Deliver::UploadPriceTier do
  let(:app) { double('app') }
  let(:uploader) { Deliver::UploadPriceTier.new }

  before do
    allow(Deliver).to receive(:cache).and_return({ app: app })
  end

  describe '#upload' do
    context 'when no price_tier is set' do
      it 'does nothing' do
        options = {}
        expect(app).not_to receive(:fetch_app_price_schedule)
        uploader.upload(options)
      end
    end

    context 'when price_tier is 0 (free)' do
      let(:price_point_free) do
        double('price_point', id: "eyJ0ZXN0IjowfQ", customer_price: "0.0")
      end

      it 'creates a price schedule for free tier' do
        allow(app).to receive(:fetch_app_price_schedule).and_return(nil)
        allow(app).to receive(:fetch_app_price_points).and_return([price_point_free])
        expect(app).to receive(:update_price_schedule).with(
          base_territory_id: "USA",
          manual_prices: [{ app_price_point_id: "eyJ0ZXN0IjowfQ" }]
        )

        uploader.upload({ price_tier: 0, base_territory: "USA" })
      end
    end

    context 'when price is unchanged' do
      let(:price_point) { double('price_point', id: "eyJ0ZXN0IjowfQ", customer_price: "0.0") }
      let(:manual_price) { double('manual_price', end_date: nil, app_price_point: price_point) }
      let(:schedule) { double('schedule', manual_prices: [manual_price]) }

      it 'skips update' do
        allow(app).to receive(:fetch_app_price_schedule).and_return(schedule)
        allow(app).to receive(:fetch_app_price_points).and_return([price_point])
        expect(app).not_to receive(:update_price_schedule)

        uploader.upload({ price_tier: 0, base_territory: "USA" })
      end
    end

    context 'when the price point changed' do
      let(:old_price_point) { double('old_price_point', id: "old_id", customer_price: "0.0") }
      let(:new_price_point) { double('new_price_point', id: "new_id", customer_price: "0.99") }
      let(:manual_price) { double('manual_price', end_date: nil, app_price_point: old_price_point) }
      let(:schedule) { double('schedule', manual_prices: [manual_price]) }

      it 'updates the schedule' do
        allow(app).to receive(:fetch_app_price_schedule).and_return(schedule)
        allow(app).to receive(:fetch_app_price_points).and_return([old_price_point, new_price_point])
        expect(app).to receive(:update_price_schedule).with(
          base_territory_id: "USA",
          manual_prices: [{ app_price_point_id: "new_id" }]
        )

        uploader.upload({ price_tier: 1, base_territory: "USA" })
      end
    end
  end
end
