require_relative 'crop_common'
require_relative 'crop_proposed'
require_relative 'crop_baseline'

module CropPRMFanPowerMetadata
  PRM_FAN_POWER_FEATURE_METHODS = {
    'supply_fan_w' => :air_loop_hvac_get_supply_fan_power,
    'return_fan_w' => :air_loop_hvac_get_return_fan_power,
    'relief_fan_w' => :air_loop_hvac_get_relief_fan_power,
  }.freeze

  def ensure_prm_fan_power_features(air_loop_hvac, prm_standard)
    fan_power_by_feature = PRM_FAN_POWER_FEATURE_METHODS.transform_values do |method_name|
      prm_standard.send(method_name, air_loop_hvac).to_f
    end
    ensure_prm_fan_power_features_for_zones(air_loop_hvac.thermalZones.sort, air_loop_hvac.name, fan_power_by_feature)
  end

  def ensure_prm_fan_power_features_for_zones(thermal_zones, object_name, fan_power_by_feature)
    repaired_zones = []
    thermal_zones.each do |zone|
      additional = zone.additionalProperties
      missing_features = fan_power_by_feature.keys.reject do |feature|
        additional.hasFeature(feature) && additional.getFeatureAsDouble(feature).is_initialized
      end
      next if missing_features.empty?

      missing_features.each do |feature|
        additional.setFeature(feature, fan_power_by_feature[feature])
      end
      repaired_zones << zone.nameString
    end

    unless repaired_zones.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model',
                         "Added missing PRM fan-power metadata for #{repaired_zones.size} zone(s) on #{object_name}.")
    end

    repaired_zones
  end
end

