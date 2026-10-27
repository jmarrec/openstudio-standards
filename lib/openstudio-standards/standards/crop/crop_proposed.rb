require_relative 'crop_common'
require_relative 'crop_winter_solar_design_day'

# Steps for the proposed pass only: warehouse 62.1 ventilation and exhaust make-up mixing in
# create_typical, and the proposed normalization with its system-type tags and reheat fixes.
module CropProposed
  HOT_CLIMATE_ZONES = ['0A', '0B', '1A', '1B', '2A', '2B', '3A'].freeze

  EXHAUST_ZONE_HIGH_REHEAT_DESIGN_SAT_C = 50.0

  REHEAT_HIGH_OCC_MIN_DENSITY_PPL_PER_M2 = 0.269
  REHEAT_HIGH_OCC_MIN_PEOPLE = 50.0

  ASHRAE_62_1_2019_WAREHOUSE_VENTILATION_IP = {
    'Bulk' => { cfm_per_person: 10.0, cfm_per_ft2: 0.06 },
    'Fine' => { cfm_per_person: 10.0, cfm_per_ft2: 0.06 },
    'Office' => { cfm_per_person: 5.0, cfm_per_ft2: 0.06 },
  }.freeze

  # Why: proposed models must keep claimed equipment/LPD choices while matching
  # baseline-grade neutral HVAC controls.
  # What: normalizes retained proposed HVAC without rebuilding it or applying
  # standard equipment efficiency.
  # How: calls vanilla PRM methods through prm_standard, with CROP hooks around
  # DCV, exhaust makeup, and reheat fixes. Infiltration and heated-only
  # ventilation are added earlier by create_typical_building_from_model_comstock.
  # Used by: the HVAC-control measure for PRM-2019 proposed normalization.
  def model_create_crop_proposed_normalization(model, climate_zone, hvac_building_type = 'other nonresidential', sizing_run_dir = Dir.pwd, _debug: false, prm_standard: Standard.build(CropCommon::PRM_2019_TEMPLATE))
    prm_standard = prepare_prm_standard_for_crop_overrides(prm_standard)
    prm_standard.instance_variable_set(:@sizing_run_dir, sizing_run_dir)
    ensure_baseline_system_type_tags(model, climate_zone, hvac_building_type)

    prm_call(prm_standard, :model_identify_non_mechanically_cooled_systems, model)
    if prm_call(prm_standard, :model_get_fan_power_breakdown)
      model.getAirLoopHVACs.sort.each do |air_loop|
        supply_fan_w = prm_call(prm_standard, :air_loop_hvac_get_supply_fan_power, air_loop)
        return_fan_w = prm_call(prm_standard, :air_loop_hvac_get_return_fan_power, air_loop)
        relief_fan_w = prm_call(prm_standard, :air_loop_hvac_get_relief_fan_power, air_loop)
        air_loop.thermalZones.sort.each do |zone|
          zone.additionalProperties.setFeature('supply_fan_w', supply_fan_w.to_f)
          zone.additionalProperties.setFeature('return_fan_w', return_fan_w.to_f)
          zone.additionalProperties.setFeature('relief_fan_w', relief_fan_w.to_f)
        end
      end
    end

    unless model.sqlFile.is_initialized || prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-DCV-PREPASS")
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model',
                         'PROP-DCV-PREPASS sizing run failed; DCV requirements will be evaluated without sizing SQL.')
    end
    prm_call(prm_standard, :model_evaluate_dcv_requirements, model)

    model.getThermalZones.each { |zone| prm_call(prm_standard, :thermal_zone_apply_prm_baseline_supply_temperatures, zone) }
    apply_exhaust_zone_higher_reheat_design_sat(model)
    model.getAirLoopHVACs.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_sizing_temperatures, air_loop) }
    prm_call(prm_standard, :model_apply_prm_baseline_sizing_schedule, model)
    prm_call(prm_standard, :model_apply_prm_sizing_parameters, model).tap { CropWinterSolarDesignDay.model_add_hot_climate_winter_solar_design_day(model, climate_zone) }

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_baseline_controls, air_loop, climate_zone) }
    apply_heated_only_storage_economizer_override(model, hvac_building_type)
    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_temperatures, plant_loop)
    end

    return false unless prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-SR1")

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_minimum_vav_damper_positions, air_loop, false) }
    apply_exhaust_zone_fixed_minimum_airflow(model)
    prm_call(prm_standard, :model_apply_multizone_vav_outdoor_air_sizing, model)

    model.getAirLoopHVACs.sort.each { |air_loop| prm_call(prm_standard, :air_loop_hvac_apply_prm_baseline_fan_power, air_loop) }
    model.getZoneHVACComponents.sort.each { |zone_hvac| prm_call(prm_standard, :zone_hvac_component_apply_prm_baseline_fan_power, zone_hvac) }

    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_boilers, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_chillers, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_number_of_cooling_towers, plant_loop)
    end

    return false unless prm_call(prm_standard, :model_run_sizing_run, model, "#{sizing_run_dir}/PROP-SR2")

    each_non_swh_plant_loop(model, prm_standard:) do |plant_loop|
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_pump_power, plant_loop)
      prm_call(prm_standard, :plant_loop_apply_prm_baseline_pumping_type, plant_loop)
    end

    prm_call(prm_standard, :model_set_baseline_demand_control_ventilation, model, climate_zone)
    prm_call(prm_standard, :model_refine_size_dependent_values, model, sizing_run_dir)
    prm_call(prm_standard, :model_temp_fix_ems_references, model)
    prm_call(prm_standard, :model_remove_unused_resource_objects, model)
    prm_call(prm_standard, :model_add_reporting_tolerances, model)
    apply_heated_only_storage_economizer_override(model, hvac_building_type)
    apply_exhaust_zone_reheat_coil_capacity_floor(model)
    apply_reheat_max_air_temperature_headroom(model)
    apply_reheat_max_flow_during_reheat(model)

    true
  end

  # Schedule for the make-up mixing. Nil means: follow the exhaust fan.
  # The ACM overlay overrides this method.
  def exhaust_makeup_mixing_schedule(_model, building_type: nil); end

  # Why: exhaust zones should be balanced by transfer air, not extra outdoor
  # infiltration.
  # What: adds ZoneMixing from an adjacent conditioned zone to each exhaust
  # zone and marks exhaust fans as balanced.
  # How: sizes mixing to each fan maximum flow. The schedule comes from
  # exhaust_makeup_mixing_schedule, else it is the fan availability schedule.
  # Used by: create-typical after the exhaust fans are added.
  def apply_exhaust_makeup_zone_mixing(model, building_type: nil)
    fans = model.getFanZoneExhausts
    return if fans.empty?

    schedule = exhaust_makeup_mixing_schedule(model, building_type:)

    fans.each do |fan|
      next unless fan.thermalZone.is_initialized
      next unless fan.maximumFlowRate.is_initialized

      zone = fan.thermalZone.get
      next unless zone.spaces.any? do |space|
        space_type = space.spaceType
        space_type.is_initialized && CropCommon::EXHAUST_ZONE_SPACE_TYPES.include?(space_type.get.standardsSpaceType.to_s)
      end

      source_zone = exhaust_zone_makeup_source_zone(zone)
      if source_zone.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', "No adjacent conditioned zone found to supply makeup air for exhaust zone '#{zone.name}'.")
        next
      end

      fan.setBalancedExhaustFractionSchedule(model.alwaysOnDiscreteSchedule)
      mixing_name = "#{fan.name} Makeup mixing"
      next if model.getZoneMixings.any? { |zone_mixing| zone_mixing.nameString == mixing_name }

      max_flow_m3s = fan.maximumFlowRate.get
      mixing = OpenStudio::Model::ZoneMixing.new(zone)
      mixing.setName(mixing_name)
      mixing.setSourceZone(source_zone)
      mixing.setDesignFlowRate(max_flow_m3s)
      availability_schedule = fan.availabilitySchedule
      mixing.setSchedule(schedule || (availability_schedule.is_initialized ? availability_schedule.get : model.alwaysOnDiscreteSchedule))

      OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Added makeup ZoneMixing '#{mixing.name}' drawing from '#{source_zone.name}' into '#{zone.name}'.")
    end
  end

  # Why: exhaust makeup transfer air needs a plausible conditioned source zone.
  # What: selects the largest conditioned neighboring zone.
  # How: walks matched interior surfaces and filters neighbors with thermostats.
  # Used by: apply_exhaust_makeup_zone_mixing.
  def exhaust_zone_makeup_source_zone(zone)
    neighbors = {}
    zone.spaces.each do |space|
      space.surfaces.each do |surface|
        adjacent_surface = surface.adjacentSurface
        next unless adjacent_surface.is_initialized

        adjacent_space = adjacent_surface.get.space
        next unless adjacent_space.is_initialized

        candidate = adjacent_space.get.thermalZone
        next unless candidate.is_initialized

        candidate_zone = candidate.get
        next if candidate_zone.handle == zone.handle
        next unless candidate_zone.thermostat.is_initialized

        neighbors[candidate_zone.handle] = candidate_zone
      end
    end
    neighbors.values.max_by(&:floorArea)
  end

  # Applies the 62.1-2019 Table 6-1 rates to Warehouse DSOAs.
  def model_apply_ashrae_62_1_2019_warehouse_ventilation(model)
    updated = 0
    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized
      next unless space_type.standardsBuildingType.get == 'Warehouse'
      next unless space_type.standardsSpaceType.is_initialized

      rates = ASHRAE_62_1_2019_WAREHOUSE_VENTILATION_IP[space_type.standardsSpaceType.get]
      next if rates.nil?

      dsoa = space_type.designSpecificationOutdoorAir
      raise "Warehouse space type '#{space_type.nameString}' is missing a design specification outdoor air object." unless dsoa.is_initialized

      dsoa = dsoa.get
      dsoa.setOutdoorAirFlowperPerson(OpenStudio.convert(rates[:cfm_per_person], 'ft^3/min*person', 'm^3/s*person').get)
      dsoa.setOutdoorAirFlowperFloorArea(OpenStudio.convert(rates[:cfm_per_ft2], 'ft^3/min*ft^2', 'm^3/s*m^2').get)
      updated += 1
    end

    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Applied 62.1-2019 ventilation rates to #{updated} Warehouse space type(s).")
    updated.positive?
  end

  # Why: exhaust-zone VAV terminals need enough reheat temperature for pinned minimum
  # airflow.
  # What: raises zone heating design SAT for exhaust VAV:Reheat zones.
  # How: sets the sizing-zone heating design supply temperature before PRM sizing.
  # Used by: proposed normalization before sizing runs.
  def apply_exhaust_zone_higher_reheat_design_sat(model)
    model.getThermalZones.each do |zone|
      next unless exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      zone.sizingZone.setZoneHeatingDesignSupplyAirTemperature(EXHAUST_ZONE_HIGH_REHEAT_DESIGN_SAT_C)
    end
  end

  # Why: PRM minimum-damper logic can undo exhaust-matched VAV minimum airflow.
  # What: pins exhaust-zone VAV minimum flow to the zone exhaust design flow.
  # How: sets FixedFlowRate on VAV:Reheat terminals serving exhaust zones.
  # Used by: proposed normalization after PRM minimum-damper adjustment.
  def apply_exhaust_zone_fixed_minimum_airflow(model)
    model.getThermalZones.each do |zone|
      next unless exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      exhaust_m3s = zone_exhaust_maximum_flow_rate(zone)
      next if exhaust_m3s <= 0.0

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      vav_terminal.setZoneMinimumAirFlowInputMethod('FixedFlowRate')
      vav_terminal.setFixedMinimumAirFlowRate(exhaust_m3s)
    end
  end

  # Why: autosized reheat coils can be too small for the exhaust-zone minimum supply.
  # What: floors hot-water reheat coil capacity for exhaust-zone VAV terminals.
  # How: computes a capacity floor from exhaust flow, air heat capacity, and SAT
  # lift, then raises capacity and water flow only when needed.
  # Used by: proposed normalization after sizing runs.
  def apply_exhaust_zone_reheat_coil_capacity_floor(model)
    rho_air = 1.2
    cp_air = 1005.0
    cooling_sat_c = 12.8889
    sizing_factor = 1.25

    model.getThermalZones.each do |zone|
      next unless exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      exhaust_m3s = zone_exhaust_maximum_flow_rate(zone)
      next if exhaust_m3s <= 0.0

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      heating_coil = vav_terminal.reheatCoil.to_CoilHeatingWater
      next unless heating_coil.is_initialized

      coil = heating_coil.get
      target_capacity_w = exhaust_m3s * rho_air * cp_air * (EXHAUST_ZONE_HIGH_REHEAT_DESIGN_SAT_C - cooling_sat_c) * sizing_factor
      current_capacity_w = if coil.ratedCapacity.is_initialized
                             coil.ratedCapacity.get
                           elsif coil.autosizedRatedCapacity.is_initialized
                             coil.autosizedRatedCapacity.get
                           end
      next unless current_capacity_w.nil? || current_capacity_w < target_capacity_w

      coil.setRatedCapacity(target_capacity_w)
      next unless current_capacity_w&.positive?

      current_water_m3s = if coil.maximumWaterFlowRate.is_initialized
                            coil.maximumWaterFlowRate.get
                          elsif coil.autosizedMaximumWaterFlowRate.is_initialized
                            coil.autosizedMaximumWaterFlowRate.get
                          end
      coil.setMaximumWaterFlowRate(current_water_m3s * target_capacity_w / current_capacity_w) if current_water_m3s
    end
  end

  # Why: high-occupancy non-exhaust zones may need full damper opening during reheat
  # recovery.
  # What: sets MaximumFlowFractionDuringReheat to 1.0 on qualifying terminals.
  # How: filters to non-exhaust VAV:Reheat hot-water terminals with high people load.
  # Used by: proposed normalization near final cleanup.
  def apply_reheat_max_flow_during_reheat(model)
    model.getThermalZones.each do |zone|
      next if exhaust_zone?(zone)

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      next unless vav_terminal.reheatCoil.to_CoilHeatingWater.is_initialized
      next unless zone.floorArea.positive?

      people_density = zone.numberOfPeople / zone.floorArea
      next unless people_density >= REHEAT_HIGH_OCC_MIN_DENSITY_PPL_PER_M2 && zone.numberOfPeople >= REHEAT_HIGH_OCC_MIN_PEOPLE

      vav_terminal.setMaximumFlowFractionDuringReheat(1.0)
    end
  end

  # Why: PRM apply methods expect baseline_system_type tags on retained HVAC.
  # What: writes one inferred baseline system type to air loops and zones.
  # How: selects the type from PRM-2019 climate, area, story, and building-type
  # rules.
  # Used by: proposed normalization before vanilla PRM HVAC apply calls.
  def ensure_baseline_system_type_tags(model, climate_zone, hvac_building_type)
    system_type = select_baseline_system_type(hvac_building_type, model, climate_zone)
    model.getAirLoopHVACs.each { |air_loop| air_loop.additionalProperties.setFeature('baseline_system_type', system_type) }
    model.getThermalZones.each { |zone| zone.additionalProperties.setFeature('baseline_system_type', system_type) }
    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Tagged retained HVAC with inferred baseline_system_type='#{system_type}'.")
  end

  # Why: proposed normalization keeps real HVAC but still needs PRM baseline type
  # tags for downstream control/fan rules.
  # What: returns the PRM-2019 baseline_system_type string.
  # How: applies the compact Appendix G selection logic from building category,
  # climate zone, floor area, and story count.
  # Used by: ensure_baseline_system_type_tags.
  def select_baseline_system_type(hvac_building_type, model, climate_zone)
    climate_zone_code = climate_zone.to_s.split('-')[-1].to_s.upcase
    warm = HOT_CLIMATE_ZONES.include?(climate_zone_code)
    area_ft2 = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
    floors = [model.getBuildingStorys.size, 1].max

    case hvac_building_type
    when 'residential'
      warm ? 'PTHP' : 'PTAC'
    when 'public assembly'
      if area_ft2 < 120_000
        warm ? 'PSZ_HP' : 'PSZ_AC'
      else
        warm ? 'SZ_CV_ER' : 'SZ_CV_HW'
      end
    when 'heated-only storage'
      warm ? 'Electric_Furnace' : 'Gas_Furnace'
    when 'retail'
      warm ? 'PSZ_HP' : 'PSZ_AC'
    when 'hospital'
      area_ft2 > 150_000 ? 'VAV_Reheat' : 'PVAV_Reheat'
    else
      if floors <= 3 && area_ft2 < 25_000
        warm ? 'PSZ_HP' : 'PSZ_AC'
      elsif (floors.between?(4, 5) && area_ft2 < 25_000) || (floors <= 5 && area_ft2.between?(25_000, 150_000))
        warm ? 'PVAV_PFP_Boxes' : 'PVAV_Reheat'
      else
        warm ? 'VAV_PFP_Boxes' : 'VAV_Reheat'
      end
    end
  end

  # Why: proposed normalization adjusts HVAC plant loops but should leave service
  # water heating loops alone.
  # What: yields only non-SWH plant loops.
  # How: delegates the SWH-loop test to the vanilla PRM standard.
  # Used by: proposed normalization plant temperature/count/pump steps.
  def each_non_swh_plant_loop(model, prm_standard: Standard.build(CropCommon::PRM_2019_TEMPLATE))
    model.getPlantLoops.sort.each do |plant_loop|
      next if prm_call(prm_standard, :plant_loop_swh_loop?, plant_loop)

      yield plant_loop
    end
  end

  # Why: heated-only storage baseline type should not retain economizer controls.
  # What: disables economizers on air loops when the inferred HVAC category is
  # heated-only storage.
  # How: sets each outdoor-air controller economizer control type to NoEconomizer.
  # Used by: proposed normalization before and after PRM control/refinement steps.
  def apply_heated_only_storage_economizer_override(model, hvac_building_type)
    return unless hvac_building_type == 'heated-only storage'

    model.getAirLoopHVACs.sort.each do |air_loop|
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir.setEconomizerControlType('NoEconomizer')
    end
  end

  # Old names. Remove after one release.
  alias model_create_179d_proposed_normalization model_create_crop_proposed_normalization
end
