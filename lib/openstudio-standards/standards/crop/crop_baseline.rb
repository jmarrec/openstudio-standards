require_relative 'crop_common'

# Steps for the baseline pass only: PRM lighting space types without the occupancy-sensor
# credit, on/off zone fans, the OA scale to the proposed total, PRM water heater efficiency,
# chiller pump staging, and the 2007 prototype SWH and lighting schedules.
module CropBaseline
  PROTOTYPE_TO_PRM_LPD_SPACE_TYPE = {
    'WholeBuilding - Sm Office' => 'office - whole building',
    'WholeBuilding - Md Office' => 'office - whole building',
    'WholeBuilding - Lg Office' => 'office - whole building',
    'Classroom' => 'classroom/lecture/training - preschool to 12th',
    'Corridor' => 'corridor - all other',
    'Cafeteria' => 'dining - cafeteria/fast food',
    'ComputerRoom' => 'computer room',
    'Gym' => 'gymnasium playing area',
    'Kitchen' => 'kitchen',
    'Library' => 'library - whole building',
    'Lobby' => 'lobby - all other',
    'Auditorium' => 'audience seating - auditorium',
    'Mechanical' => 'electrical/mechanical',
    'Office' => 'office - whole building',
    'Restroom' => 'restroom - all other',
    'Stair' => 'stairwell',
    'PublicRestroom' => 'restroom - all other',
    'Storage' => 'storage 50 to 1000 sf - all other',
    'Bulk' => 'warehouse - bulk storage',
    'Fine' => 'warehouse - fine storage',
    'Strip mall - type 1' => 'retail - whole building',
    'Strip mall - type 2' => 'retail - whole building',
    'Strip mall - type 3' => 'retail - whole building',
    'Retail' => 'retail - whole building',
    'Point_of_Sale' => 'sales',
    'Back_Space' => 'storage 50 to 1000 sf - all other',
    'Entry' => 'lobby - all other',
    'GuestRoom123Occ' => 'guest room',
    'GuestRoom123Vac' => 'guest room',
    'GuestLounge' => 'lobby - hotel',
    'StaffLounge' => 'lounge/breakroom - all other',
    'Exercise' => 'exercise center - whole building',
    'Meeting' => 'conference/meeting/multipurpose',
    'Laundry' => 'laundry/washing',
    'ElevatorCore' => 'elevator core',
    'Elec/MechRoom' => 'electrical/mechanical',
  }.freeze

  # Replaces the Fan:ConstantVolume supply fan of each zone unit that has a fan
  # operating mode schedule with a Fan:OnOff fan of the same size and power.
  # EnergyPlus does not let a constant-volume fan cycle, so the baseline fan could not
  # cycle to meet loads during unoccupied hours.
  def replace_zone_hvac_constant_volume_fans_with_on_off(model)
    count = 0
    model.getZoneHVACComponents.each do |raw_eq|
      eq = cast_zone_hvac_equipment(raw_eq)
      next unless eq.respond_to?(:setSupplyAirFanOperatingModeSchedule) && eq.respond_to?(:setSupplyAirFan)
      next unless supply_fan_constant_volume?(eq)

      old_fan = eq.supplyAirFan.to_FanConstantVolume.get
      new_fan = OpenStudio::Model::FanOnOff.new(model, old_fan.availabilitySchedule)
      new_fan.setFanTotalEfficiency(old_fan.fanTotalEfficiency)
      new_fan.setPressureRise(old_fan.pressureRise)
      new_fan.setMotorEfficiency(old_fan.motorEfficiency)
      new_fan.setMotorInAirstreamFraction(old_fan.motorInAirstreamFraction)
      new_fan.setEndUseSubcategory(old_fan.endUseSubcategory)
      old_fan.maximumFlowRate.is_initialized ? new_fan.setMaximumFlowRate(old_fan.maximumFlowRate.get) : new_fan.autosizeMaximumFlowRate
      fan_name = old_fan.nameString
      eq.setSupplyAirFan(new_fan)
      old_fan.remove
      new_fan.setName(fan_name)
      count += 1
    end
    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Replaced #{count} zone HVAC constant-volume supply fans with Fan:OnOff.") if count.positive?
    count
  end

  # Prepares the baseline zone HVAC before the first PRM sizing run: on/off fans
  # for zone units, then the HVAC and exhaust availability schedules.
  def apply_baseline_hvac_before_sizing(model)
    replace_zone_hvac_constant_volume_fans_with_on_off(model)
    model_apply_occupancy_hvac_and_exhaust_availability_schedules(model)
  end

  # Why: the PRM baseline generator needs 179D inputs captured before it
  # rebuilds the model.
  # What: stamps PRM-valid lighting space types and saves proposed design OA.
  # How: uses vanilla PRM data for LPD names, then reads current air-loop OA.
  # Used by: the create-179D-baseline measure before vanilla PRM generation.
  def model_prepare_crop_baseline(model, prm_standard: Standard.build(CropCommon::PRM_2019_TEMPLATE))
    building_type = nil
    if model.getBuilding.standardsBuildingType.is_initialized || model.getSpaceTypes.any? { |space_type| space_type.standardsBuildingType.is_initialized }
      building_type = model_get_primary_building_type(model, remap_office: true, remap_retail: true)
    end
    prepare_space_types_for_prm_lighting(model, prm_standard:)
    { building_type:, proposed_total_oa_m3s: compute_total_design_oa_m3_per_s(model) }
  end

  # Why: the vanilla PRM baseline pass omits 179D-only post-processing.
  # What: adds heated-only ventilation and adjusts baseline OA/reheat behavior.
  # How: applies the saved pre-baseline state after PRM has rebuilt HVAC.
  # Used by: the create-179D-baseline measure after vanilla PRM generation.
  def model_apply_crop_baseline_post_steps(model, state = {})
    proposed_total_oa_m3s = state.is_a?(Hash) ? state[:proposed_total_oa_m3s] : state
    add_heated_only_zone_ventilation(model)
    apply_baseline_oa_scale(model, proposed_total_oa_m3s)
    apply_reheat_max_air_temperature_headroom(model)
    model_apply_occupancy_hvac_and_exhaust_availability_schedules(model)
    true
  end

  def prm_2019_water_heater_efficiency_requirement(prm_standard, _water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
    search_criteria = {
      'template' => prm_standard.template,
      'fuel_type' => fuel_type,
      'product_class' => prm_2019_storage_water_heater_product_class(fuel_type)
    }

    wh_props = prm_2019_find_water_heater_efficiency_requirement(prm_standard, search_criteria, capacity_btu_per_hr, volume_gal)
    return wh_props unless wh_props == {}

    search_criteria['draw_profile'] = 'medium'
    prm_2019_find_water_heater_efficiency_requirement(prm_standard, search_criteria, capacity_btu_per_hr, volume_gal)
  end

  def prm_2019_find_water_heater_efficiency_requirement(prm_standard, search_criteria, capacity_btu_per_hr, volume_gal)
    [
      prm_standard.model_find_objects(prm_standard.standards_data['water_heaters'], search_criteria, capacity_btu_per_hr),
      prm_standard.model_find_objects(prm_standard.standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal.round(0)),
      prm_standard.model_find_objects(prm_standard.standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, nil, capacity_btu_per_hr),
      prm_standard.model_find_objects(prm_standard.standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal, capacity_btu_per_hr / volume_gal)
    ].each do |rows|
      return rows[0] if rows.size == 1
    end

    {}
  end

  def prm_2019_storage_water_heater_product_class(fuel_type)
    fuel_type == 'Electricity' ? 'Water Heaters' : 'Storage Water Heater'
  end

  # Why: the rebuilt PRM baseline can change total design outdoor air from the
  # proposed model used for the 179D comparison.
  # What: scales baseline air-loop design OA to match the captured proposed total.
  # How: compares total OA after rebuild and scales each baseline air loop when
  # the difference is larger than one percent.
  # Used by: model_apply_crop_baseline_post_steps.
  def apply_baseline_oa_scale(model, proposed_total_oa_m3s = nil)
    return if proposed_total_oa_m3s.nil?

    # A zero proposed total means the proposed OA is autosized and not known.
    # A scale factor of 0 would remove all baseline OA, so skip the step.
    unless proposed_total_oa_m3s.positive?
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', 'Proposed total OA is 0 m^3/s (autosized, no sizing results); skipping baseline OA scale step.')
      return
    end

    baseline_total_oa_m3s = compute_total_design_oa_m3_per_s(model)
    if baseline_total_oa_m3s.zero?
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', "Baseline total OA is 0 m^3/s but proposed is #{proposed_total_oa_m3s.round(3)} m^3/s; skipping baseline OA scale step.")
      return
    end

    pct_diff = (proposed_total_oa_m3s - baseline_total_oa_m3s) / baseline_total_oa_m3s * 100.0
    return if pct_diff.abs <= 1.0

    scaling_factor = proposed_total_oa_m3s / baseline_total_oa_m3s
    model.getAirLoopHVACs.sort.each do |air_loop|
      sizing_system = air_loop.sizingSystem
      old_value = if sizing_system.designOutdoorAirFlowRate.is_initialized
                    sizing_system.designOutdoorAirFlowRate.get
                  elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
                    sizing_system.autosizedDesignOutdoorAirFlowRate.get
                  end

      if old_value
        sizing_system.setDesignOutdoorAirFlowRate(old_value * scaling_factor)
      else
        raise "Cannot adjust baseline design outdoor airflow rate; no existing value found on air loop '#{air_loop.nameString}'."
      end
    end
  end

  # Why: baseline OA scaling needs a simple model-level design OA total.
  # What: sums design OA on air loops with outdoor-air systems.
  # How: prefers explicit Sizing:System OA and falls back to autosized OA.
  # Used by: baseline pre/post override state capture.
  def compute_total_design_oa_m3_per_s(model)
    total = 0.0
    model.getAirLoopHVACs.each do |air_loop|
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      sizing_system = air_loop.sizingSystem
      total += if sizing_system.designOutdoorAirFlowRate.is_initialized
                 sizing_system.designOutdoorAirFlowRate.get
               elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
                 sizing_system.autosizedDesignOutdoorAirFlowRate.get
               else
                 0.0
               end
    end
    total
  end

  # Why: PRM baseline lighting lookup needs PRM-valid space type names.
  # What: maps prototype space type names to PRM LPD table names.
  # How: leaves already-valid PRM names alone and stamps only known prototype
  # names.
  # Used by: model_prepare_crop_baseline.
  def prepare_space_types_for_prm_lighting(model, prm_standard: Standard.build(CropCommon::PRM_2019_TEMPLATE))
    valid_lpd = (prm_standard.standards_data['prm_interior_lighting'] || []).filter_map { |row| row['lpd_space_type'] }.uniq
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsSpaceType.is_initialized

      current = space_type.standardsSpaceType.get
      space_type.additionalProperties.setFeature('prototype_standards_space_type', current)
      next if valid_lpd.include?(current)

      mapped = PROTOTYPE_TO_PRM_LPD_SPACE_TYPE[current]
      if mapped.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', "No PRM lpd_space_type mapping for '#{current}'; baseline lighting may be zero.")
        next
      end
      space_type.setStandardsSpaceType(mapped)
    end
  end

  # Removes the occupancy-sensor credit from each baseline lighting schedule.
  # Processes shared Lights once so the name suffix does not repeat.
  def space_type_light_sch_change(model, prm_standard: Standard.build(CropCommon::PRM_2019_TEMPLATE))
    sizing_run_dir = prm_standard.instance_variable_get(:@sizing_run_dir)
    schedule_hash = {}
    processed_lights = {}
    model.getSpaces.sort_by(&:nameString).each do |space|
      space_type = prm_call(prm_standard, :prm_get_optional_handler, space, sizing_run_dir, 'spaceType')
      next unless space_type.hasAdditionalProperties && space_type.additionalProperties.hasFeature('regulated_lights_name')

      lights_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
      lights = space_type.model.getLightsByName(lights_name)
      if lights.is_initialized
        light = lights.get
      else
        prm_call(prm_standard, :prm_raise, false, sizing_run_dir, "Cannot find the lights #{lights_name} in the model")
      end

      # A Lights object attached at the space-type level is shared by every space
      # of that type; process it once so the occupancy-sensor credit suffix isn't
      # appended repeatedly to the schedule name.
      next if processed_lights.key?(light.handle.to_s)

      processed_lights[light.handle.to_s] = true

      unless light.schedule.is_initialized
        OpenStudio.logFree(OpenStudio::Warn, 'prm.log', "schedule is not available in component #{light.name.get}. Skip processing")
        next
      end

      light_schedule = light.schedule.get
      occupancy_sensor_credit = prm_call(prm_standard, :get_additional_property_as_double, space, 'occ_control_credit', 0.0)
      new_light_schedule_name = format("#{light_schedule.name.get}_%.4f", occupancy_sensor_credit)
      if schedule_hash.key?(new_light_schedule_name)
        light.setSchedule(schedule_hash[new_light_schedule_name])
      else
        new_schedule = prm_call(prm_standard, :deep_copy_schedule, new_light_schedule_name, light_schedule, occupancy_sensor_credit, model)
        schedule_hash[new_light_schedule_name] = new_schedule if light.setSchedule(new_schedule)
      end
    end
  end

  # PRM stages the primary chiller pumps on the primary loop's own supply-side demand.
  # The forced pump flow keeps that demand high, so the plant can lock on with no load.
  # Sense the secondary loop (the building load) instead. Returns true if the sensor changed.
  def stage_chiller_pumps_on_secondary_demand(model, primary_plant)
    sensor_name = "#{primary_plant.name.to_s.gsub(/[-\s]+/, '_')}_CHW_DEMAND"
    sensor = model.getEnergyManagementSystemSensors.find { |s| s.nameString == sensor_name }
    return false if sensor.nil?

    secondary_plant = primary_plant.demandComponents.filter_map { |c| c.to_HeatExchangerFluidToFluid.get if c.to_HeatExchangerFluidToFluid.is_initialized }
                                   .flat_map { |hx| [hx.plantLoop, hx.secondaryPlantLoop] }
                                   .filter_map { |loop| loop.get if loop.is_initialized }
                                   .find { |loop| loop.handle != primary_plant.handle }
    if secondary_plant.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{primary_plant.name}, no secondary loop found; chiller pump EMS still senses the primary loop.")
      return false
    end

    sensor.setKeyName(secondary_plant.nameString)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{primary_plant.name}, chiller pump EMS now senses demand on #{secondary_plant.name}.")
    true
  end

  def prototype_standard_2007
    @prototype_standard_2007 ||= Standard.build('90.1-2007')
  end

  def prototype_space_type_properties(std_2007, space_type)
    props = std_2007.space_type_get_standards_data(space_type)
    return props if props && !props.empty?

    additional = space_type.additionalProperties
    if additional.hasFeature('prototype_standards_space_type')
      proto_name = additional.getFeatureAsString('prototype_standards_space_type').get
      bldg_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
      if bldg_type
        props = std_2007.standards_data['space_types'].find do |r|
          r['building_type'] == bldg_type && r['space_type'] == proto_name
        end
        return props if props && !props.empty?
      end
    end

    bldg_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
    if bldg_type
      st_name = space_type.nameString
      candidate_rows = std_2007.standards_data['space_types'].select { |r| r['building_type'] == bldg_type }
      candidate_rows.find { |r| st_name.include?(r['space_type']) }
    end
  end

  # Applies ASHRAE 90.1-2007 DOE prototype lighting schedules to each space type in the model.
  def model_apply_prototype_lighting_schedule(model)
    std_2007 = prototype_standard_2007
    count = 0

    model.getSpaceTypes.sort.each do |space_type|
      lights = space_type.lights
      next if lights.empty?

      props = prototype_space_type_properties(std_2007, space_type)
      next if props.nil? || props['lighting_schedule'].nil? || props['lighting_schedule'].empty?

      schedule_name = props['lighting_schedule']
      schedule = std_2007.model_add_schedule(model, schedule_name)
      next if schedule.nil?

      lights.each do |light|
        count += 1 if light.setSchedule(schedule)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Applied 2007 prototype lighting schedule to #{count} Lights object(s).")
    count.positive?
  end

  # Replaces existing WaterUseEquipment flow rate fraction schedules with ASHRAE 90.1-2007 prototype schedules.
  def model_apply_prototype_service_water_heating(model, building_type: nil)
    equipments = model.getWaterUseEquipments
    return false if equipments.empty?

    std_2007 = prototype_standard_2007
    count = 0
    primary_bldg_type = building_type
    if primary_bldg_type.nil?
      begin
        primary_bldg_type = model_get_primary_building_type(model)
      rescue StandardError => e
        OpenStudio.logFree(OpenStudio::Debug, 'crop.Model', "Could not determine primary building type: #{e.message}")
      end
    end

    equipments.sort.each do |equipment|
      schedule_name = prototype_service_water_heating_schedule_name(equipment, primary_bldg_type)
      next if schedule_name.nil?

      schedule = std_2007.model_add_schedule(model, schedule_name)
      next if schedule.nil?

      count += 1 if equipment.setFlowRateFractionSchedule(schedule)
    end

    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Applied 2007 prototype SWH schedule to #{count} WaterUseEquipment object(s).")
    count.positive?
  end

  # Name of the 2007 prototype SWH schedule for one WaterUseEquipment: from its space type,
  # else from the primary building type. Nil if neither has one.
  def prototype_service_water_heating_schedule_name(equipment, primary_bldg_type)
    std_2007 = prototype_standard_2007

    # 1. Look up from space type if available
    space = equipment.space
    if space.is_initialized && space.get.spaceType.is_initialized
      props = prototype_space_type_properties(std_2007, space.get.spaceType.get)
      schedule_name = props['service_water_heating_schedule'] if props
      return schedule_name unless schedule_name.nil? || schedule_name.empty?
    end

    # 2. Fall back to primary building type SWH schedule
    return nil if primary_bldg_type.nil?

    row = std_2007.standards_data['space_types'].find do |r|
      r['building_type'] == primary_bldg_type && r['service_water_heating_schedule'] && !r['service_water_heating_schedule'].empty?
    end
    row && row['service_water_heating_schedule']
  end

  # Old names. Remove after one release.
  alias apply_179d_baseline_hvac_before_sizing apply_baseline_hvac_before_sizing
  alias model_prepare_179d_prm_baseline_overrides model_prepare_crop_baseline
  alias model_apply_179d_prm_baseline_overrides model_apply_crop_baseline_post_steps
  alias apply_179d_baseline_post_steps apply_baseline_oa_scale
end
