class ASHRAE901PRM2019 < ASHRAE901PRM
  # Apply the prm parameter to a water heater based on the
  # building area type.
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @param building_type_swh [String] the swh building are type
  # @return [Boolean] returns true if successful, false if not
  def model_apply_water_heater_prm_parameter(water_heater_mixed, building_type_swh)
    new_fuel = water_heater_mixed_apply_prm_baseline_fuel_type(building_type_swh)
    water_heater_mixed.setHeaterFuelType(new_fuel)
    unless water_heater_mixed_apply_efficiency(water_heater_mixed)
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, could not apply baseline water heater efficiency after changing fuel to #{new_fuel}.")
      return false
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, changed baseline water heater fuel to #{new_fuel}.")
    true
  end

  def water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
    search_criteria = {
      'template' => template,
      'fuel_type' => fuel_type,
      'product_class' => water_heater_mixed_prm_storage_product_class(fuel_type)
    }

    wh_props = water_heater_mixed_find_efficiency_requirement(search_criteria, capacity_btu_per_hr, volume_gal)
    return wh_props unless wh_props == {}

    search_criteria = water_heater_mixed_additional_search_criteria(water_heater_mixed, search_criteria)
    water_heater_mixed_find_efficiency_requirement(search_criteria, capacity_btu_per_hr, volume_gal)
  end

  def water_heater_mixed_find_efficiency_requirement(search_criteria, capacity_btu_per_hr, volume_gal)
    [
      model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr),
      model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal.round(0)),
      model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, nil, capacity_btu_per_hr),
      model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal, capacity_btu_per_hr / volume_gal)
    ].each do |rows|
      return rows[0] if rows.size == 1
    end

    {}
  end

  def water_heater_mixed_additional_search_criteria(_water_heater_mixed, search_criteria)
    search_criteria['draw_profile'] = 'medium'
    search_criteria
  end

  def water_heater_mixed_prm_storage_product_class(fuel_type)
    fuel_type == 'Electricity' ? 'Water Heaters' : 'Storage Water Heater'
  end

  # Apply the prm fuel type to a water heater based on the
  # building area type.
  # @param building_type [String] the building type (For consistency with the standard class, not used in the method)
  # @return [String] returns fuel type
  def water_heater_mixed_apply_prm_baseline_fuel_type(building_type)
    # Get the fuel type data
    heater_prop = model_find_object(standards_data['prm_swh_bldg_type'], { 'swh_building_type' => building_type })
    new_fuel_data = heater_prop['baseline_heating_method']
    # There are only two water heater fuel type in the prm database:
    # ("Gas Storage" and "Electric Resistance Storage")
    # Change the prm fuel type to openstudio fuel type
    if new_fuel_data == 'Gas Storage'
      new_fuel = 'NaturalGas'
    else
      new_fuel = 'Electricity'
    end
    return new_fuel
  end
end
