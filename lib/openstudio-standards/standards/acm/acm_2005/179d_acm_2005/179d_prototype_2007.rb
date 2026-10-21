require_relative '179d_acm_2019'

# 179D Prototype 2007 sources the SWH schedule/load, the interior lighting usage
# schedule, and the infiltration rate from ASHRAE 90.1-2007 DOE prototype building values.
class Prototype179d2007 < ACM179dACM2019
  register_standard '179D Prototype 2007'
  register_standard '179D ACM 2005'

  ACM_TEMPLATE = '179d-ACM-2005'.freeze
  ACM_SCHEDULES_FILE = '179d_acm_2005.schedules.json'.freeze
  ACM_SPACE_TYPES_FILE = '179d_acm_2005.spc_typ.json'.freeze

  def acm_template
    ACM_TEMPLATE
  end

  def acm_data_files
    [ACM_SCHEDULES_FILE, ACM_SPACE_TYPES_FILE]
  end

  def model_apply_prototype_service_water_heating(model, building_type: nil)
    lookup_type = building_type ? acm_building_type_for_lookup(building_type, throw_if_not_found: false) : nil
    if building_type && lookup_type.nil?
      OpenStudio.logFree(OpenStudio::Warn, '179d.acm.Model', "Skipping prototype SWH override for building type '#{building_type}' because it has no 2007 prototype space type rows.")
      return false
    end

    model_apply_acm_service_water_heating(model, building_type:)
  end

  def model_apply_prototype_lighting_schedule(model)
    model_apply_acm_lighting_schedule(model)
  end

  # All 2007 prototype schedules are applied directly; there is no 2019
  # prototype schedule to preserve.
  def acm_space_type_keeps_prototype_schedule?(_space_type)
    false
  end
end

# Backward compatibility alias for the legacy class name
ACM179dACM2005 = Prototype179d2007
