require_relative '179d_acm_2019'

# ACM 2005 reuses every 179D ACM lookup and apply method from the 2019 overlay;
# only the template string and the data files it loads differ. On the baseline
# path 179D sources the SWH schedule/load, the interior lighting usage schedule,
# and the infiltration rate from ACM 2005.
class ACM179dACM2005 < ACM179dACM2019
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

  # The ACM 2005 school schedules already model the summer break, so there is no
  # prototype schedule to preserve: the baseline applies the ACM 2005 (2007
  # prototype) lighting and SWH schedules to PrimarySchool/SecondarySchool too.
  def acm_space_type_keeps_prototype_schedule?(_space_type)
    false
  end
end
