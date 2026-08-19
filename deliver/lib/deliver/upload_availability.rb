require_relative 'module'
require 'spaceship'

module Deliver
  # Manage the app's territory availability via the App Store Connect API.
  #
  # For new apps (no existing availability), uses POST /v2/appAvailabilities.
  # For existing apps, uses PATCH /v1/territoryAvailabilities/{id} per territory.
  class UploadAvailability
    def upload(options)
      return unless should_upload?(options)

      app = Deliver.cache[:app]
      available_in_new_territories = options[:available_in_new_territories].nil? ? true : options[:available_in_new_territories]
      desired_territory_ids = resolve_territory_ids(options)

      existing_availability = fetch_current_availability(app)
      UI.verbose("Existing availability: #{existing_availability.inspect}")

      if existing_availability
        update_existing_territories(app, desired_territory_ids)
      else
        UI.message("No existing availability found, creating new availability...")
        create_availability(app, desired_territory_ids, available_in_new_territories)
      end
    end

    private

    def should_upload?(options)
      options[:available_countries] || !options[:available_in_new_territories].nil?
    end

    def resolve_territory_ids(options)
      if options[:available_countries]
        options[:available_countries]
      else
        Spaceship::ConnectAPI::Territory.all.map(&:id)
      end
    end

    def fetch_current_availability(app)
      app.get_app_availabilities
    rescue Spaceship::UnexpectedResponse => e
      if e.message.include?("404") || e.message.include?("not found") || e.message.include?("does not exist")
        UI.verbose("No existing app availability found")
        nil
      else
        raise
      end
    rescue => e
      UI.verbose("Could not fetch current availability: #{e.message}")
      nil
    end

    def create_availability(app, territory_ids, available_in_new_territories)
      app.update_availability(
        territory_ids: territory_ids,
        available_in_new_territories: available_in_new_territories
      )
      UI.success("Successfully created app availability (#{territory_ids.length} territories)")
    end

    def update_existing_territories(app, desired_territory_ids)
      current_territories = app.fetch_territory_availabilities(includes: "territory")

      changed = 0
      current_territories.each do |ta|
        territory_id = ta.territory&.id || ta.id
        should_be_available = desired_territory_ids.include?(territory_id)

        next if ta.available == should_be_available

        app.patch_territory_availability(
          territory_availability_id: ta.id,
          available: should_be_available
        )
        changed += 1
        UI.verbose("Territory #{territory_id}: #{ta.available} -> #{should_be_available}")
      end

      if changed > 0
        UI.success("Successfully updated app availability (#{changed} territories changed)")
      else
        UI.success("App availability unchanged")
      end
    end
  end
end
