class ASHRAE9012007 < ASHRAE901
  # @!group Model

  # Determines which system number is used
  # for the baseline system.
  # @return [String] the system number: 1_or_2, 3_or_4,
  # 5_or_6, 7_or_8, 9_or_10
  def model_prm_baseline_system_number(model, climate_zone, area_type, fuel_type, area_ft2, num_stories, custom)
    sys_num = nil

    # @todo refactor: figure out this weird template switching case
    # For a custom scenario, use the lookup method from
    # a different standard instead of the specified standard.
    # if custom == "90.1-2007 with addenda dn"
    # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Custom; per Addenda dn of 90.1-2007, System 10 and 11 (same as system 9 and 10 in 90.1-2010) will be used for heated only space.')
    # template = '90.1-2010'
    # sys_num = model_prm_baseline_system_number(model, climate_zone, area_type, fuel_type, area_ft2, num_stories, custom)
    # return sys_num
    # end

    # Set the area limit
    limit_ft2 = 25_000

    # Warn about heated only
    if area_type == 'heatedonly'
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Per Table G3.1.10.d, '(In the proposed building) Where no cooling system exists or no cooling system has been specified, the cooling system shall be identical to the system modeled in the baseline building design.' This requires that you go back and add a cooling system to the proposed model.  This code cannot do that for you; you must do it manually.")
    end

    case area_type
    when 'residential'
      sys_num = '1_or_2'
    when 'nonresidential', 'heatedonly'
      # nonresidential and 3 floors or less and <25,000 ft2
      if num_stories <= 3 && area_ft2 < limit_ft2
        sys_num = '3_or_4'
      # nonresidential and 4 or 5 floors or 5 floors or less and 25,000 ft2 to 150,000 ft2
      elsif ((num_stories == 4 || num_stories == 5) && area_ft2 < limit_ft2) || (num_stories <= 5 && (area_ft2 >= limit_ft2 && area_ft2 <= 150_000))
        sys_num = '5_or_6'
      # nonresidential and more than 5 floors or >150,000 ft2
      elsif num_stories >= 5 || area_ft2 > 150_000
        sys_num = '7_or_8'
      end
    end

    return sys_num
  end

  def model_create_prm_any_baseline_building(user_model, building_type, climate_zone, hvac_building_type = 'All others', wwr_building_type = 'All others', swh_building_type = 'All others', model_deep_copy = false, custom = nil, sizing_run_dir = Dir.pwd, run_all_orients = false, unmet_load_hours_check = true, baseline_179d = true, debug = false)
    args = {
      # "user_model"   => user_model,
      'building_type' => building_type,
      'climate_zone' => climate_zone,
      'hvac_building_type' => hvac_building_type,
      'wwr_building_type' => wwr_building_type,
      'swh_building_type' => swh_building_type,
      'model_deep_copy' => model_deep_copy,
      'custom' => custom,
      'sizing_run_dir' => sizing_run_dir,
      'run_all_orients' => run_all_orients,
      'unmet_load_hours_check' => unmet_load_hours_check,
      'debug' => debug,
    }
    args.each { |k, v| OpenStudio.logFree(OpenStudio::Info, 'openstudio.prm.179d', "179d - model_create_prm_any_baseline_building inputs: #{k} - #{v}") }
    # system_type string
    prm_system_types = []

    # Check proposed model unmet load hours
    if unmet_load_hours_check
      # Run proposed model; need annual simulation to get unmet load hours
      if model_run_simulation_and_log_errors(user_model, run_dir = "#{sizing_run_dir}/PROP")
        umlh = model_get_unmet_load_hours(user_model)
        if umlh > 300
          OpenStudio.logFree(OpenStudio::Error, 'prm.log', "Proposed model unmet load hours exceed 300. Baseline model(s) won't be created.")
          raise "Proposed model unmet load hours exceed 300. Baseline model(s) won't be created."
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', 'Simulation failed. Check the model to make sure no severe errors.')
        raise 'Simulation on proposed model failed. Baseline generation is stopped.'
      end
    end

    # User data process
    # bldg_type_hvac_zone_hash could be an empty hash if all zones in the models are unconditioned
    bldg_type_hvac_zone_hash = {}
    ## Note for 179: replace from local to prm methods
    handle_user_input_data(user_model, climate_zone, hvac_building_type, wwr_building_type, swh_building_type, bldg_type_hvac_zone_hash)
    # Define different orientation from original orientation
    # for each individual baseline models
    # Need to run proposed model sizing simulation if no sql data is available
    pp "179d - bldg_type_hvac_zone_hash after handle_user_input_data: #{bldg_type_hvac_zone_hash.map { |k, v| "Key #{k} - Value: #{v}" }}"

    degs_from_org = run_all_orientations(run_all_orients, user_model) ? [0, 90, 180, 270] : [0]

    # Create baseline model for each orientation
    degs_from_org.each do |degs|
      # New baseline model:
      # Starting point is the original proposed model
      # Create a deep copy of the user model if requested
      model = model_deep_copy ? BTAP::FileIO.deep_copy(user_model) : user_model
      model.getBuilding.setName("#{template}-#{building_type}-#{climate_zone} PRM baseline created: #{Time.new}")

      # Rotate building if requested,
      # Site shading isn't rotated
      model_rotate(model, degs) unless degs == 0
      # Perform a sizing run of the proposed model.
      #
      # Among others, one of the goal is to get individual
      # space load to determine each space's conditioning
      # type: conditioned, unconditioned, semiheated.

      if model_create_prm_baseline_building_requires_proposed_model_sizing_run(model)
        # Set up some special reports to be used for baseline system selection later
        # Zone return air flows
        # ! no need for 90.1-2007
        node_list = []
        var_name = 'System Node Standard Density Volume Flow Rate'
        frequency = 'hourly'
        model.getThermalZones.each do |zone|
          port_list = zone.returnPortList
          port_list_objects = port_list.modelObjects
          port_list_objects.each do |node|
            node_name = node.nameString
            node_list << node_name
            output = OpenStudio::Model::OutputVariable.new(var_name, model)
            output.setKeyValue(node_name)
            output.setReportingFrequency(frequency)
          end
        end

        # air loop relief air flows
        var_name = 'System Node Standard Density Volume Flow Rate'
        frequency = 'hourly'
        model.getAirLoopHVACs.sort.each do |air_loop_hvac|
          relief_node = air_loop_hvac.reliefAirNode.get
          output = OpenStudio::Model::OutputVariable.new(var_name, model)
          output.setKeyValue(relief_node.nameString)
          output.setReportingFrequency(frequency)
        end

        # Run the sizing run
        if model_run_sizing_run(model, "#{sizing_run_dir}/SR_PROP#{degs}") == false
          return false
        end

        # Set baseline model space conditioning category based on proposed model
        model.getSpaces.each do |space|
          # Get conditioning category at the space level
          space_conditioning_category = space_conditioning_category(space)

          # Set space conditioning category
          space.additionalProperties.setFeature('space_conditioning_category', space_conditioning_category)
        end

        # The following should be done after a sizing run of the proposed model
        # because the proposed model zone design air flow is needed
        model_identify_return_air_type(model)
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prm.179d', '***179d === All non-HVAC alteration will be disabled***')
      # # Remove external shading devices
      # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Removing External Shading Devices ***')
      if baseline_179d
        model_remove_external_shading_devices(model)
      end

      # Reduce the WWR and SRR, if necessary
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adjusting Window and Skylight Ratios ***')
        success, wwr_info = model_apply_prm_baseline_window_to_wall_ratio(model, climate_zone, wwr_building_type: wwr_building_type)
        model_apply_prm_baseline_skylight_to_roof_ratio(model)
      end

      # Assign building stories to spaces in the building where stories are not yet assigned.
      model_assign_spaces_to_stories(model)

      # Modify the internal loads in each space type, keeping user-defined schedules.
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Changing Lighting Loads ***')
        model.getSpaceTypes.sort.each do |space_type|
          set_people = false
          set_lights = true
          set_electric_equipment = false
          set_gas_equipment = false
          set_ventilation = false
          set_infiltration = false
          # For PRM, it only applies lights for now.
          space_type_apply_internal_loads(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation, set_infiltration)
        end
      end

      # # Modify the lighting schedule to handle lighting occupancy sensors
      # # Modify the upper limit value of fractional schedule to avoid the fatal error caused by schedule value higher than 1
      # ! No light schedule change as it fixed wth ACM schedules
      # space_type_light_sch_change(model)
      # ! No exterior lighting schedule required
      # model_apply_baseline_exterior_lighting(model)

      # # Modify the elevator motor peak power
      # ! no need for 90.1-2007
      # model_add_prm_elevators(model)

      # # Calculate infiltration as per 90.1 PRM rules
      # ! return True for 90.1-2007 template
      # model_baseline_apply_infiltration_standard(model, climate_zone)

      # If any of the lights are missing schedules, assign an always-off schedule to those lights.
      # This is assumed to be the user's intent in the proposed model.
      model.getLightss.sort.each do |lights|
        if lights.schedule.empty?
          lights.setSchedule(model.alwaysOffDiscreteSchedule)
        end
      end

      # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adding Daylighting Controls ***')

      # Run a sizing run to calculate VLT for layer-by-layer windows.
      # TODO check if not required for 90.1-2007 full appnendix (only required for 90.1-2010)
      if baseline_179d
        if model_create_prm_baseline_building_requires_vlt_sizing_run(model) && (model_run_sizing_run(model, "#{sizing_run_dir}/SRVLT") == false)
          return false
        end
      end

      # # Add or remove daylighting controls to each space
      # # Add daylighting controls for 90.1-2013 and prior
      # # Remove daylighting control for 90.1-PRM-2019 and onward
      # ! check how daylighting required for 90.1-2007
      if baseline_179d
        model.getSpaces.sort.each do |space|
          space_set_baseline_daylighting_controls(space, false, false)
        end
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline Constructions ***')

      # Modify some of the construction types as necessary
      if baseline_179d
        model_apply_prm_construction_types(model)
      end

      # Get the groups of zones that define the baseline HVAC systems for later use.
      # This must be done before removing the HVAC systems because it requires knowledge of proposed HVAC fuels.
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Grouping Zones by Fuel Type and Occupancy Type ***')

      # 179d using local method with 90.1-2010
      # TODO test with warehouse and aparment midrise
      sys_groups = model_prm_baseline_system_groups(model, custom, bldg_type_hvac_zone_hash)
      # sys_groups.each_with_index do |system_group,i|
      #   system_group.each do |k,v|
      #     if k != "zones"
      #       pp "179d - system_group #{i}: #{k} - #{v}"
      #     else
      #       pp "179d - system_group #{i}: #{k} - #{v.map {|x| x.nameString}.join(":")}"
      #     end
      #   end
      # end

      # Also get hash of zoneName:boolean to record which zones have district heating, if any
      district_heat_zones = model_get_district_heating_zones(model)

      # Store occupancy and fan operation schedules for each zone before deleting HVAC objects name

      zone_fan_scheds = get_fan_schedule_for_each_zone(model)
      # ! 179D get ACM schedules directly without care
      zone_fan_scheds = get_fan_schedule_for_each_zone_179d(model, zone_fan_scheds) # update get_fan_schedule by name

      # Set the construction properties of all the surfaces in the model
      if baseline_179d
        model_apply_constructions(model, climate_zone, wwr_building_type, wwr_info)
      end

      # Update ground temperature profile (for F/C-factor construction objects)
      if baseline_179d
        model_update_ground_temperature_profile(model, climate_zone)
      end

      # Identify non-mechanically cooled systems if necessary
      model_identify_non_mechanically_cooled_systems(model)

      # Get supply, return, relief fan power for each air loop
      if model_get_fan_power_breakdown
        model.getAirLoopHVACs.sort.each do |air_loop|
          supply_fan_w = air_loop_hvac_get_supply_fan_power(air_loop)
          return_fan_w = air_loop_hvac_get_return_fan_power(air_loop)
          relief_fan_w = air_loop_hvac_get_relief_fan_power(air_loop)

          # Save fan power at the zone to determining
          # baseline fan power
          air_loop.thermalZones.sort.each do |zone|
            zone.additionalProperties.setFeature('supply_fan_w', supply_fan_w.to_f)
            zone.additionalProperties.setFeature('return_fan_w', return_fan_w.to_f)
            zone.additionalProperties.setFeature('relief_fan_w', relief_fan_w.to_f)
          end
        end
      end

      # Compute and marke DCV related information before deleting proposed model HVAC systems
      if baseline_179d
        model_mark_zone_dcv_existence(model)
        model_add_dcv_user_exception_properties(model)
        model_add_dcv_requirement_properties(model)
        model_add_apxg_dcv_properties(model)
        model_raise_user_model_dcv_errors(model)
      end

      # Remove all HVAC from model, excluding service water heating
      if baseline_179d
        model_remove_prm_hvac(model)
      end

      # Remove all EMS objects from the model
      model_remove_prm_ems_objects(model)
      # remove orphan object from DOE prototype
      if model.getMeterCustomDecrementByName('WIRED_INT_EQUIP').is_initialized
        model.getMeterCustomDecrementByName('WIRED_INT_EQUIP').get.remove
        pp 'Removed MeterCustomDecrement:WIRED_INT_EQUIP'
      end
      if model.getMeterCustomByName('Wired_LTG').is_initialized
        model.getMeterCustomByName('Wired_LTG').get.remove
        pp 'Removed MeterCustom:Wired_LTG'
      end
      model.getElectricLoadCenterTransformers.each do |ob|
        ob.remove
        pp "Removed Transformer #{ob.nameString}"
      end

      # Modify the service water heating loops per the baseline rules
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Cleaning up Service Water Heating Loops ***')
        model_apply_baseline_swh_loops(model, building_type)
      end

      # Determine the baseline HVAC system type for each of the groups of zones and add that system type.
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adding Baseline HVAC Systems ***')

        air_loop_name_array = []
        sys_groups.each_with_index do |sys_group, i|
          ## add data
          sys_group.each do |k, v|
            if k == 'zones'
              pp "179d - system_group #{i}: #{k} - #{v.map(&:nameString).join(':')}"
            else
              pp "179d - system_group #{i}: #{k} - #{v}"
            end
          end
          # Determine the primary baseline system type
          system_type = model_prm_baseline_system_type(model, climate_zone, sys_group, custom, hvac_building_type, district_heat_zones)
          # system_type --> ["PSZ_AC", "NaturalGas", nil, "Electricity"]
          # system_type[0] = "PTHP" ## force system type
          # system_type[0] = "PVAV_Reheat" ## force system type
          # system_type[0] = "VAV_PFP_Boxes" ## force system type
          # system_type[0] = "Gas_Furnace" ## force system type
          # system_type[0] = "Electric_Furnace" ## force system type
          prm_system_types << system_type
          system_str = system_type.zip(['type', 'central_heating_fuel', 'zone_heating_fuel', 'cooling_fuel']).map { |v, k| "#{k} => #{v}" }.join("\n")
          pp "179d - system_type: #{system_str}"

          sys_group['zones'].sort.each_slice(5) do |zone_list|
            zone_names = []
            zone_list.each do |zone|
              zone_names << zone.name.get.to_s
            end
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{zone_names.join(', ')}")
          end

          # Add system type reference to zone
          sys_group['zones'].sort.each do |zone|
            zone.additionalProperties.setFeature('baseline_system_type', system_type[0])
          end

          # Add the system type for these zones
          model_add_prm_baseline_system(model,
                                        system_type[0],
                                        system_type[1],
                                        system_type[2],
                                        system_type[3],
                                        sys_group['zones'],
                                        zone_fan_scheds)

          model.getAirLoopHVACs.each do |air_loop|
            air_loop_name = air_loop.name.get
            unless air_loop_name_array.include?(air_loop_name)
              air_loop.additionalProperties.setFeature('zone_group_type', sys_group['zone_group_type'] || 'None')
              air_loop.additionalProperties.setFeature('sys_group_occ', sys_group['occ'] || 'None')
              #  assign hvac_schedule directly not find from anywhere with air_loop_hvac_enable_unoccupied_fan_shutoff
              if !zone_fan_scheds.values.empty? && (zone_fan_scheds.values[0].is_a? String)
                air_loop.additionalProperties.setFeature('fan_sched_name', zone_fan_scheds.values[0])
              end

              air_loop_name_array << air_loop_name
            end

            # Determine return air type
            plenum, return_air_type = model_determine_baseline_return_air_type(model, system_type[0], air_loop.thermalZones)
            air_loop.thermalZones.sort.each do |zone|
              # Set up return air plenum
              zone.setReturnPlenum(model.getThermalZoneByName(plenum).get) if return_air_type == 'return_plenum'
            end
          end
        end
      end

      # Add system type reference to all air loops
      model.getAirLoopHVACs.sort.each do |air_loop|
        if air_loop.thermalZones[0].additionalProperties.hasFeature('baseline_system_type')
          sys_type = air_loop.thermalZones[0].additionalProperties.getFeatureAsString('baseline_system_type').get
          air_loop.additionalProperties.setFeature('baseline_system_type', sys_type)
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Thermal zone #{air_loop.thermalZones[0].name} is not associated to a particular system type.")
        end
      end

      # Set the zone sizing SAT for each zone in the model
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline HVAC System Sizing Settings ***')
      model.getThermalZones.each do |zone|
        thermal_zone_apply_prm_baseline_supply_temperatures(zone)
      end

      # Set the system sizing properties based on the zone sizing information
      model.getAirLoopHVACs.each do |air_loop|
        air_loop_hvac_apply_prm_sizing_temperatures(air_loop)
      end

      # Set internal load sizing run schedules
      # ! no need for 90.1-2007
      model_apply_prm_baseline_sizing_schedule(model)

      # Set the heating and cooling sizing parameters
      model_apply_prm_sizing_parameters(model)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline HVAC System Controls ***')

      # SAT reset, economizers
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_prm_baseline_controls(air_loop, climate_zone)
      end

      # Apply the baseline system water loop temperature reset control
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        plant_loop_apply_prm_baseline_temperatures(plant_loop)
      end

      # Run sizing run with the HVAC equipment
      if model_run_sizing_run(model, "#{sizing_run_dir}/SR1") == false
        return false
      end

      # Apply the minimum damper positions, assuming no DDC control of VAV terminals
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_minimum_vav_damper_positions(air_loop, false)
      end

      # If there are any multi-zone systems, reset damper positions to achieve a 60% ventilation effectiveness minimum for the system
      # following the ventilation rate procedure from 62.1
      model_apply_multizone_vav_outdoor_air_sizing(model)

      # Set the baseline fan power for all air loops
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_prm_baseline_fan_power(air_loop)
      end

      # Set the baseline fan power for all zone HVAC
      model.getZoneHVACComponents.sort.each do |zone_hvac|
        zone_hvac_component_apply_prm_baseline_fan_power(zone_hvac)
      end

      # Set the baseline number of boilers and chillers
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        plant_loop_apply_prm_number_of_boilers(plant_loop)
        plant_loop_apply_prm_number_of_chillers(plant_loop, sizing_run_dir)
      end

      # Set the baseline number of cooling towers
      # Must be done after all chillers are added
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        if baseline_179d
          plant_loop_apply_prm_number_of_cooling_towers(plant_loop)
        end
      end

      # Run sizing run with the new chillers, boilers, and cooling towers to determine capacities
      if model_run_sizing_run(model, "#{sizing_run_dir}/SR2") == false
        return false
      end

      # Set the pumping control strategy and power
      # Must be done after sizing components
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        if baseline_179d
          plant_loop_apply_prm_baseline_pump_power(plant_loop)
        end
        plant_loop_apply_prm_baseline_pumping_type(plant_loop)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Prescriptive HVAC Controls and Equipment Efficiencies ***')

      # Apply the HVAC efficiency standard -- !179D notes: autofan_turn_off apply to this one (both airLoop and ZoneHVAC)
      model_apply_hvac_efficiency_standard(model, climate_zone)

      # Set baseline DCV system
      model_set_baseline_demand_control_ventilation(model, climate_zone)

      # Final sizing run and adjustements to values that need refinement
      model_refine_size_dependent_values(model, sizing_run_dir)

      # Fix EMS references.
      # Temporary workaround for OS issue #2598
      model_temp_fix_ems_references(model)

      # Delete all the unused resource objects
      model_remove_unused_resource_objects(model)

      # Add reporting tolerances
      model_add_reporting_tolerances(model)

      # @todo: turn off self shading
      # Set Solar Distribution to MinimalShadowing... problem is when you also have detached shading such as surrounding buildings etc
      # It won't be taken into account, while it should: only self shading from the building itself should be turned off but to my knowledge there isn't a way to do this in E+

      model_status = degs > 0 ? "final_#{degs}" : 'final'
      model.save(OpenStudio::Path.new("#{sizing_run_dir}/#{model_status}.osm"), true)

      # Translate to IDF and save for debugging
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      idf = forward_translator.translateModel(model)
      idf_path = OpenStudio::Path.new("#{sizing_run_dir}/#{model_status}.idf")
      idf.save(idf_path, true)

      prm_system_type_str = prm_system_types.uniq.map { |x| x[0] }.uniq.join('***')
      model.getBuilding.additionalProperties.setFeature('prm_baseline_system_type', prm_system_type_str)

      # Check unmet load hours # disable for 179d
      if unmet_load_hours_check
        nb_adjustments = 0
        loop do
          model_run_simulation_and_log_errors(model, "#{sizing_run_dir}/final#{degs}") == false
          # If UMLH are greater than the threshold allowed by Appendix G,
          # increase zone air flow and load as per the recommendation in
          # the PRM-RM; Note that the PRM-RM only suggest to increase
          # air zone air flow, but the zone sizing factor in EnergyPlus
          # increase both air flow and load.
          if model_get_unmet_load_hours(model) > 300
            # Limit the number of zone sizing factor adjustment to 8
            unless nb_adjustments < 8
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "After 8 rounds of zone sizing factor adjustments the unmet load hours for the baseline model (#{degs} degree of rotation) still exceed 300 hours. Please open an issue on GitHub (https://github.com/NREL/openstudio-standards/issues) and share your user model with the developers.")
              break
            end
            model.getThermalZones.each do |thermal_zone|
              # Cooling adjustments
              clg_umlh = thermal_zone_get_unmet_load_hours(thermal_zone, 'Cooling')
              if clg_umlh > 50
                # Get zone cooling sizing factor
                if thermal_zone.sizingZone.zoneCoolingSizingFactor.is_initialized
                  sizing_factor = thermal_zone.sizingZone.zoneCoolingSizingFactor.get
                else
                  sizing_factor = 1.0
                end

                # Make adjustment to zone cooling sizing factor
                # Do not adjust factors greater or equal to 2
                if sizing_factor < 2.0
                  if clg_umlh > 150
                    sizing_factor *= 1.1
                  elsif clg_umlh > 50
                    sizing_factor *= 1.05
                  end
                  thermal_zone.sizingZone.setZoneCoolingSizingFactor(sizing_factor)
                end
              end

              # Heating adjustments
              htg_umlh = thermal_zone_get_unmet_load_hours(thermal_zone, 'Heating')
              if htg_umlh > 50
                # Get zone cooling sizing factor
                if thermal_zone.sizingZone.zoneHeatingSizingFactor.is_initialized
                  sizing_factor = thermal_zone.sizingZone.zoneHeatingSizingFactor.get
                else
                  sizing_factor = 1.0
                end

                # Make adjustment to zone heating sizing factor
                # Do not adjust factors greater or equal to 2
                if sizing_factor < 2.0
                  if htg_umlh > 150
                    sizing_factor *= 1.1
                  elsif htg_umlh > 50
                    sizing_factor *= 1.05
                  end
                  thermal_zone.sizingZone.setZoneHeatingSizingFactor(sizing_factor)
                end
              end
            end
          else
            break
          end
        end
      end
    end

    if debug
      generate_baseline_log(sizing_run_dir)
    end

    return true
  end
end
