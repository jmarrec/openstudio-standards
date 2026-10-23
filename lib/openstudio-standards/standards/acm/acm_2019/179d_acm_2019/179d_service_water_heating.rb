# 179D override for typical service water heating (SWH).
# openstudio-standards 0.8.2 puts the zone multiplier in the SWH peak flow, and
# EnergyPlus applies the zone multiplier again. These methods are copies of the
# fixed upstream methods in service_water_heating/create_typical.rb and
# service_water_heating/information.rb. Remove this file when the
# openstudio-standards gem has the fix.
module OpenstudioStandards
  module ServiceWaterHeating
    # add typical swh demand and supply to model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param water_heating_fuel [String] water heater fuel. Valid choices are NaturalGas, Electricity, and HeatPump.
    #   If not supplied, a smart default will be determined based on building type and loop type.
    # @param circulating [Boolean] determine whether the system is circulating (true), noncirculating (false).
    #   A nil value will default based on the standards building type
    # @return [Array<OpenStudio::Model::PlantLoop>] array of service hot water loops
    # @todo add support for other loop configurations, such as by space type, space type adjacent, or building type
    def self.create_typical_service_water_heating(model,
                                                  water_heating_fuel: nil,
                                                  circulating: nil)
      # array of service hot water loops
      swh_systems = []

      # water use equipment on the building loop
      shared_water_use_equipment = []
      booster_water_use_equipment = []

      # @todo remove once model_add_schedule is refactored
      std = Standard.build('90.1-2013')

      # loop through space types adding demand side of swh
      model.getSpaces.sort.each do |space|
        next unless space.spaceType.is_initialized

        # EnergyPlus applies the zone multiplier to water use equipment in the space,
        # so the peak flow uses the area of one space. Water heater sizing includes the multiplier.
        total_space_floor_area_m2 = space.floorArea
        zone_multiplier = space.multiplier
        total_space_floor_area_ft2 = OpenStudio.convert(total_space_floor_area_m2, 'm^2', 'ft^2').get
        space_type = space.spaceType.get

        next unless space_type.standardsSpaceType.is_initialized
        next unless space_type.standardsBuildingType.is_initialized

        standards_space_type = space_type.standardsSpaceType.get
        standards_building_type = space_type.standardsBuildingType.get

        # load typical water use equipment data
        # The data file is next to the upstream SWH code, not next to this override
        swh_dir = File.dirname(method(:create_water_use).source_location.first)
        data = JSON.parse(File.read("#{swh_dir}/data/typical_water_use_equipment.json"), symbolize_names: true)
        space_type_properties = data[:space_types].select { |hash| (hash[:space_type] == standards_space_type) && (hash[:building_type] == standards_building_type) }

        # skip spaces with no equipment defined
        next if space_type_properties.empty?

        water_use_equipment = space_type_properties[0][:water_use_equipment]

        # store one per unit equipment
        space_water_use_equipment = []

        if space.hasAdditionalProperties && space.additionalProperties.hasFeature('num_units')
          num_units = space.additionalProperties.getFeatureAsInteger('num_units').get
        else # assume 1 space is 1 unit
          num_units = 1
        end

        # loop through and add water use equipment to space
        water_use_equipment.each do |w|
          # get water use equipment properties
          water_use_name = w[:equipment_name]
          peak_flow_rate_gal_per_hr = w[:peak_flow_rate].to_f
          peak_flow_rate_gal_per_hr_per_ft2 = w[:peak_flow_rate_per_area].to_f
          loop_type = w[:loop_type]
          temperature = w[:temperature]
          flow_rate_schedule = w[:flow_rate_schedule]
          sensible_fraction = w[:sensible_fraction]
          latent_fraction = w[:latent_fraction]

          # derived from equipment properties
          is_booster = water_use_name && water_use_name.downcase.include?('booster')
          water_use_name = water_use_name ? "#{space.name} #{water_use_name}" : "#{space.name} Water Use"
          service_water_temperature_c = OpenStudio.convert(temperature, 'F', 'C').get

          # @todo replace this line once model_add_schedule is refactored to not require a standard
          flow_rate_schedule = std.model_add_schedule(model, flow_rate_schedule)

          # skip undefined equipment
          next unless peak_flow_rate_gal_per_hr > 0.0 || peak_flow_rate_gal_per_hr_per_ft2 > 0.0

          # If there is no SWH schedule, assume no SWH use for this space type.
          unless flow_rate_schedule
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', "No service water heating schedule was specified for space type #{space_type.name} with standards space type #{standards_space_type}. Assuming an always off schedule.")
            flow_rate_schedule = model.alwaysOffDiscreteSchedule
          end

          # Determine the peak flow rate and default water heating fuel
          case loop_type
          when 'One Per Unit'
            # calculate peak flow rate
            if peak_flow_rate_gal_per_hr.zero? && peak_flow_rate_gal_per_hr_per_ft2 > 0.0
              peak_flow_rate_gal_per_hr = num_units * peak_flow_rate_gal_per_hr_per_ft2 * total_space_floor_area_ft2
            else
              peak_flow_rate_gal_per_hr *= num_units
            end

            # update water use name
            water_use_name = "#{water_use_name} #{num_units} unit(s)"
          else
            # calculate peak flow rate
            if peak_flow_rate_gal_per_hr.zero? && peak_flow_rate_gal_per_hr_per_ft2 > 0.0
              peak_flow_rate_gal_per_hr = peak_flow_rate_gal_per_hr_per_ft2 * total_space_floor_area_ft2
            end
          end

          # convert to SI
          peak_flow_rate_m3_per_s = OpenStudio.convert(peak_flow_rate_gal_per_hr, 'gal/hr', 'm^3/s').get

          # create water use equipment
          water_use_equip = OpenstudioStandards::ServiceWaterHeating.create_water_use(model,
                                                                                      name: water_use_name,
                                                                                      flow_rate: peak_flow_rate_m3_per_s,
                                                                                      flow_rate_fraction_schedule: flow_rate_schedule,
                                                                                      water_use_temperature: service_water_temperature_c,
                                                                                      sensible_fraction: sensible_fraction,
                                                                                      latent_fraction: latent_fraction,
                                                                                      space: space)

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added water use equipment #{water_use_equip.name}")

          # create service hot water loop for 'One Per Space' and 'One Per Unit' dedicated equipment
          case loop_type
          when 'Shared'
            if is_booster
              booster_water_use_equipment << water_use_equip
            else
              shared_water_use_equipment << water_use_equip
            end
          when 'One Per Space', 'One Per Unit'
            space_water_use_equipment << water_use_equip
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', "Water use equipment service loop type #{loop_type} not recognized. Cannot attach equipment to a loop.")
          end
        end

        # create water loop for 'One Per Space' and 'One Per Unit' equipment
        unless space_water_use_equipment.empty?
          water_heater_capacity_w = num_units * zone_multiplier * OpenStudio.convert(20.0, 'kBtu/hr', 'W').get
          water_heater_volume_m3 = num_units * zone_multiplier * OpenStudio.convert(50.0, 'gal', 'm^3').get
          num_water_heaters = num_units * zone_multiplier

          # default to electricity for single units
          dedicated_water_heating_fuel = water_heating_fuel || 'Electricity'

          # @todo add method to get service water temperature as max of space_water_use_equipment
          service_water_temperature_c = OpenStudio.convert(140.0, 'F', 'C').get

          # add service water loop with water heater
          swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                system_name: "#{space.name} Service Water Loop",
                                                                                                service_water_temperature: service_water_temperature_c,
                                                                                                service_water_pump_head: 0.01,
                                                                                                service_water_pump_motor_efficiency: 1.0,
                                                                                                water_heater_capacity: water_heater_capacity_w,
                                                                                                water_heater_volume: water_heater_volume_m3,
                                                                                                water_heater_fuel: dedicated_water_heating_fuel,
                                                                                                number_of_water_heaters: num_water_heaters,
                                                                                                add_piping_losses: true,
                                                                                                floor_area: total_space_floor_area_m2,
                                                                                                number_of_stories: 1)

          # add loop to array
          swh_systems << swh_loop

          # Attach water use equipment to the loop
          space_water_use_equipment.each do |water_use_equip|
            swh_connection = water_use_equip.waterUseConnections
            swh_loop.addDemandBranchForComponent(swh_connection.get) if swh_connection.is_initialized
          end
        end
      end

      ############################################################################

      # default to gas for shared system types and booster systems
      shared_water_heating_fuel = water_heating_fuel || 'NaturalGas'
      booster_water_heating_fuel = water_heating_fuel || 'Electricity'

      # @todo get maximum service water temperature from shared_water_use_equipment
      water_heater_temp_f = 140.0
      water_heater_temp_c = OpenStudio.convert(water_heater_temp_f, 'F', 'C').get

      # defaults for circulating or noncirculating systems
      # @todo Remove hard-coded building-type-based lookups for circulating vs. non-circulating SWH systems
      if circulating.nil?
        if model.getBuilding.standardsBuildingType.is_initialized
          circulating = OpenstudioStandards::ServiceWaterHeating.circulating_building_type?(model.getBuilding.standardsBuildingType.get)
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', 'Unable to determine the standards building type. Assuming the building does not have a circulating service water heating loop.')
          circulating = false
        end
      end

      # create a shared water loop
      unless shared_water_use_equipment.empty? && booster_water_use_equipment.empty?
        if circulating
          # Table A.2 in PrototypeModelEnhancements_2014_0.pdf shows 10ft on everything except SecondarySchool which has 11.4ft
          service_water_pump_head_pa = OpenStudio.convert(10.0, 'ftH_{2}O', 'Pa').get
          service_water_pump_motor_efficiency = 0.3
        else
          service_water_pump_head_pa = 0.01
          service_water_pump_motor_efficiency = 1.0
        end

        water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(shared_water_use_equipment)
        water_heater_capacity_w = water_heater_sizing[:water_heater_capacity]
        water_heater_volume_m3 = water_heater_sizing[:water_heater_volume]

        # Add a shared service water heating loop with water heater
        shared_swh_loop = OpenstudioStandards::ServiceWaterHeating.create_service_water_heating_loop(model,
                                                                                                     system_name: 'Shared Service Water Loop',
                                                                                                     service_water_temperature: water_heater_temp_c,
                                                                                                     service_water_pump_head: service_water_pump_head_pa,
                                                                                                     service_water_pump_motor_efficiency: service_water_pump_motor_efficiency,
                                                                                                     water_heater_capacity: water_heater_capacity_w,
                                                                                                     water_heater_volume: water_heater_volume_m3,
                                                                                                     water_heater_fuel: shared_water_heating_fuel,
                                                                                                     add_piping_losses: true)

        # Add loop to array
        swh_systems << shared_swh_loop

        # Attach all water use equipment to the shared loop
        shared_water_use_equipment.sort.each do |water_use_equip|
          swh_connection = water_use_equip.waterUseConnections
          shared_swh_loop.addDemandBranchForComponent(swh_connection.get) if swh_connection.is_initialized
        end

        # Attach booster water heater loop to shared loop
        unless booster_water_use_equipment.empty?
          # find_water_heater_capacity_volume_and_parasitic
          booster_water_heater_sizing = OpenstudioStandards::ServiceWaterHeating.water_heater_sizing_from_water_use_equipment(booster_water_use_equipment,
                                                                                                                              water_heater_efficiency: 1.0,
                                                                                                                              inlet_temperature: 140.0,
                                                                                                                              supply_temperature: 180.0)

          # Note that booster water heaters are always assumed to be electric resistance
          booster_water_temperature_c = OpenStudio.convert(180.0, 'F', 'C').get
          swh_booster_loop = OpenstudioStandards::ServiceWaterHeating.create_booster_water_heating_loop(model,
                                                                                                        system_name: 'Booster Water Loop',
                                                                                                        water_heater_capacity: booster_water_heater_sizing[:water_heater_capacity],
                                                                                                        service_water_temperature: booster_water_temperature_c,
                                                                                                        service_water_loop: shared_swh_loop)

          # Add loop to array
          swh_systems << swh_booster_loop

          # Attach booster water use equipment to the booster loop
          booster_water_use_equipment.each do |booster_equip|
            booster_swh_connection = booster_equip.waterUseConnections
            swh_booster_loop.addDemandBranchForComponent(booster_swh_connection.get) if booster_swh_connection.is_initialized
          end
        end
      end

      return swh_systems
    end

    # Determines water heater capacity and volume from an array of water use equipment.
    #
    # @param water_use_equipment_array [Array<OpenStudio::Model::WaterUseEquipment>] Array of water use equipment objects served by this water heater
    # @param capacity_to_volume_ratio [Double] storage volume in gallons per kBtu/hr of capacity
    # @param water_heater_efficiency [Double] water heater thermal efficiency, fraction
    # @param inlet_temperature [Double] inlet cold water temperature, degrees Fahrenheit
    # @param supply_temperature [Double] supply water temperature from the tank, degrees Fahrenheit
    # @param peak_flow_fraction [Double] a variable for system diversity as fraction of peak flow when setting water heater capacity
    # @param minimum_volume [Double] minimum allowable volume of the water heater, in gallons
    # @return [Hash] hash with water_heater_capacity in watts and water_heater_volume in m^3
    def self.water_heater_sizing_from_water_use_equipment(water_use_equipment_array,
                                                          capacity_to_volume_ratio: 1.0,
                                                          water_heater_efficiency: 0.8,
                                                          inlet_temperature: 40.0,
                                                          supply_temperature: 140.0,
                                                          peak_flow_fraction: 1.0,
                                                          minimum_volume: 40.0)
      # Initialize hash
      water_heater_sizing = {}

      # Get the maximum flow rates for all pieces of water use equipment
      adjusted_max_flow_rates_gal_per_hr = []
      water_use_equipment_array.sort.each do |water_use_equip|
        water_use_equip_sch = water_use_equip.flowRateFractionSchedule
        next if water_use_equip_sch.empty?

        water_use_equip_sch = water_use_equip_sch.get
        max_sch_value = OpenstudioStandards::Schedules.schedule_get_min_max(water_use_equip_sch)['max']

        # Get peak flow rate from water use equipment definition
        peak_flow_rate_m3_per_s = water_use_equip.waterUseEquipmentDefinition.peakFlowRate

        # EnergyPlus applies the zone multiplier to water use equipment in a space, so include it here
        zone_multiplier = 1
        if water_use_equip.space.is_initialized && water_use_equip.space.get.thermalZone.is_initialized
          zone_multiplier = water_use_equip.space.get.thermalZone.get.multiplier
        end

        # Calculate adjusted flow rate based on the peak fraction found in the flow rate fraction schedule
        adjusted_peak_flow_rate_m3_per_s = max_sch_value * peak_flow_rate_m3_per_s * zone_multiplier
        adjusted_max_flow_rates_gal_per_hr << OpenStudio.convert(adjusted_peak_flow_rate_m3_per_s, 'm^3/s', 'gal/hr').get
      end

      # Sum gph values from water use equipment to use in formula
      total_adjusted_flow_rate_gal_per_hr = adjusted_max_flow_rates_gal_per_hr.sum

      # Calculate capacity based on analysis of combined water use equipment maximum flow rates and schedules
      # Max gal/hr * 8.4 lb/gal * 1 Btu/lb F * (120F - 40F)/0.8 = Btu/hr
      water_heater_capacity_btu_per_hr = peak_flow_fraction * total_adjusted_flow_rate_gal_per_hr * 8.4 * 1.0 * (supply_temperature - inlet_temperature) / water_heater_efficiency
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Capacity of #{water_heater_capacity_btu_per_hr.round} Btu/hr = #{peak_flow_fraction} peak fraction * #{total_adjusted_flow_rate_gal_per_hr.round} gal/hr * 8.4 lb/gal * 1.0 Btu/lb F * (#{supply_temperature.round} - #{inlet_temperature.round} deltaF / #{water_heater_efficiency} htg eff).")
      water_heater_capacity_w = OpenStudio.convert(water_heater_capacity_btu_per_hr, 'Btu/hr', 'W').get

      # Calculate volume based on capacity
      # A.1.4 Total Storage Volume and Water Heater Capacity of PrototypeModelEnhancements_2014_0.pdf shows 1 gallon of storage to 1 kBtu/h of capacity
      water_heater_capacity_kbtu_per_hr = OpenStudio.convert(water_heater_capacity_btu_per_hr, 'Btu/hr', 'kBtu/hr').get
      water_heater_volume_gal = water_heater_capacity_kbtu_per_hr * capacity_to_volume_ratio

      # increase tank size to the minimum volume if calculated value is smaller
      water_heater_volume_gal = minimum_volume if water_heater_volume_gal < minimum_volume # gal
      water_heater_volume_m3 = OpenStudio.convert(water_heater_volume_gal, 'gal', 'm^3').get

      # Populate return hash
      water_heater_sizing[:water_heater_capacity] = water_heater_capacity_w
      water_heater_sizing[:water_heater_volume] = water_heater_volume_m3

      return water_heater_sizing
    end
  end
end
