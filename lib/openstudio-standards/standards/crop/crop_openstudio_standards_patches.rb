# CROP override for typical service water heating (SWH).
# openstudio-standards 0.8.2 puts the zone multiplier in the typical SWH peak flow,
# and EnergyPlus applies the zone multiplier again. This wrapper calls the upstream
# method, then removes the zone multiplier from the peak flows. The water heaters
# keep their size, because upstream sizes them for the whole building.
# Remove this file when the openstudio-standards gem has the fix.
module OpenstudioStandards
  module ServiceWaterHeating
    class << self
      unless method_defined?(:create_typical_service_water_heating_without_crop_fix)
        alias_method :create_typical_service_water_heating_without_crop_fix, :create_typical_service_water_heating
      end

      def create_typical_service_water_heating(model, **kwargs)
        swh_loops = create_typical_service_water_heating_without_crop_fix(model, **kwargs)
        remove_zone_multiplier_from_typical_swh_flows_crop(model)
        swh_loops
      end

      # Divides a peak flow by its zone multiplier only if it equals the typical
      # per-space flow times the multiplier. Fixed flows that upstream does not
      # multiply, and flows that are already per space, do not change.
      def remove_zone_multiplier_from_typical_swh_flows_crop(model)
        swh_dir = File.dirname(method(:create_water_use).source_location.first)
        data = JSON.parse(File.read("#{swh_dir}/data/typical_water_use_equipment.json"), symbolize_names: true)
        done = {}
        model.getWaterUseEquipments.each do |equipment|
          definition = equipment.waterUseEquipmentDefinition
          next if done[definition.handle.to_s]

          per_space_flows = typical_per_space_flows_gal_per_hr_crop(equipment, data)
          next if per_space_flows.empty?

          multiplier = equipment.space.get.multiplier
          flow_gal_per_hr = OpenStudio.convert(definition.peakFlowRate, 'm^3/s', 'gal/hr').get
          next unless per_space_flows.any? { |flow| (flow_gal_per_hr - (flow * multiplier)).abs <= 1e-6 * flow_gal_per_hr }

          definition.setPeakFlowRate(definition.peakFlowRate / multiplier)
          gpm = OpenStudio.convert(definition.peakFlowRate, 'm^3/s', 'gal/min').get.round(2)
          [definition, equipment].each { |obj| obj.setName(obj.nameString.sub(/[\d.]+gpm/, "#{gpm}gpm")) }
          done[definition.handle.to_s] = true
        end
      end

      # Typical peak flows (gal/hr) for one space, for the equipment rows that
      # upstream multiplies by the zone multiplier (per-area flows and One Per Unit).
      def typical_per_space_flows_gal_per_hr_crop(equipment, data)
        return [] unless equipment.space.is_initialized

        space = equipment.space.get
        return [] if space.multiplier <= 1 || !space.spaceType.is_initialized
        return [] if space.hasAdditionalProperties && space.additionalProperties.hasFeature('num_units')

        space_type = space.spaceType.get
        return [] unless space_type.standardsBuildingType.is_initialized && space_type.standardsSpaceType.is_initialized

        area_ft2 = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get
        rows = data[:space_types].select do |row|
          row[:building_type] == space_type.standardsBuildingType.get && row[:space_type] == space_type.standardsSpaceType.get
        end
        rows.flat_map { |row| row[:water_use_equipment] }.filter_map do |w|
          if w[:peak_flow_rate].to_f.zero? && w[:peak_flow_rate_per_area].to_f.positive?
            w[:peak_flow_rate_per_area].to_f * area_ft2
          elsif w[:loop_type] == 'One Per Unit' && w[:peak_flow_rate].to_f.positive?
            w[:peak_flow_rate].to_f
          end
        end
      end
    end
  end
end
