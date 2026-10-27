require_relative 'crop_2019'

# CROP Prototype 2007 applies the SWH schedule and the interior lighting schedule
# from the ASHRAE 90.1-2007 DOE prototype buildings to the baseline.
class CROPPrototype2007 < CROP2019
  register_standard 'CROP Prototype 2007'
  register_standard '179D Prototype 2007'

  def initialize
    super()
    @template = 'CROP Prototype 2007'
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

    OpenStudio.logFree(OpenStudio::Info, '179d.prototype.Model', "Applied 2007 prototype lighting schedule to #{count} Lights object(s).")
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
        OpenStudio.logFree(OpenStudio::Debug, '179d.prototype.Model', "Could not determine primary building type: #{e.message}")
      end
    end

    equipments.sort.each do |equipment|
      schedule_name = nil

      # 1. Look up from space type if available
      space = equipment.space
      if space.is_initialized
        space_type = space.get.spaceType
        if space_type.is_initialized
          props = prototype_space_type_properties(std_2007, space_type.get)
          schedule_name = props['service_water_heating_schedule'] if props && props['service_water_heating_schedule'] && !props['service_water_heating_schedule'].empty?
        end
      end

      # 2. Fall back to primary building type SWH schedule
      if (schedule_name.nil? || schedule_name.empty?) && primary_bldg_type
        candidate_rows = std_2007.standards_data['space_types'].select do |r|
          r['building_type'] == primary_bldg_type && r['service_water_heating_schedule'] && !r['service_water_heating_schedule'].empty?
        end
        schedule_name = candidate_rows.first['service_water_heating_schedule'] unless candidate_rows.empty?
      end

      next if schedule_name.nil? || schedule_name.empty?

      schedule = std_2007.model_add_schedule(model, schedule_name)
      next if schedule.nil?

      count += 1 if equipment.setFlowRateFractionSchedule(schedule)
    end

    OpenStudio.logFree(OpenStudio::Info, '179d.prototype.Model', "Applied 2007 prototype SWH schedule to #{count} WaterUseEquipment object(s).")
    count.positive?
  end
end

# Old name of the prototype class. Kept so old tests and scripts still work.
Prototype179d2007 = CROPPrototype2007
