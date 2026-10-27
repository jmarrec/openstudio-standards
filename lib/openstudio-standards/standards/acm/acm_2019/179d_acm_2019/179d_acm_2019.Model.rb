require_relative '179d_acm_2019'

class ACM179d2019
  ACM_BUILDING_TYPE_BY_PROTOTYPE = {
    'SmallOffice' => 'Office',
    'MediumOffice' => 'Office',
    'LargeOffice' => 'Office',
    'RetailStandalone' => 'Retail',
    'RetailStripmall' => 'StripMall',
  }.freeze

  ACM_INFILTRATION_RATE_CFM_PER_FT2 = 0.0448

  HVAC_AVAILABILITY_SCHEDULE_MAP = {
    'AirLoopHVAC' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACCoolingPanelRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACDehumidifierDX' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACEnergyRecoveryVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACFourPipeFanCoil' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACHighTemperatureRadiant' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACIdealLoadsAirSystem' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTemperatureRadiantElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantConstFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantVarFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalAirConditioner' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitHeater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACWaterToAirHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'FanZoneExhaust' => [
      [:availabilitySchedule, :setAvailabilitySchedule],
      [:flowFractionSchedule, :setFlowFractionSchedule]
    ],
    'AirLoopHVACUnitarySystem' => [[:supplyAirFanOperatingModeSchedule, :setSupplyAirFanOperatingModeSchedule]],
  }.freeze

  ACM_PEOPLE_FIELDS = [
    'occupancy_per_area',
    'occupancy_schedule',
    'occupancy_activity_schedule',
    'occupancy_fraction_sensible'
  ].freeze

  ACM_SWH_FIELDS = [
    'service_water_heating_peak_flow_per_area',
    'service_water_heating_schedule'
  ].freeze

  ACM_EQUIPMENT_FIELDS = [
    'electric_equipment_per_area',
    'electric_equipment_schedule',
    'gas_equipment_schedule'
  ].freeze

  ACM_ELECTRIC_EQUIPMENT_EXCLUDED_NAME_FRAGMENTS = [
    'elevator',
    'fuel equipment'
  ].freeze

  PRM_WHOLE_BUILDING_ACM_SPACE_TYPE = {
    'school/university - whole building' => 'Classroom',
    'warehouse - whole building' => 'Bulk',
  }.freeze

  ACM_WHOLE_BUILDING_SPACE_TYPE_FALLBACK = {
    'Retail' => 'Retail',
    'StripMall' => 'Strip mall - type 1',
    'Warehouse' => 'Bulk',
  }.freeze

  def model_get_acm_standards_data(model, throw_if_not_found: false, building_type: nil)
    lookup_building_type = building_type || model_get_primary_building_type(model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: false)
    return acm_lookup_failure([], throw_if_not_found) if standards_building_type.nil?

    criteria = acm_space_type_candidates(standards_building_type, whole_building_space_type_name(model, standards_building_type)).map do |space_type_name|
      acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    space_type_properties = acm_find_space_type_properties(criteria, throw_if_not_found: false, log_failure: false)
    if space_type_properties.empty?
      candidate_space_type = model.getSpaceTypes.select do |space_type|
        next false unless space_type.standardsBuildingType.is_initialized

        acm_building_type_for_lookup(space_type.standardsBuildingType.get, throw_if_not_found: false) == standards_building_type
      end.max_by(&:floorArea)
      space_type_properties = space_type_get_acm_standards_data(candidate_space_type) unless candidate_space_type.nil?
    end

    return space_type_properties unless space_type_properties.empty?

    schedule_properties = acm_hvac_operation_schedule_properties(standards_building_type)
    return schedule_properties unless schedule_properties.empty?

    acm_lookup_failure(criteria, throw_if_not_found)
  end

  def model_get_standards_data(model, throw_if_not_found: false, building_type: nil)
    model_get_acm_standards_data(model, throw_if_not_found:, building_type:)
  end

  def model_apply_common_acm_assumptions(model, apply_hvac_operation_schedule: true, building_type: nil)
    model_apply_acm_hvac_availability_schedule(model, building_type:) if apply_hvac_operation_schedule
    true
  end

  # Building types whose prototype schedules model the summer break the flat ACM
  # schedules do not; for these we keep the prototype load schedules.
  ACM_PROTOTYPE_SCHEDULE_BUILDING_TYPES = ['PrimarySchool', 'SecondarySchool'].freeze

  # True when the space type belongs to a school, so ACM leaves its lighting,
  # occupancy, equipment, and SWH schedules on the prototype (summer-break)
  # values. ACM densities are still applied.
  def acm_space_type_keeps_prototype_schedule?(space_type)
    return false unless space_type.standardsBuildingType.is_initialized

    ACM_PROTOTYPE_SCHEDULE_BUILDING_TYPES.include?(space_type.standardsBuildingType.get)
  end

  def model_apply_acm_people(model, building_type: nil)
    count_people = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      people_objects = space_type.people.sort_by(&:nameString)
      next if people_objects.empty? && space_type.floorArea.zero?

      acm_data = acm_people_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_PEOPLE_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM people data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      if people_objects.empty?
        next unless acm_data['occupancy_per_area'].to_f.positive?

        people_definition = OpenStudio::Model::PeopleDefinition.new(model)
        people_definition.setName("#{space_type.nameString} ACM People Definition")
        new_people = OpenStudio::Model::People.new(people_definition)
        new_people.setName("#{space_type.nameString} ACM People")
        new_people.setSpaceType(space_type)
        people_objects = [new_people]
      end

      occupancy_schedule = model_add_schedule(model, acm_data['occupancy_schedule'])
      activity_schedule = model_add_schedule(model, acm_data['occupancy_activity_schedule'])
      keep_schedule = acm_space_type_keeps_prototype_schedule?(space_type)

      people_objects.each do |people_object|
        people_definition = people_object.peopleDefinition
        people_definition.setPeopleperSpaceFloorArea(acm_occupancy_per_area_si(acm_data['occupancy_per_area']))
        people_definition.setSensibleHeatFraction(acm_data['occupancy_fraction_sensible'].to_f)
        people_object.setNumberofPeopleSchedule(occupancy_schedule) unless keep_schedule && people_object.numberofPeopleSchedule.is_initialized
        people_object.setActivityLevelSchedule(activity_schedule)
        count_people += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM people fields to #{count_people} People object(s).")
    count_people.positive?
  end

  def acm_people_data_for_space_type(space_type, building_type: nil)
    return space_type_get_acm_standards_data(space_type, throw_if_not_found: true) if building_type.nil?

    standards_building_type = acm_building_type_for_lookup(building_type, throw_if_not_found: true)
    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_occupancy_per_area_si(occupancy_per_1000_ft2)
    OpenStudio.convert(occupancy_per_1000_ft2.to_f / 1000.0, '1/ft^2', '1/m^2').get
  end

  def model_apply_acm_equipment_loads(model, building_type: nil)
    count_electric = 0
    count_gas = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      electric_objects = space_type.electricEquipment.sort_by(&:nameString)
      gas_objects = space_type.gasEquipment.sort_by(&:nameString)
      space_type.spaces.sort_by(&:nameString).each do |space|
        electric_objects.concat(space.electricEquipment.sort_by(&:nameString))
        gas_objects.concat(space.gasEquipment.sort_by(&:nameString))
      end
      electric_objects.reject! { |equipment| acm_excluded_electric_equipment?(equipment) }
      next if electric_objects.empty? && gas_objects.empty? && space_type.floorArea.zero?

      acm_data = acm_equipment_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_EQUIPMENT_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM equipment data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      electric_density_w_per_m2 = acm_electric_equipment_per_area_si(acm_data['electric_equipment_per_area'])
      keep_schedule = acm_space_type_keeps_prototype_schedule?(space_type)
      if electric_objects.empty? && acm_data['electric_equipment_per_area'].to_f.positive? && space_type.floorArea.positive?
        definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
        definition.setName("#{space_type.nameString} ACM Electric Equipment Definition")
        new_equipment = OpenStudio::Model::ElectricEquipment.new(definition)
        new_equipment.setName("#{space_type.nameString} ACM Electric Equipment")
        new_equipment.setSpaceType(space_type)
        electric_objects = [new_equipment]
      end

      unless electric_objects.empty?
        electric_schedule = model_add_schedule(model, acm_data['electric_equipment_schedule'])
        electric_objects.each do |equipment_object|
          equipment_object.electricEquipmentDefinition.setWattsperSpaceFloorArea(electric_density_w_per_m2)
          equipment_object.setSchedule(electric_schedule) unless keep_schedule && equipment_object.schedule.is_initialized
          count_electric += 1
        end
      end

      next if gas_objects.empty?

      gas_schedule = model_add_schedule(model, acm_data['gas_equipment_schedule'])
      gas_objects.each do |equipment_object|
        equipment_object.setSchedule(gas_schedule) unless keep_schedule && equipment_object.schedule.is_initialized
        count_gas += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM equipment fields to #{count_electric} ElectricEquipment object(s) and #{count_gas} GasEquipment object(s).")
    count_electric.positive? || count_gas.positive?
  end

  def acm_equipment_data_for_space_type(space_type, building_type: nil)
    lookup_building_type = building_type
    lookup_building_type ||= space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized
    lookup_building_type ||= model_get_primary_building_type(space_type.model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: true)

    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_electric_equipment_per_area_si(w_per_ft2)
    OpenStudio.convert(w_per_ft2.to_f, 'W/ft^2', 'W/m^2').get
  end

  def acm_excluded_electric_equipment?(equipment)
    definition = equipment.electricEquipmentDefinition
    name_values = [equipment.nameString, definition.nameString]
    end_use = equipment.respond_to?(:endUseSubcategory) ? equipment.endUseSubcategory.to_s : ''
    return false if end_use != 'Elevators' && name_values.any? { |value| value.to_s.downcase.include?('acm electric equipment') }

    values = name_values + [end_use]
    values.any? do |value|
      ACM_ELECTRIC_EQUIPMENT_EXCLUDED_NAME_FRAGMENTS.any? { |fragment| value.to_s.downcase.include?(fragment) }
    end
  end

  def model_apply_acm_service_water_heating(model, building_type: nil)
    water_use_by_space_type = acm_water_use_equipment_by_space_type(model)
    space_type_floor_area = model_create_space_type_hash(model, false).transform_values { |values| values[:floor_area].to_f }
    count = 0

    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      next if water_use_by_space_type.key?(space_type.handle.to_s)

      floor_area_m2 = space_type_floor_area[space_type]
      next if floor_area_m2.nil? || floor_area_m2.zero?

      acm_data = acm_swh_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_SWH_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM service water heating data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      next unless acm_data['service_water_heating_peak_flow_per_area'].to_f.positive?

      definition = OpenStudio::Model::WaterUseEquipmentDefinition.new(model)
      definition.setName("#{space_type.nameString} ACM Service Water Use Definition")
      equipment = OpenStudio::Model::WaterUseEquipment.new(definition)
      equipment.setName("#{space_type.nameString} ACM Service Water Use")
      spaces = model.getSpaces.select { |space| space.spaceType.is_initialized && space.spaceType.get == space_type }
      equipment.setSpace(spaces.max_by(&:floorArea)) unless spaces.empty?
      water_use_by_space_type[space_type.handle.to_s] = { space_type:, water_use_equipment: [equipment], created_by_acm: true }
    end

    water_use_by_space_type.each_value do |entry|
      space_type = entry[:space_type]
      water_use_equipment = entry[:water_use_equipment]
      acm_data = acm_swh_data_for_space_type(space_type, building_type:)
      missing_fields = ACM_SWH_FIELDS.select { |field| acm_data[field].nil? || acm_data[field].to_s.empty? }
      unless missing_fields.empty?
        raise "179D ACM service water heating data for '#{space_type.nameString}' is missing #{missing_fields.join(', ')}."
      end

      floor_area_m2 = space_type_floor_area[space_type]
      if floor_area_m2.nil? || floor_area_m2.zero?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Skipping ACM SWH for '#{space_type.nameString}' because its floor area is zero.")
        next
      end

      schedule = model_add_schedule(model, acm_data['service_water_heating_schedule'])
      # Keep the prototype (summer-break) schedule only on SWH that predates ACM;
      # WaterUseEquipment auto-populates a default schedule, so ACM-created
      # equipment still takes the ACM schedule.
      keep_schedule = acm_space_type_keeps_prototype_schedule?(space_type) && !entry[:created_by_acm]
      peak_flow_rate_m3_per_s = acm_swh_peak_flow_rate_si(acm_data['service_water_heating_peak_flow_per_area'], floor_area_m2)
      existing_peak_flow_rate_m3_per_s = water_use_equipment.sum { |equipment| equipment.waterUseEquipmentDefinition.peakFlowRate }
      fallback_split = 1.0 / water_use_equipment.size

      water_use_equipment.each do |equipment|
        ratio = existing_peak_flow_rate_m3_per_s.positive? ? equipment.waterUseEquipmentDefinition.peakFlowRate / existing_peak_flow_rate_m3_per_s : fallback_split
        equipment.waterUseEquipmentDefinition.setPeakFlowRate(peak_flow_rate_m3_per_s * ratio)
        equipment.setFlowRateFractionSchedule(schedule) unless keep_schedule
        count += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM service water heating fields to #{count} WaterUseEquipment object(s).")
    count.positive?
  end

  def acm_swh_data_for_space_type(space_type, building_type: nil)
    return space_type_get_acm_standards_data(space_type, throw_if_not_found: true) if building_type.nil?

    lookup_building_type = building_type
    lookup_building_type ||= space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized
    lookup_building_type ||= model_get_primary_building_type(space_type.model, remap_office: false)
    standards_building_type = acm_building_type_for_lookup(lookup_building_type, throw_if_not_found: true)

    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    acm_space_type_candidates(standards_building_type, space_type.nameString).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found: true)
  end

  def acm_swh_peak_flow_rate_si(peak_flow_rate_gal_per_hr_per_ft2, floor_area_m2)
    floor_area_ft2 = OpenStudio.convert(floor_area_m2, 'm^2', 'ft^2').get
    OpenStudio.convert(peak_flow_rate_gal_per_hr_per_ft2.to_f * floor_area_ft2, 'gal/hr', 'm^3/s').get
  end

  def acm_water_use_equipment_by_space_type(model)
    water_use_by_space_type = {}
    model.getWaterUseEquipments.sort_by(&:nameString).each do |equipment|
      space_type = acm_space_type_for_water_use_equipment(equipment)
      if space_type.nil?
        OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Skipping ACM SWH for '#{equipment.nameString}' because its source SpaceType could not be found.")
        next
      end

      key = space_type.handle.to_s
      water_use_by_space_type[key] ||= { space_type:, water_use_equipment: [] }
      water_use_by_space_type[key][:water_use_equipment] << equipment
    end

    water_use_by_space_type
  end

  def acm_space_type_for_water_use_equipment(equipment)
    model = equipment.model
    if equipment.space.is_initialized
      space = equipment.space.get
      return space.spaceType.get if space.spaceType.is_initialized
    end
    return equipment.spaceType.get if equipment.spaceType.is_initialized

    equipment_name = equipment.nameString.delete_prefix('Booster ').sub(/\s+\d+\s+units\z/, '')
    model.getSpaceTypes.find { |candidate| candidate.nameString == equipment_name } ||
      model.getSpaceTypes.find { |candidate| equipment_name.start_with?(candidate.nameString) }
  end

  def model_apply_acm_hvac_availability_schedule(model, building_type: nil)
    acm_data = model_get_acm_standards_data(model, throw_if_not_found: true, building_type:)
    schedule_name = acm_data['hvac_operation_schedule']
    return false if schedule_name.nil? || schedule_name.empty?

    schedule = nil
    count_availability = 0
    HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      objects = model.respond_to?(:"get#{hvac_type}s") ? model.send(:"get#{hvac_type}s") : []
      next if objects.empty?

      schedule ||= model_add_schedule(model, schedule_name)
      model.getBuilding.additionalProperties.setFeature(ACM_HVAC_OPERATION_SCHEDULE_FEATURE, schedule_name)
      objects.each do |object|
        methods.each do |_getter, setter|
          raise "HVAC_AVAILABILITY_SCHEDULE_MAP is out of date, #{object.briefDescription} does not respond to #{setter}" unless object.respond_to?(setter)

          count_availability += 1 if object.send(setter, schedule)
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM HVAC availability schedule '#{schedule_name}' to #{count_availability} objects.")
    count_availability.positive?
  end

  # Attaches each space type's ACM lighting_schedule to its Lights objects.
  # Only the schedule is changed; lighting power (LPD) is left untouched.
  def model_apply_acm_lighting_schedule(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      lights = space_type.lights
      next if lights.empty?
      next if acm_space_type_keeps_prototype_schedule?(space_type)

      schedule_name = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)['lighting_schedule']
      next if schedule_name.nil? || schedule_name.empty?

      schedule = model_add_schedule(model, schedule_name)
      next if schedule.nil?

      lights.each { |light| count += 1 if light.setSchedule(schedule) }
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM lighting schedule to #{count} Lights object(s).")
    count.positive?
  end

  # Attaches each space type's ACM heating/cooling setpoint schedules to the
  # thermostats of the thermal zones its spaces occupy. Only the setpoint
  # schedules change; thermostats created by create_typical are reused.
  def model_apply_acm_thermostat_setpoint_schedules(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      acm_data = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)
      heating_schedule = acm_add_setpoint_schedule(model, acm_data['heating_setpoint_schedule'])
      cooling_schedule = acm_add_setpoint_schedule(model, acm_data['cooling_setpoint_schedule'])
      next if heating_schedule.nil? && cooling_schedule.nil?

      space_type.spaces.each do |space|
        next unless space.thermalZone.is_initialized

        thermostat = space.thermalZone.get.thermostatSetpointDualSetpoint
        next unless thermostat.is_initialized

        thermostat = thermostat.get
        count += 1 if heating_schedule && thermostat.setHeatingSetpointTemperatureSchedule(heating_schedule)
        count += 1 if cooling_schedule && thermostat.setCoolingSetpointTemperatureSchedule(cooling_schedule)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM thermostat setpoint schedules to #{count} schedule slot(s).")
    count.positive?
  end

  # Adds the named ACM setpoint schedule to the model, returning nil for a
  # blank name so callers can skip a missing heating or cooling column.
  def acm_add_setpoint_schedule(model, schedule_name)
    return nil if schedule_name.nil? || schedule_name.empty?

    model_add_schedule(model, schedule_name)
  end

  # Attaches each space type's ACM infiltration_schedule to the
  # SpaceInfiltrationDesignFlowRate objects on its spaces. Runs after
  # model_apply_standard_infiltration, which rebuilds space-level infiltration
  # at the ACM rate; this only sets the schedule.
  def model_apply_acm_infiltration_schedule(model)
    count = 0
    model.getSpaceTypes.sort.each do |space_type|
      schedule_name = space_type_get_acm_standards_data(space_type, throw_if_not_found: false)['infiltration_schedule']
      next if schedule_name.nil? || schedule_name.empty?

      schedule = model_add_schedule(model, schedule_name)
      next if schedule.nil?

      space_type.spaces.each do |space|
        space.spaceInfiltrationDesignFlowRates.each do |infiltration|
          count += 1 if infiltration.setSchedule(schedule)
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.acm.Model', "Applied ACM infiltration schedule to #{count} SpaceInfiltrationDesignFlowRate object(s).")
    count.positive?
  end

  # Returns the PRM wind-driven coefficient set used by the opt-in ACM infiltration.
  def model_get_infiltration_coefficients(_model)
    [0.0, 0.0, 0.224, 0.0]
  end

  # Why: ACM 2019 sets infiltration by exterior wall area at a fixed design rate.
  # What: removes space-type infiltration and applies space infiltration objects
  # to every space, conditioned or not.
  # How: sets the flat rate per exterior wall area through
  # acm_apply_space_infiltration (the vanilla PRM helper skips unconditioned spaces).
  # Used by: create-typical when an ACM standard is passed in.
  def model_apply_standard_infiltration(model, infiltration_rate: nil, prm_standard: Standard.build(PRM_2019_TEMPLATE), rate_cfm_per_ft2: ACM_INFILTRATION_RATE_CFM_PER_FT2)
    unless infiltration_rate.nil?
      OpenStudio.logFree(OpenStudio::Debug, '179d.acm.Model', "Ignoring upstream infiltration_rate #{infiltration_rate}; ACM rate is fixed.")
    end

    ela = model.getSpaceInfiltrationEffectiveLeakageAreas.sort.size
    if ela.positive?
      OpenStudio.logFree(OpenStudio::Warn, 'prm.log', 'The current model cannot include SpaceInfiltrationEffectiveLeakageArea. These objects will be skipped in modeling infiltration according to the 90.1-PRM rules.')
    end

    acm_infil_rate_m3_per_s_per_m2 = OpenStudio.convert(rate_cfm_per_ft2, 'cfm/ft^2', 'm^3/s*m^2').get
    total_exterior_wall_area_m2 = model.getSpaces.sum { |space| space.exteriorWallArea * space.multiplier }
    prm_log_dir = prm_standard.instance_variable_get(:@sizing_run_dir) || Dir.pwd
    prm_call(prm_standard, :prm_raise, total_exterior_wall_area_m2.positive?, prm_log_dir, 'Total exterior wall area in the model is 0 m2, Please check model inputs.')

    infiltration_coefficients = model_get_infiltration_coefficients(model)
    model.getSpaces.sort_by(&:nameString).each do |space|
      # The rebuild removes every space infiltration object, so set sizing-only ones aside and
      # re-add them only where the rebuilt space-level infiltration is still negligible. Space-type
      # infiltration is ignored here: its schedule is read when rebuilding, and it is removed below.
      sizing_only = space.spaceInfiltrationDesignFlowRates.select { |infil| sizing_only_infiltration?(infil) }
      sizing_only.each(&:remove)
      acm_apply_space_infiltration(space, acm_infil_rate_m3_per_s_per_m2, infiltration_coefficients)
      next if sizing_only.empty?

      rebuilt_flow = space.spaceInfiltrationDesignFlowRates.sum { |infil| infil.flowperExteriorWallArea.is_initialized ? infil.flowperExteriorWallArea.get : 0.0 }
      add_design_day_only_infiltration(space) unless rebuilt_flow.positive? && space.exteriorWallArea.positive?
    end
    model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
      space_type.spaceInfiltrationDesignFlowRates.each(&:remove)
    end

    true
  end

  # Replaces a space's infiltration with one object at the given flow per
  # exterior wall area, keeping any schedule from the old space or space-type
  # object (else always on). Applies to unconditioned spaces too.
  def acm_apply_space_infiltration(space, flow_per_exterior_wall_area, coefficients)
    model = space.model
    schedule = nil
    [space, (space.spaceType.get if space.spaceType.is_initialized)].compact.each do |owner|
      old_infiltration = owner.spaceInfiltrationDesignFlowRates.first
      schedule ||= old_infiltration.schedule.get if old_infiltration && old_infiltration.schedule.is_initialized
    end
    if schedule.nil?
      schedule = model.alwaysOnDiscreteSchedule
    else
      schedule.setScheduleTypeLimits(
        OpenstudioStandards::Schedules.create_schedule_type_limits(model, name: 'Infiltration Schedule Type Limits', lower_limit_value: 0.0, upper_limit_value: 1.0, numeric_type: 'Continuous', unit_type: 'Dimensionless')
      )
    end

    space.spaceInfiltrationDesignFlowRates.each(&:remove)
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration.setName("#{space.name} Infiltration")
    infiltration.setFlowperExteriorWallArea(flow_per_exterior_wall_area.round(13)) if space.exteriorWallArea > 0
    infiltration.setSchedule(schedule)
    infiltration.setConstantTermCoefficient(coefficients[0]) unless coefficients[0].nil?
    infiltration.setTemperatureTermCoefficient(coefficients[1]) unless coefficients[1].nil?
    infiltration.setVelocityTermCoefficient(coefficients[2]) unless coefficients[2].nil?
    infiltration.setVelocitySquaredTermCoefficient(coefficients[3]) unless coefficients[3].nil?
    infiltration.setSpace(space)
    infiltration
  end

  def acm_building_type_for_lookup(building_type, throw_if_not_found: true)
    acm_building_type = ACM_BUILDING_TYPE_BY_PROTOTYPE.fetch(building_type, model_get_lookup_name(building_type))
    rows = model_find_objects(
      standards_data['space_types'] || [],
      'template' => template,
      'building_type' => acm_building_type
    )
    return acm_building_type unless rows.empty?

    msg = "No 179D ACM space-type rows for building type '#{building_type}' (resolved as '#{acm_building_type}')."
    if throw_if_not_found
      OpenStudio.logFree(OpenStudio::Error, '179d.acm.Model', msg)
      raise msg
    end

    OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', msg)
    nil
  end

  def acm_hvac_operation_schedule_properties(standards_building_type)
    rows = model_find_objects(
      standards_data['space_types'] || [],
      'template' => template,
      'building_type' => standards_building_type
    )
    rows.find { |row| !row['hvac_operation_schedule'].to_s.empty? } || {}
  end

  # Returns the ACM HVAC operation schedule for the make-up mixing when the model
  # carries the ACM availability feature. Nil means: follow the exhaust fan.
  def exhaust_makeup_mixing_schedule(model, building_type: nil)
    return nil unless model.getBuilding.additionalProperties.hasFeature(ACM_HVAC_OPERATION_SCHEDULE_FEATURE)

    schedule_name = model_get_acm_standards_data(model, throw_if_not_found: true, building_type:)['hvac_operation_schedule']
    model_add_schedule(model, schedule_name)
  end
end