# The PRM hooks: singleton methods that prepare_prm_standard_for_crop_overrides installs on a
# vanilla PRM standard, and the proposed normalization that needs them. The hooks call back
# into CropCommon, CropProposed, CropBaseline and CropPRMFanPowerMetadata, so the includer
# needs those modules too.
module CropPRMHooks
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

  # Installs the CROP hooks on a vanilla PRM standard as singleton methods, so the
  # pinned PRM class stays untouched. Returns the same PRM standard.
  def prepare_prm_standard_for_crop_overrides(prm_standard)
    # Each hook calls host_standard.<name>, so a self install recurses forever.
    raise ArgumentError, 'prm_standard must be a separate PRM standard' if prm_standard.equal?(self)

    host_standard = self
    prm_fan_power_method = prm_standard.method(:air_loop_hvac_apply_prm_baseline_fan_power)
    prm_get_airloop_design_oa = prm_standard.method(:get_airloop_hvac_design_oa_from_sql)

    prm_standard.define_singleton_method(:baseline_thermal_zone_demand_control_ventilation_required?) do |thermal_zone|
      prm_standard.send(:user_model_zone_demand_control_ventilation_required?, thermal_zone)
    end
    prm_standard.define_singleton_method(:baseline_air_loop_hvac_demand_control_ventilation_required?) do |air_loop_hvac|
      prm_standard.send(:user_model_air_loop_hvac_demand_control_ventilation_required?, air_loop_hvac)
    end
    prm_standard.define_singleton_method(:get_airloop_hvac_design_oa_from_sql) do |air_loop_hvac|
      host_standard.air_loop_design_oa_with_sizing_fallback(air_loop_hvac, prm_get_airloop_design_oa)
    end
    prm_standard.define_singleton_method(:space_type_light_sch_change) do |model|
      host_standard.space_type_light_sch_change(model, prm_standard:)
    end
    prm_standard.define_singleton_method(:model_apply_standard_infiltration) do |model, **_options|
      host_standard.model_apply_nist_infiltration(model, CropCommon::NIST_INFILTRATION_BASELINE_CFM_PER_FT2)
    end
    prm_standard.define_singleton_method(:model_update_ground_temperature_profile) do |model, climate_zone|
      surfaces_with_fc_factor_boundary = model.getSurfaces.any? { |s| s.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod' }
      if surfaces_with_fc_factor_boundary
        weather_file_path = prm_get_optional_handler(model.getWeatherFile, @sizing_run_dir, 'path').to_s
        stat_file_path = weather_file_path.sub('.epw', '.stat').to_s
        unless File.exist?(stat_file_path)
          climate_zone_weather_file_map = OpenstudioStandards::Weather.climate_zone_weather_file_map
          weather_file = climate_zone_weather_file_map[climate_zone]
          stat_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file).sub('.epw', '.stat').to_s
        end
        ground_temp = model.getSiteGroundTemperatureFCfactorMethod
        stat_file = OpenstudioStandards::Weather::StatFile.load(stat_file_path)
        ground_temperatures = stat_file.monthly_lagged_dry_bulb
        unless ground_temperatures.empty?
          ground_temp.setAllMonthlyTemperatures(ground_temperatures)
        end
      end
      surfaces_with_fc_factor_boundary
    end
    prm_sizing_schedule_method = prm_standard.method(:model_apply_prm_baseline_sizing_schedule)
    prm_standard.define_singleton_method(:model_apply_prm_baseline_sizing_schedule) do |model|
      prm_sizing_schedule_method.call(model).tap do
        host_standard.restore_design_day_only_infiltration_design_days(model)
        host_standard.zero_nist_hvac_off_infiltration_design_days(model)
      end
    end
    # Only the baseline build names its first sizing run SR1; the proposed runs are PROP-SR1 and PROP-SR2.
    prm_sizing_run_method = prm_standard.method(:model_run_sizing_run)
    prm_standard.define_singleton_method(:model_run_sizing_run) do |model, sizing_run_dir = "#{Dir.pwd}/SR"|
      host_standard.apply_baseline_hvac_before_sizing(model) if File.basename(sizing_run_dir.to_s) == 'SR1'
      prm_sizing_run_method.call(model, sizing_run_dir)
    end
    prm_standard.define_singleton_method(:__model_get_primary_building_type) do |model|
      host_standard.__model_get_primary_building_type(model)
    end
    prm_standard.define_singleton_method(:model_get_primary_building_type) do |model, remap_office: false, remap_retail: false|
      host_standard.model_get_primary_building_type(model, remap_office:, remap_retail:)
    end
    prm_standard.define_singleton_method(:model_remap_office) do |model, floor_area|
      host_standard.model_remap_office(model, floor_area)
    end
    prm_standard.define_singleton_method(:model_apply_water_heater_prm_parameter) do |water_heater_mixed, building_type_swh|
      new_fuel = water_heater_mixed_apply_prm_baseline_fuel_type(building_type_swh)
      water_heater_mixed.setHeaterFuelType(new_fuel)
      if water_heater_mixed_apply_efficiency(water_heater_mixed)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, changed baseline water heater fuel to #{new_fuel}.")
        true
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, could not apply baseline water heater efficiency after changing fuel to #{new_fuel}.")
        false
      end
    end
    prm_standard.define_singleton_method(:water_heater_mixed_get_efficiency_requirement) do |water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal|
      host_standard.prm_2019_water_heater_efficiency_requirement(prm_standard, water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
    end
    prm_standard.define_singleton_method(:air_loop_hvac_apply_prm_baseline_fan_power) do |air_loop_hvac|
      host_standard.ensure_prm_fan_power_features(air_loop_hvac, prm_standard)
      prm_fan_power_method.call(air_loop_hvac)
    end
    prm_chiller_pump_ems_method = prm_standard.method(:add_ems_for_multiple_chiller_pumps_w_secondary_plant)
    prm_standard.define_singleton_method(:add_ems_for_multiple_chiller_pumps_w_secondary_plant) do |model, primary_plant|
      prm_chiller_pump_ems_method.call(model, primary_plant).tap do
        host_standard.stage_chiller_pumps_on_secondary_demand(model, primary_plant)
      end
    end

    prm_standard
  end
  alias prepare_prm_standard_for_acm_overrides prepare_prm_standard_for_crop_overrides
  alias model_create_179d_proposed_normalization model_create_crop_proposed_normalization

  # EnergyPlus only fills the Standard 62.1 Summary Vot when Sizing:System OA is
  # autosized; a hard-set design OA (proposed normalization) leaves it 0 and the
  # DCV air-loop gate wrongly drops DCV. Fall back to the Sizing:System (or OA
  # controller) design OA when the 62.1 read is non-positive.
  def air_loop_design_oa_with_sizing_fallback(air_loop_hvac, prm_get_airloop_design_oa)
    oa_m3_per_s = prm_get_airloop_design_oa.call(air_loop_hvac)
    return oa_m3_per_s if oa_m3_per_s.is_a?(Numeric) && oa_m3_per_s > 0.0

    sizing_system = air_loop_hvac.sizingSystem
    return sizing_system.designOutdoorAirFlowRate.get if sizing_system.designOutdoorAirFlowRate.is_initialized
    return sizing_system.autosizedDesignOutdoorAirFlowRate.get if sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized

    return 0.0 unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

    controller_oa = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
    return controller_oa.minimumOutdoorAirFlowRate.get if controller_oa.minimumOutdoorAirFlowRate.is_initialized
    return controller_oa.autosizedMinimumOutdoorAirFlowRate.get if controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized

    0.0
  end
end

# CROP standard for the two PRM-2019 passes: the proposed normalization and the baseline. It
# keeps the stock template and data.
class CropASHRAE901PRM2019 < ASHRAE901PRM2019
  register_standard 'CROP 90.1-PRM-2019'
  # Old registration of the 2007 prototype schedule class; its methods now live in CropBaseline.
  register_standard '179D Prototype 2007'

  include CropCommon
  include CropProposed
  include CropBaseline
  include CropPRMFanPowerMetadata
  include CropPRMHooks
end

# Old name of the 2007 prototype class. Kept so old scripts still work.
Prototype179d2007 = CropASHRAE901PRM2019
