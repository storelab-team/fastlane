require_relative '../model'
module Spaceship
  class ConnectAPI
    class AppPriceSchedule
      include Spaceship::ConnectAPI::Model

      attr_accessor :base_territory
      attr_accessor :manual_prices
      attr_accessor :automatic_prices

      attr_mapping({
        "baseTerritory" => "base_territory",
        "manualPrices" => "manual_prices",
        "automaticPrices" => "automatic_prices"
      })

      def self.type
        return "appPriceSchedules"
      end
    end
  end
end
