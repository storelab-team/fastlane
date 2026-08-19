require_relative 'module'
require 'spaceship'

module Deliver
  # Set the app's pricing via the App Store Connect appPriceSchedules API.
  #
  # The legacy appPrices/appPriceTiers endpoints were deprecated in ASC API 2.3
  # (March 2023). This implementation uses POST /v1/appPriceSchedules with
  # price-point IDs looked up per territory.
  class UploadPriceTier
    def upload(options)
      return if options[:price_tier].nil?

      price_tier = options[:price_tier]
      app = Deliver.cache[:app]
      base_territory = options[:base_territory] || "USA"

      price_point = find_price_point(app, base_territory, price_tier)
      current_price_point = fetch_current_price_point(app)

      if current_price_point && current_price_point.id == price_point.id
        UI.success("Price Tier unchanged (tier #{price_tier}, #{price_point.customer_price})")
        return
      end

      app.update_price_schedule(
        base_territory_id: base_territory,
        manual_prices: [{ app_price_point_id: price_point.id }]
      )

      UI.success("Successfully updated the price schedule to tier #{price_tier} (#{price_point.customer_price})")
    end

    private

    # Returns the price point currently in effect, so it can be compared against
    # the desired one by ID. Comparing a tier number to a customer price string
    # never matches ("1" vs "0.99") and would re-post the schedule every run.
    def fetch_current_price_point(app)
      schedule = app.fetch_app_price_schedule(includes: "manualPrices,manualPrices.appPricePoint,baseTerritory")
      return nil unless schedule

      manual_prices = schedule.manual_prices
      return nil unless manual_prices&.any?

      current = manual_prices.find { |p| p.end_date.nil? }
      return nil unless current&.app_price_point

      current.app_price_point
    rescue => e
      UI.verbose("Could not fetch current price schedule: #{e.message}")
      nil
    end

    def find_price_point(app, territory, price_tier)
      price_points = app.fetch_app_price_points(
        filter: { territory: territory },
        includes: "territory"
      )

      if price_tier.to_i == 0
        point = price_points.find { |pp| pp.customer_price == "0.0" || pp.customer_price == "0" }
      else
        point = price_points.find { |pp| pp.customer_price == price_tier_to_price(price_tier) }
      end

      point ||= price_points[price_tier.to_i] if price_tier.to_i < price_points.length

      unless point
        UI.user_error!("Could not find a price point for tier #{price_tier} in territory #{territory}. " \
                        "Available price points: #{price_points.map(&:customer_price).first(10).join(', ')}...")
      end
      point
    end

    # Maps legacy tier numbers to approximate USD prices for common tiers.
    # Falls back to index-based lookup if not found.
    def price_tier_to_price(tier)
      tier = tier.to_i
      return "0.0" if tier == 0
      return "#{tier - 1}.99" if tier <= 50
      nil
    end
  end
end
