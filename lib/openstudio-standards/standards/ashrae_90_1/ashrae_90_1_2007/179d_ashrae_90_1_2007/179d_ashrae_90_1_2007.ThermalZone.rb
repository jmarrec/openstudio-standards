class ACM179dASHRAE9012007
  # 179D ACM mandates that Kitchen, Restroom, and Cafeteria zone exhaust fans
  # operate on the building's HVAC operation schedule (per IRS Notice 2006-52
  # §3.03 / CA 2005 ACM Tables N2-2..N2-9), not the always-on default that
  # OpenstudioStandards::HVAC.create_exhaust_fan applies in standards 0.8.x.
  # Call super for the stock fan creation: sized from typical_exhaust.csv,
  # BUT DO NOT required transfer-air zone mixing
  #
  # We then balance the flows ourselves, because it will not do it because cafeteria is too far away from Kitchen
  #
  # Finally, replace availability and flow-fraction schedules on those three space types with the ACM schedule.

  ACM_EXHAUST_SPACE_TYPES = ['Kitchen', 'Restroom', 'Cafeteria'].freeze

  # Add Exhaust Fans based on space type lookup.
  # This measure doesn't look if DCV is needed.
  # Others methods can check if DCV needed and add it.
  # NOTE: 179D override to add infiltration manually to balance the Kitchen and
  # Restroom exhaust fans
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] thermal zone
  # @param exhaust_makeup_inputs [Hash] has of makeup exhaust inputs
  # @return [OpenStudio::Model::FanZoneExhaust] The created exhaust fan, or nil
  def thermal_zone_add_exhaust(thermal_zone, _exhaust_makeup_inputs = {})
    data = model_get_standards_data(thermal_zone.model, throw_if_not_found: true)
    acm_fan_sch_name = data['hvac_operation_schedule']
    acm_fan_sch = model_add_schedule(thermal_zone.model, acm_fan_sch_name)

    zone_exhaust_fan = OpenstudioStandards::HVAC.create_exhaust_fan(thermal_zone)
    return nil if zone_exhaust_fan.nil?

    # set fan pressure rise
    fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)

    # update efficiency and pressure rise
    prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)

    space_type_hash = {} # key is space type value is floor_area_si
    thermal_zone.spaces.each do |space|
      next unless space.spaceType.is_initialized
      next unless space.partofTotalFloorArea

      space_type = space.spaceType.get
      if space_type_hash.key?(space_type)
        space_type_hash[space_type] += space.floorArea # excluding space.multiplier since used to calc loads in zone
      else
        next unless space_type.standardsBuildingType.is_initialized
        next unless space_type.standardsSpaceType.is_initialized

        space_type_hash[space_type] = space.floorArea # excluding space.multiplier since used to calc loads in zone
      end
    end
    space_type = space_type_hash.max_by { |_space_type, area| area }.first

    # Set to first in line, because we do that voluntarily AFTER the hvac has been added
    thermal_zone.setHeatingPriority(zone_exhaust_fan, 0)
    thermal_zone.setCoolingPriority(zone_exhaust_fan, 0)

    maximum_flow_rate_si = zone_exhaust_fan.maximumFlowRate.get

    # NOTE: 179D - Balance it up with infiltration
    if ACM_EXHAUST_SPACE_TYPES.include?(space_type.standardsSpaceType.get)
      space = thermal_zone.spaces.first
      OpenStudio.logFree(OpenStudio::Warn, '179d.Standards.ThermalZone', "adding make up #{space_type.standardsSpaceType.get} infiltration object: thermal zone = '#{thermal_zone.nameString}' | space= '#{space.nameString}'")
      air_terminal = thermal_zone.airLoopHVACTerminal
      if air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized
        air_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
        air_terminal.setMaximumAirFlowRate(maximum_flow_rate_si) # Add an abitrary multiplier here?
        # Is this needed?
        sz = thermal_zone.sizingZone
        sz.setCoolingDesignAirFlowMethod('DesignDayWithLimit')
        sz.setCoolingMinimumAirFlow(maximum_flow_rate_si)
        sz.setHeatingDesignAirFlowMethod('DesignDayWithLimit')
        sz.setHeatingMaximumAirFlow(maximum_flow_rate_si)
      else
        OpenStudio.logFree(OpenStudio::Warn, '179d.Standards.ThermalZone', '=' * 80)
        OpenStudio.logFree(OpenStudio::Warn, '179d.Standards.ThermalZone', "Zone #{thermal_zone.nameString}")
        equipment = thermal_zone.equipment.map(&:to_s).join("\n")
        OpenStudio.logFree(OpenStudio::Warn, '179d.Standards.ThermalZone', equipment.to_s)

        makeup_infiltration_for_exhaust_fan = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(thermal_zone.model)
        makeup_infiltration_for_exhaust_fan.setName("#{zone_exhaust_fan.name} Makeup infil")
        makeup_infiltration_for_exhaust_fan.setDesignFlowRate(maximum_flow_rate_si)
        makeup_infiltration_for_exhaust_fan.setSpace(space)
        makeup_infiltration_for_exhaust_fan.setSchedule(acm_fan_sch)
        zone_exhaust_fan.setBalancedExhaustFractionSchedule(thermal_zone.model.alwaysOnDiscreteSchedule)
      end

      zone_exhaust_fan.setAvailabilitySchedule(acm_fan_sch)
      zone_exhaust_fan.setFlowFractionSchedule(acm_fan_sch)

    end

    zone_exhaust_fan
  end
end
