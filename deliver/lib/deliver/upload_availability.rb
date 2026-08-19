require_relative 'module'
require 'spaceship'

module Deliver
  # Manage the app's territory availability via the App Store Connect API.
  #
  # Apple only exposes two writes for availability (ASC API spec 4.4):
  #
  #   POST  /v2/appAvailabilities            create-only, requires the full
  #                                          territory list AND availableInNewTerritories
  #   PATCH /v1/territoryAvailabilities/{id} per-territory `available` flag
  #
  # There is no PATCH for appAvailabilities, so `available_in_new_territories`
  # can only be set at creation time. On an app that already has availability
  # we warn instead of silently doing nothing.
  class UploadAvailability
    def upload(options)
      return unless should_upload?(options)

      app = Deliver.cache[:app]
      desired_territory_ids = options[:available_countries]
      available_in_new_territories = options[:available_in_new_territories]

      existing_availability = fetch_current_availability(app)

      if existing_availability.nil?
        create_availability(app, desired_territory_ids, available_in_new_territories)
      else
        update_existing_territories(app, desired_territory_ids) if desired_territory_ids
        warn_unsupported_new_territories_change(existing_availability, available_in_new_territories)
      end
    end

    private

    def should_upload?(options)
      !options[:available_countries].nil? || !options[:available_in_new_territories].nil?
    end

    # No availability record yet: POST is the only write, and Apple requires
    # both the territory list and the flag in the same request.
    def create_availability(app, territory_ids, available_in_new_territories)
      if territory_ids.nil?
        UI.user_error!("This app has no availability set yet. `available_in_new_territories` cannot be set on " \
                       "its own because App Store Connect requires the territory list in the same request - " \
                       "please also specify `available_countries`.")
      end

      if territory_ids.empty?
        UI.user_error!("`available_countries` is empty. An app must be available in at least one territory.")
      end

      UI.message("No existing availability found, creating availability for #{territory_ids.length} territories...")
      app.update_availability(
        territory_ids: territory_ids,
        available_in_new_territories: available_in_new_territories.nil? ? true : available_in_new_territories
      )
      UI.success("Successfully created app availability (#{territory_ids.length} territories)")
    end

    # `available_countries` is authoritative: territories not in the list are
    # made unavailable.
    def update_existing_territories(app, desired_territory_ids)
      if desired_territory_ids.empty?
        UI.user_error!("`available_countries` is empty. This would remove the app from every App Store territory - " \
                       "refusing to continue. Specify at least one territory.")
      end

      current_territories = app.fetch_territory_availabilities(includes: "territory")
      log_current_state(current_territories, desired_territory_ids)

      to_enable = []
      to_disable = []

      current_territories.each do |ta|
        territory_id = territory_id_for(ta)
        should_be_available = desired_territory_ids.include?(territory_id)
        next if ta.available == should_be_available

        (should_be_available ? to_enable : to_disable) << [ta, territory_id, should_be_available]
      end

      if to_enable.empty? && to_disable.empty?
        UI.success("App availability already up to date (#{desired_territory_ids.length} territories)")
        return
      end

      UI.message("Updating availability: +#{to_enable.length} / -#{to_disable.length} territories")
      failures = apply_changes(app, to_enable + to_disable)

      if failures.empty?
        UI.success("Successfully updated app availability (#{to_enable.length + to_disable.length} territories changed)")
      else
        UI.user_error!("Failed to update #{failures.length} of #{to_enable.length + to_disable.length} territories. " \
                       "App availability is now in a partially updated state:\n" +
                       failures.map { |code, message| "  #{code}: #{message}" }.join("\n"))
      end
    end

    # Apple rejects individual territories for reasons unrelated to this run
    # (missing tax ID, missing age rating, restricted content). Collect those so
    # one bad territory doesn't abandon the other 170.
    def apply_changes(app, changes)
      failures = []

      changes.each do |ta, territory_id, should_be_available|
        app.patch_territory_availability(
          territory_availability_id: ta.id,
          available: should_be_available
        )
        UI.verbose("Territory #{territory_id}: #{ta.available} -> #{should_be_available}")
      rescue => e
        failures << [territory_id, e.message]
        UI.error("Territory #{territory_id}: #{e.message}")
      end

      failures
    end

    def territory_id_for(ta)
      territory = ta.territory
      if territory.nil? || territory.id.nil?
        UI.user_error!("App Store Connect returned a territory availability (#{ta.id}) without a territory. " \
                       "Cannot determine which territory it refers to.")
      end
      territory.id
    end

    # Surfaces whether the endpoint returns every territory or only the ones the
    # app is currently available in, and flags territories we cannot reach.
    def log_current_state(current_territories, desired_territory_ids)
      available = current_territories.count(&:available)
      UI.verbose("App Store Connect returned #{current_territories.length} territory availabilities " \
                 "(#{available} available, #{current_territories.length - available} unavailable)")

      known_ids = current_territories.map { |ta| territory_id_for(ta) }
      missing = desired_territory_ids - known_ids
      return if missing.empty?

      UI.important("#{missing.length} requested territories were not returned by App Store Connect and cannot be " \
                   "updated: #{missing.join(', ')}. Check that these are valid territory codes.")
    end

    def warn_unsupported_new_territories_change(existing_availability, available_in_new_territories)
      return if available_in_new_territories.nil?
      return if existing_availability.available_in_new_territories == available_in_new_territories

      UI.important("`available_in_new_territories` is currently " \
                   "#{existing_availability.available_in_new_territories} and cannot be changed to " \
                   "#{available_in_new_territories}: App Store Connect only accepts this attribute when the app's " \
                   "availability is first created. Please change it in App Store Connect directly.")
    end

    def fetch_current_availability(app)
      app.get_app_availabilities
    rescue Spaceship::UnexpectedResponse => e
      # A missing availability record is the signal to create one. Anything
      # else must not fall through to the create path, which would then fail
      # with a confusing 409 conflict.
      raise unless e.message.include?("404") || e.message.include?("NOT_FOUND")

      UI.verbose("No existing app availability found")
      nil
    end
  end
end
