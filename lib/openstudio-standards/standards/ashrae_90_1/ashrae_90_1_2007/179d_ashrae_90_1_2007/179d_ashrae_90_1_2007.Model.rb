class ACM179dASHRAE9012007
  def self.__model_get_primary_building_type(model)
    building_types = {}

    building = model.getBuilding
    building_level_bt = nil
    if building.standardsBuildingType.is_initialized
      building_level_bt =building.standardsBuildingType.get
      building_level_bt = model_get_lookup_name(building_level_bt)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found Building level standardsBuildingType = '#{building_level_bt}'")
    end

    model.getSpaceTypes.sort.each do |space_type|
      # populate hash of building types
      if !space_type.standardsBuildingType.is_initialized
        next
      end

      bldg_type = space_type.standardsBuildingType.get
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found building type for Space Type '#{space_type.name}' = '#{bldg_type}'")
      if building_types.key?(bldg_type)
        building_types[bldg_type] += space_type.floorArea
      else
        building_types[bldg_type] = space_type.floorArea
      end
    end

    if building_types.empty?
      if building_level_bt.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot identify a single building type in model, none of your #{model.getSpaceTypes.size} SpaceTypes have a standardsBuildingType assigned and neither does the Building")
        raise 'No Primary Building Type found'
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "No area determination based on space types found, using Building level standardsBuildingType = '#{building_level_bt}'")
        return building_level_bt
      end
    end

    space_type_level_bt = building_types.max_by { |_, v| v }.first
    space_type_level_bt = model_get_lookup_name(space_type_level_bt)
    if !building_level_bt.nil?
      if building_level_bt != space_type_level_bt
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "The Building has standardsBuildingType '#{building_level_bt}' while the area determination based on space types has '#{space_type_level_bt}'. Preferring the Space Type one")
      end
      return space_type_level_bt
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Building doesn't have a standardsBuildingType, using the area determination based on space types = '#{space_type_level_bt}'")
    return space_type_level_bt
  end

  def model_get_primary_building_type(model)
    # Maybe this is a premature optimization, but memoize the computation
    @primary_building_types_memoized ||= Hash.new do |h, key|
      h[key] = ACM179dASHRAE9012007.__model_get_primary_building_type(model)
    end
    @primary_building_types_memoized[model]
  end

  # Patched to prefer the space area method above instead of just relying on
  # Building object
  def model_get_building_properties(model, remap_office = true)
    # get climate zone from model
    climate_zone = model_standards_climate_zone(model)

    # get building type from model
    building_type = model_get_primary_building_type(model)

    # map office building type to small medium or large
    if building_type == 'Office' && remap_office
      open_studio_area = model.getBuilding.floorArea
      building_type = model_remap_office(model, open_studio_area)
    end

    # get standards template
    if model.getBuilding.standardsTemplate.is_initialized
      standards_template = model.getBuilding.standardsTemplate.get
    end

    results = {}
    results['climate_zone'] = climate_zone
    results['building_type'] = building_type
    results['standards_template'] = standards_template

    return results
  end

  # Determines which system number is used
  # for the baseline system.
  # @return [String] the system number: 1_or_2, 3_or_4,
  # 5_or_6, 7_or_8, 9_or_10
  def model_prm_baseline_system_number(_model, _climate_zone, area_type, _fuel_type, area_ft2, num_stories, custom)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.prm', '179d: Heat Storage area applied as 90.1-2007 with addenda dn')
    sys_num = nil

    # Set the area limit
    limit_ft2 = 25_000

    # Customization for Xcel EDA.
    # No special retail category
    # for regular 90.1-2010.
    if custom != 'Xcel Energy CO EDA' && (area_type == 'retail')
      area_type = 'nonresidential'
    end

    case area_type
    when 'residential'
      sys_num = '1_or_2'
    when 'nonresidential'
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
    when 'heatedonly'
      sys_num = '9_or_10'
    when 'retail'
      # Should only be hit by Xcel EDA
      sys_num = '3_or_4'
    end

    return sys_num
  end


  BT_TO_HVAC_OPERATION_SCHEDULE_NAMES = {
    'FullServiceRestaurant' => 'Nonres_HVAC_Sch',
    'Office' => 'Nonres_HVAC_Sch',
    'PrimarySchool' => 'SchoolPrimary_HVAC_Sch',
    'QuickServiceRestaurant' => 'Nonres_HVAC_Sch',
    'Retail' => 'Retail_HVAC_Sch',
    'SmallHotel' => 'Res_HVAC_Sch',
    'StripMall' => 'Retail_HVAC_Sch',
    'Warehouse' => 'Nonres_HVAC_Sch'
  }

  def hvac_operation_schedule_name(model)
    bt = model_get_primary_building_type(model)
    name = BT_TO_HVAC_OPERATION_SCHEDULE_NAMES[bt]
    if name.nil?
      raise "Building type #{bt} is not supported"
    end
    return name
  end

end
