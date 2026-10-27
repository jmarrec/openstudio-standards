require 'date'

# Steps that both passes use: building type, NIST infiltration, occupancy-based HVAC and
# exhaust availability, heated-only ventilation, sizing-only infiltration, reheat headroom,
# and the window helpers of the reporting measure.
module CropCommon
  PRM_2019_TEMPLATE = '90.1-PRM-2019'.freeze

  EXHAUST_ZONE_SPACE_TYPES = ['Kitchen', 'Restroom', 'Cafeteria'].freeze
  SIZING_ONLY_INFILTRATION_FEATURE = '179d_sizing_only_infiltration'.freeze

  # NIST infiltration inputs: airtightness at 75 Pa for each pass, 6-sided area, air barrier.
  NIST_INFILTRATION_PROPOSED_CFM_PER_FT2 = 0.6
  NIST_INFILTRATION_BASELINE_CFM_PER_FT2 = 1.0
  NIST_INFILTRATION_AREA_COVERED = '6-sided'.freeze
  NIST_INFILTRATION_AIR_BARRIER = true

  REHEAT_MAX_AIR_TEMPERATURE_C = 43.3

  ZONE_HVAC_EQUIPMENT_CAST_METHODS = [
    :to_ZoneHVACPackagedTerminalAirConditioner,
    :to_ZoneHVACPackagedTerminalHeatPump,
    :to_ZoneHVACWaterToAirHeatPump,
    :to_ZoneHVACFourPipeFanCoil,
    :to_ZoneHVACTerminalUnitVariableRefrigerantFlow,
    :to_ZoneHVACUnitHeater,
    :to_ZoneHVACUnitVentilator,
    :to_ZoneHVACBaseboardConvectiveElectric,
    :to_ZoneHVACBaseboardConvectiveWater,
    :to_ZoneHVACBaseboardRadiantConvectiveElectric,
    :to_ZoneHVACBaseboardRadiantConvectiveWater,
    :to_ZoneHVACCoolingPanelRadiantConvectiveWater,
    :to_ZoneHVACDehumidifierDX,
    :to_ZoneHVACEnergyRecoveryVentilator,
    :to_ZoneHVACHighTemperatureRadiant,
    :to_ZoneHVACIdealLoadsAirSystem,
    :to_ZoneHVACLowTemperatureRadiantElectric,
    :to_ZoneHVACLowTempRadiantConstFlow,
    :to_ZoneHVACLowTempRadiantVarFlow,
    :to_AirLoopHVACUnitarySystem
  ].freeze

  HVAC_HOURS_OF_OPERATION_SCHEDULE_NAME = '179D HVAC Hours of Operation'.freeze
  # A low threshold keeps HVAC on whenever the building has any real occupancy,
  # so lightly occupied early and late hours do not become unmet hours.
  HVAC_HOURS_OF_OPERATION_OCC_FRACTION = 0.05

  # Zone HVAC types that already deliver outdoor air; the reporting measure counts
  # their OA, so adding ZoneVentilation on top would double-count ventilation.
  OA_PROVIDING_ZONE_HVAC_METHODS = [
    :to_ZoneHVACPackagedTerminalAirConditioner,
    :to_ZoneHVACPackagedTerminalHeatPump,
    :to_ZoneHVACWaterToAirHeatPump,
    :to_ZoneHVACFourPipeFanCoil,
    :to_ZoneHVACTerminalUnitVariableRefrigerantFlow,
    :to_ZoneHVACUnitVentilator,
    :to_ZoneHVACEnergyRecoveryVentilator
  ].freeze

  def cast_zone_hvac_equipment(equipment)
    ZONE_HVAC_EQUIPMENT_CAST_METHODS.each do |meth|
      if equipment.respond_to?(meth)
        opt = equipment.send(meth)
        return opt.get if opt.is_initialized
      end
    end
    equipment
  end

  # Helper to set availability schedule across diverse zone HVAC equipment types
  # (including VRF terminal units which use setTerminalUnitAvailabilityschedule).
  def set_zone_hvac_availability_schedule(equipment, schedule)
    if equipment.respond_to?(:setAvailabilitySchedule)
      equipment.setAvailabilitySchedule(schedule)
    elsif equipment.respond_to?(:setTerminalUnitAvailabilityschedule)
      equipment.setTerminalUnitAvailabilityschedule(schedule)
    end
  end

  # Helper to set outdoor air schedule across zone HVAC equipment types
  # (e.g. setOutdoorAirSchedule for FanCoil, setMinimumOutdoorAirSchedule for UnitVentilator).
  def set_zone_hvac_outdoor_air_schedule(equipment, schedule)
    if equipment.respond_to?(:setOutdoorAirSchedule)
      equipment.setOutdoorAirSchedule(schedule)
    elsif equipment.respond_to?(:setMinimumOutdoorAirSchedule)
      equipment.setMinimumOutdoorAirSchedule(schedule)
    end
  end

  # Returns true if the supply fan of the equipment is a Fan:ConstantVolume.
  def supply_fan_constant_volume?(equipment)
    fan = if equipment.respond_to?(:supplyAirFan)
            equipment.supplyAirFan
          elsif equipment.respond_to?(:supplyFan)
            equipment.supplyFan
          end
    fan = fan.is_initialized ? fan.get : nil if fan.respond_to?(:is_initialized)
    !fan.nil? && fan.to_FanConstantVolume.is_initialized
  end

  # Sets the supply fan operating mode schedule (0 = cycle, 1 = continuous).
  # EnergyPlus requires a constant-volume fan to run continuously, so that fan always gets always on.
  def set_supply_air_fan_operating_mode_schedule(equipment, schedule)
    return false unless equipment.respond_to?(:setSupplyAirFanOperatingModeSchedule)

    schedule = equipment.model.alwaysOnDiscreteSchedule if supply_fan_constant_volume?(equipment)
    equipment.setSupplyAirFanOperatingModeSchedule(schedule)
  end

  # Returns the HVAC hours of operation schedule, inferred from occupancy.
  # It ignores the building hours of operation schedule and restores it after
  # the inference, because the inference overwrites it on every default schedule set.
  def model_get_or_infer_hours_of_operation_building(model)
    hoo_sched = model.getScheduleRulesets.find { |s| s.nameString == HVAC_HOURS_OF_OPERATION_SCHEDULE_NAME }
    return hoo_sched if hoo_sched
    return model.alwaysOnDiscreteSchedule unless model.getSpaces.any? { |sp| sp.numberOfPeople.positive? }

    building = model.getBuilding
    had_building_set = building.defaultScheduleSet.is_initialized
    previous_hoo = model.getDefaultScheduleSets.map { |set| [set, set.hoursofOperationSchedule] }
    previous_set_handles = previous_hoo.map { |set, _sch| set.handle.to_s }
    begin
      inferred = OpenstudioStandards::Schedules.model_infer_hours_of_operation_building(model, fraction_of_daily_occ_range: HVAC_HOURS_OF_OPERATION_OCC_FRACTION)
      inferred.setName(HVAC_HOURS_OF_OPERATION_SCHEDULE_NAME)
      hoo_sched = inferred
    rescue StandardError => e
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', "Could not infer HVAC hours of operation schedule: #{e.message}. Using Always On.")
    ensure
      previous_hoo.each do |set, sch|
        sch.is_initialized ? set.setHoursofOperationSchedule(sch.get) : set.resetHoursofOperationSchedule
      end
      unless had_building_set
        added_set = building.defaultScheduleSet
        building.resetDefaultScheduleSet
        added_set.get.remove if added_set.is_initialized && !previous_set_handles.include?(added_set.get.handle.to_s)
      end
    end
    hoo_sched || model.alwaysOnDiscreteSchedule
  end

  # Returns the HVAC hours of operation schedule for a group of zones: on when
  # their occupancy is at least HVAC_HOURS_OF_OPERATION_OCC_FRACTION of design.
  # Zones without people use the building schedule, so their HVAC does not stay off.
  def zones_hvac_hours_of_operation_schedule(model, zones, name_prefix)
    sch_name = "#{name_prefix} #{HVAC_HOURS_OF_OPERATION_SCHEDULE_NAME}"
    existing = model.getScheduleRulesets.find { |s| s.nameString == sch_name }
    return existing if existing
    return model_get_or_infer_hours_of_operation_building(model) unless zones.any? { |z| z.numberOfPeople.positive? }

    sch = OpenstudioStandards::ThermalZone.thermal_zones_get_occupancy_schedule(zones, sch_name:, occupied_percentage_threshold: HVAC_HOURS_OF_OPERATION_OCC_FRACTION)
    sch.is_a?(OpenStudio::Model::Schedule) ? sch : model_get_or_infer_hours_of_operation_building(model)
  end

  # Returns a schedule that is on in each hour that any of the given schedules is on.
  # A schedule with the same name is reused only if it has the same hours.
  def union_hvac_hours_of_operation_schedule(model, schedules, sch_name)
    schedules = schedules.uniq
    return schedules.first if schedules.size == 1

    on_hours = schedules.map { |s| OpenstudioStandards::Schedules.schedule_get_hourly_values(s) }.transpose.map { |vals| vals.any?(&:positive?) ? 1.0 : 0.0 }
    existing = model.getScheduleRulesets.find { |s| s.nameString == sch_name }
    return existing if existing && OpenstudioStandards::Schedules.schedule_get_hourly_values(existing) == on_hours

    existing&.setName("#{sch_name} Superseded")
    # Group days by day of week, because one rule applies to every matching day of week in its date range.
    year = model.getYearDescription.assumedYear
    days_by_profile = Hash.new { |h, k| h[k] = [] }
    on_hours.each_slice(24).with_index do |profile, i|
      days_by_profile[[OpenStudio::Date.fromDayOfYear(i + 1, year).dayOfWeek.valueName, profile]] << (i + 1)
    end
    default_profile = days_by_profile.group_by { |(_day, profile), _days| profile }.max_by { |_profile, groups| groups.sum { |_key, days| days.size } }.first

    sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sch.setName(sch_name)
    OpenstudioStandards::Schedules.schedule_day_populate_from_array_of_values(sch.defaultDaySchedule, default_profile)
    days_by_profile.each do |(_day, profile), days|
      next if profile == default_profile

      OpenstudioStandards::Schedules.schedule_ruleset_create_rules_from_day_list(sch, days).each do |rule|
        OpenstudioStandards::Schedules.schedule_day_populate_from_array_of_values(rule.daySchedule, profile)
      end
    end
    # On for design days, the same as the occupancy-based zone schedules.
    design_day = OpenStudio::Model::ScheduleDay.new(model, 1.0)
    sch.setSummerDesignDaySchedule(design_day)
    sch.setWinterDesignDaySchedule(design_day)
    design_day.remove
    sch
  end

  # Sets HVAC and exhaust availability from zone occupancy (on at 5% of design people).
  # - Exhaust fans and their make-up mixing follow their zone.
  # - Air loops are on when any served zone is on. Night cycling holds the setback.
  # - Zone units are always available, so the thermostat holds the setback. Units
  #   that supply OA directly (no DOAS) run the fan continuously when the zone is on.
  # - A constant-volume supply fan always runs continuously, because EnergyPlus requires it.
  # - NIST infiltration schedules follow the new HVAC schedule.
  def model_apply_occupancy_hvac_and_exhaust_availability_schedules(model)
    zone_sched = {}
    zone_hoo = ->(zone) { zone_sched[zone.handle.to_s] ||= zones_hvac_hours_of_operation_schedule(model, [zone], zone.nameString) }

    # 1. Exhaust fans follow the schedule of their zone
    model.getFanZoneExhausts.each do |fan|
      sch = fan.thermalZone.is_initialized ? zone_hoo.call(fan.thermalZone.get) : model_get_or_infer_hours_of_operation_building(model)
      fan.setAvailabilitySchedule(sch)
      fan.setFlowFractionSchedule(sch)
      mixing = model.getZoneMixings.find { |zm| zm.nameString == "#{fan.nameString} Makeup mixing" }
      mixing.setSchedule(sch) if mixing
    end

    # 2. Central air loops are on when any zone they serve with people is on
    loop_sched = {}
    model.getAirLoopHVACs.each do |air_loop|
      zone_schedules = air_loop.thermalZones.select { |zone| zone.numberOfPeople.positive? }.map { |zone| zone_hoo.call(zone) }
      sch_name = "#{air_loop.nameString} #{HVAC_HOURS_OF_OPERATION_SCHEDULE_NAME}"
      loop_sched[air_loop.handle.to_s] = zone_schedules.empty? ? model_get_or_infer_hours_of_operation_building(model) : union_hvac_hours_of_operation_schedule(model, zone_schedules, sch_name)
      air_loop.setAvailabilitySchedule(loop_sched[air_loop.handle.to_s])
    end

    # 3. Unitary systems: continuous fan when occupied, cycling fan when unoccupied
    model.getAirLoopHVACUnitarySystems.each do |unitary|
      sch = if unitary.airLoopHVAC.is_initialized
              loop_sched[unitary.airLoopHVAC.get.handle.to_s]
            elsif unitary.controllingZoneorThermostatLocation.is_initialized
              zone_hoo.call(unitary.controllingZoneorThermostatLocation.get)
            end
      set_supply_air_fan_operating_mode_schedule(unitary, sch || model_get_or_infer_hours_of_operation_building(model))
    end

    # 4. Zone HVAC equipment
    model.getThermalZones.each do |zone|
      zone_has_doas = zone.airLoopHVACs.any? do |al|
        al.nameString =~ /doas/i || al.sizingSystem.typeofLoadtoSizeOn.to_s == 'VentilationRequirement'
      end
      zone.equipment.each do |raw_eq|
        next if raw_eq.to_FanZoneExhaust.is_initialized
        next if raw_eq.iddObjectType.valueDescription =~ /AirTerminal/i

        eq = cast_zone_hvac_equipment(raw_eq)
        set_zone_hvac_availability_schedule(eq, model.alwaysOnDiscreteSchedule)

        is_oa_providing = OA_PROVIDING_ZONE_HVAC_METHODS.any? { |meth| raw_eq.respond_to?(meth) && raw_eq.send(meth).is_initialized }
        if !is_oa_providing && raw_eq.respond_to?(:to_AirLoopHVACUnitarySystem) && raw_eq.to_AirLoopHVACUnitarySystem.is_initialized
          is_oa_providing = raw_eq.to_AirLoopHVACUnitarySystem.get.airLoopHVACOutdoorAirSystem.is_initialized
        end

        if is_oa_providing && !zone_has_doas
          hoo_sched = zone_hoo.call(zone)
          set_supply_air_fan_operating_mode_schedule(eq, hoo_sched)
          set_zone_hvac_outdoor_air_schedule(eq, hoo_sched)
        else
          set_supply_air_fan_operating_mode_schedule(eq, model.alwaysOffDiscreteSchedule)
        end
      end
    end

    sync_nist_infiltration_schedules(model)
    true
  end

  # Returns the NIST airtightness value in m^3/h-m^2 for a rate in cfm/ft^2.
  def nist_airtightness_value(rate_cfm_per_ft2)
    OpenStudio.convert(rate_cfm_per_ft2, 'cfm/ft^2', 'm^3/s*m^2').get * 3600.0
  end

  # Replaces all infiltration with NIST correlations at the given rate at 75 Pa.
  # Re-adds sizing-only infiltration to spaces that get no NIST infiltration.
  # Leaves the model unchanged and returns false if NIST has no data for the model.
  def model_apply_nist_infiltration(model, rate_cfm_per_ft2)
    sizing_only_spaces = model.getSpaceInfiltrationDesignFlowRates.select { |infil| sizing_only_infiltration?(infil) && infil.space.is_initialized }
                              .map { |infil| infil.space.get }.uniq { |space| space.handle.to_s }
    applied = OpenstudioStandards::Infiltration.model_set_nist_infiltration(model,
                                                                            airtightness_value: nist_airtightness_value(rate_cfm_per_ft2),
                                                                            airtightness_area_covered: NIST_INFILTRATION_AREA_COVERED,
                                                                            air_barrier: NIST_INFILTRATION_AIR_BARRIER)
    unless applied
      OpenStudio.logFree(OpenStudio::Warn, 'crop.Model', 'NIST infiltration was not applied. The model keeps its existing infiltration.')
      return false
    end

    sizing_only_spaces.each { |space| add_design_day_only_infiltration(space) if space.spaceInfiltrationDesignFlowRates.empty? }
    true
  end

  # Why: heated-only zones have no air loop, so the baseline and proposed models
  # need an explicit, matching outdoor air source for them.
  # What: adds equivalent ZoneVentilation to every zone that is heated but not
  # cooled, has no air loop, and has no other OA source.
  # How: selects zones by thermal_zone_heated?/thermal_zone_cooled? rather than
  # by equipment type, so baseboard and radiant zones qualify too; skips zones
  # that already have ZoneVentilation or an OA-delivering zone HVAC unit.
  # Used by: baseline post-overrides and proposed normalization.
  def add_heated_only_zone_ventilation(model)
    heated_only_zones = model.getThermalZones.select do |zone|
      next false unless zone.airLoopHVACs.empty?
      next false if zone.equipment.any? { |equipment| equipment.to_ZoneVentilationDesignFlowRate.is_initialized }
      next false if zone.equipment.any? { |equipment| OA_PROVIDING_ZONE_HVAC_METHODS.any? { |meth| equipment.send(meth).is_initialized } }

      OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && !OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
    end
    return if heated_only_zones.empty?

    OpenStudio.logFree(OpenStudio::Info, 'crop.Model', "Adding ZoneVentilationDesignFlowRate to #{heated_only_zones.size} heated-only zone(s).")
    model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(model, heated_only_zones, ventilation_type: 'Exhaust')
  end

  # Why: heated-only ventilation needs explicit fan and sizing support.
  # What: creates ZoneVentilation and optional design-day infiltration per zone.
  # How: converts each zone DSOA rate to flow per floor area and assigns fan
  # pressure based on the selected ventilation type.
  # Used by: add_heated_only_zone_ventilation.
  def model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(model, zones, ventilation_type: 'Natural', ensure_ddy_infiltration: true)
    zones.sort.each do |zone|
      total_oa_m3_per_s = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
      total_oa_m3_per_m2s = total_oa_m3_per_s / zone.floorArea
      next unless total_oa_m3_per_s.positive?

      ventilation = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
      ventilation.setName("#{zone.name} Ventilation")
      ventilation.setSchedule(model.alwaysOnDiscreteSchedule)
      ventilation.setFlowRateperZoneFloorArea(total_oa_m3_per_m2s)
      ventilation.setConstantTermCoefficient(1.0)
      ventilation.setVelocityTermCoefficient(0.0)
      ventilation.setTemperatureTermCoefficient(0.0)
      ventilation.setMinimumIndoorTemperature(-73.3333352760033)
      ventilation.setMaximumIndoorTemperature(100.0)
      ventilation.setDeltaTemperature(-100.0)

      case ventilation_type
      when 'Natural'
        pressure_rise_pa = 0.0
        fan_total_eff = 1.0
      when 'Intake'
        target_w_per_m3_per_s = OpenStudio.convert(0.3, 'W/CFM', 'W*s/m^3').get
        fan_total_eff = 0.6
        pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
      when 'Exhaust'
        target_w_per_m3_per_s = OpenStudio.convert(0.054, 'W/CFM', 'W*s/m^3').get
        fan_total_eff = 0.6
        pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
      else
        raise "ventilation_type must be one of ['Natural', 'Intake', 'Exhaust']"
      end

      ventilation.setVentilationType(ventilation_type)
      ventilation.setFanPressureRise(pressure_rise_pa)
      ventilation.setFanTotalEfficiency(fan_total_eff)
      ventilation.addToThermalZone(zone)
      zone.setHeatingPriority(ventilation, 0)
      zone.setCoolingPriority(ventilation, 0)

      next unless ensure_ddy_infiltration

      zone.spaces.each do |space|
        add_design_day_only_infiltration(space) unless space.infiltrationDesignAirChangesPerHour > 0.001
      end
    end
  end

  # True when the infiltration object was created only for design-day sizing.
  def sizing_only_infiltration?(infiltration)
    feature = infiltration.additionalProperties.getFeatureAsBoolean(SIZING_ONLY_INFILTRATION_FEATURE)
    feature.is_initialized && feature.get
  end

  # Adds a design-day-only infiltration object (flagged as sizing-only) to a space.
  def add_design_day_only_infiltration(space)
    model = space.model
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
    infiltration.setName("#{space.nameString} Design Day Only Infiltration")
    infiltration.setSpace(space)
    infiltration.additionalProperties.setFeature(SIZING_ONLY_INFILTRATION_FEATURE, true)
    infiltration.setSchedule(ddy_only_infiltration_schedule(model))
    if space.designSpecificationOutdoorAir.is_initialized
      infiltration.setFlowperSpaceFloorArea(space_get_outdoor_airflow_rate(space) / space.floorArea)
    else
      infiltration.setAirChangesperHour(0.01)
    end
    infiltration
  end

  # Raises exterior non-exhaust VAV:Reheat terminal caps after PRM sizing without lowering existing caps.
  def apply_reheat_max_air_temperature_headroom(model)
    model.getThermalZones.each do |zone|
      next if exhaust_zone?(zone)
      next unless zone.spaces.any? { |space| space.exteriorWallArea > 0.0 }

      air_terminal = zone.airLoopHVACTerminal
      next unless air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized

      vav_terminal = air_terminal.get.to_AirTerminalSingleDuctVAVReheat.get
      next if vav_terminal.maximumReheatAirTemperature >= REHEAT_MAX_AIR_TEMPERATURE_C

      vav_terminal.setMaximumReheatAirTemperature(REHEAT_MAX_AIR_TEMPERATURE_C)
    end
  end

  # Why: heated-only zones may need sizing-only infiltration support.
  # What: returns a schedule that is on only for design days.
  # How: creates or reuses a ScheduleRuleset with winter/summer design days at 1.
  # Used by: heated-only equivalent ventilation helper.
  def ddy_only_infiltration_schedule(model)
    schedule_name = 'Infiltration Schedule Only One on Design Days'
    existing = model.getScheduleRulesetByName(schedule_name)
    return existing.get if existing.is_initialized

    schedule = OpenStudio::Model::ScheduleRuleset.new(model, 0.0)
    schedule.setName(schedule_name)
    schedule.defaultDaySchedule.setName("#{schedule_name} Default Day")
    set_ddy_only_design_days(schedule)
    schedule
  end

  # Sets both design days of a ruleset to a constant value.
  def set_ddy_only_design_days(schedule, value = 1.0)
    model = schedule.model
    schedule_name = schedule.nameString
    winter_day = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setWinterDesignDaySchedule(winter_day)
    winter_day.remove
    schedule.winterDesignDaySchedule.setName("#{schedule_name} Winter Design Day")
    schedule.winterDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), value)
    summer_day = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setSummerDesignDaySchedule(summer_day)
    summer_day.remove
    schedule.summerDesignDaySchedule.setName("#{schedule_name} Summer Design Day")
    schedule.summerDesignDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), value)
  end

  # PRM design-day sizing sets both NIST On and Off schedules to 1, which counts
  # infiltration twice. Sizing assumes the HVAC runs, so set the Off design days to 0.
  def zero_nist_hvac_off_infiltration_design_days(model)
    model.getSpaceInfiltrationDesignFlowRates.select { |infil| infil.nameString.end_with?(' HVAC Off Infiltration') && infil.schedule.is_initialized }
         .map { |infil| infil.schedule.get.to_ScheduleRuleset }.select(&:is_initialized).map(&:get)
         .uniq { |schedule| schedule.handle.to_s }
         .each { |schedule| set_ddy_only_design_days(schedule, 0.0) }
  end

  # Rebuilds the NIST On and Off schedules from the current HVAC schedule.
  # NIST copies the HVAC schedule only once, so a later HVAC schedule change needs this.
  # Sizing assumes the HVAC runs, so the On design days are 1 and the Off design days are 0.
  def sync_nist_infiltration_schedules(model)
    on_suffix = ' HVAC On Infiltration'
    return false unless model.getSpaceInfiltrationDesignFlowRates.any? { |infil| infil.nameString.end_with?(on_suffix) }

    OpenstudioStandards::Infiltration.model_set_nist_infiltration_schedules(model)
    model.getSpaceInfiltrationDesignFlowRates.select { |infil| infil.nameString.end_with?(on_suffix) && infil.schedule.is_initialized }
         .map { |infil| infil.schedule.get.to_ScheduleRuleset }.select(&:is_initialized).map(&:get)
         .uniq { |schedule| schedule.handle.to_s }
         .each { |schedule| set_ddy_only_design_days(schedule, 1.0) }
    zero_nist_hvac_off_infiltration_design_days(model)
    true
  end

  # PRM design-day sizing resets each infiltration schedule's design days to its
  # annual max (0 for the sizing-only schedule); put them back to 1.0.
  def restore_design_day_only_infiltration_design_days(model)
    model.getSpaceInfiltrationDesignFlowRates.select { |infil| sizing_only_infiltration?(infil) }.each do |infil|
      next unless infil.schedule.is_initialized

      ruleset = infil.schedule.get.to_ScheduleRuleset
      next unless ruleset.is_initialized

      ruleset = ruleset.get
      next if ruleset.winterDesignDaySchedule.values == [1.0] && ruleset.summerDesignDaySchedule.values == [1.0]

      set_ddy_only_design_days(ruleset)
    end
  end

  # Why: design-day infiltration for heated-only ventilation needs each space OA.
  # What: calculates total outdoor airflow from a space DSOA object.
  # How: combines per-person, per-area, fixed, and ACH terms using sum or max.
  # Used by: heated-only equivalent ventilation helper.
  def space_get_outdoor_airflow_rate(space)
    return 0.0 if space.designSpecificationOutdoorAir.empty?

    outdoor_air = space.designSpecificationOutdoorAir.get
    values = [
      space.numberOfPeople * outdoor_air.outdoorAirFlowperPerson,
      space.floorArea * outdoor_air.outdoorAirFlowperFloorArea,
      outdoor_air.outdoorAirFlowRate,
      space.volume * outdoor_air.outdoorAirFlowAirChangesperHour / 3600.0
    ]
    outdoor_air.outdoorAirMethod.casecmp('sum').zero? ? values.sum : values.max
  end

  # True when a space of the zone has an exhaust space type (kitchen, restroom, cafeteria).
  def exhaust_zone?(zone)
    zone.spaces.any? do |space|
      space_type = space.spaceType
      space_type.is_initialized && EXHAUST_ZONE_SPACE_TYPES.include?(space_type.get.standardsSpaceType.to_s)
    end
  end

  def zone_exhaust_maximum_flow_rate(zone)
    zone.equipment.sum do |equipment|
      next 0.0 unless equipment.to_FanZoneExhaust.is_initialized

      fan = equipment.to_FanZoneExhaust.get
      fan.maximumFlowRate.is_initialized ? fan.maximumFlowRate.get : 0.0
    end
  end

  def prm_call(prm_standard, method_name, *args)
    prm_standard.send(method_name, *args)
  end

  def __model_get_primary_building_type(model)
    building_types = {}

    building = model.getBuilding
    building_level_type = nil
    if building.standardsBuildingType.is_initialized
      building_level_type = model_get_lookup_name(building.standardsBuildingType.get)
      OpenStudio.logFree(OpenStudio::Debug, 'crop.Model', "found Building level standardsBuildingType = '#{building_level_type}'")
    end

    model.getSpaceTypes.sort.each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized

      building_type = model_get_lookup_name(space_type.standardsBuildingType.get)
      building_types[building_type] ||= 0.0
      building_types[building_type] += space_type.floorArea
    end

    if building_types.empty?
      if building_level_type.nil?
        msg = "Cannot identify a single building type in model, none of your #{model.getSpaceTypes.size} SpaceTypes have a standardsBuildingType assigned and neither does the Building"
        OpenStudio.logFree(OpenStudio::Error, 'crop.Model', msg)
        raise 'No Primary Building Type found'
      end
      return building_level_type
    end

    building_types.max_by { |_building_type, floor_area| floor_area }.first
  end

  def model_get_primary_building_type(model, remap_office: false, remap_retail: false)
    @primary_building_types_memoized ||= {}
    @primary_building_types_memoized[model] ||= __model_get_primary_building_type(model)

    building_type = @primary_building_types_memoized[model]
    building_type = model_remap_office(model, model.getBuilding.floorArea) if remap_office && building_type == 'Office'
    if remap_retail
      return 'RetailStripmall' if building_type == 'StripMall'
      return 'RetailStandalone' if building_type == 'Retail'
    end
    building_type
  end

  def model_remap_office(model, floor_area)
    floor_area_sqft = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get
    num_floors = model.getBuilding.buildingStories.size
    if floor_area_sqft < 25_000
      num_floors <= 3 ? 'SmallOffice' : 'MediumOffice'
    elsif floor_area_sqft < 150_000
      num_floors <= 5 ? 'MediumOffice' : 'LargeOffice'
    else
      'LargeOffice'
    end
  end

  def get_exterior_fenestration_value(sub_surface, column_name)
    known_columns = [
      'Construction',
      'Frame and Divider',
      'Glass Area',
      'Frame Area',
      'Divider Area',
      'Area of One Opening',
      'Area of Multiplied Openings',
      'Glass U-Factor',
      'Glass SHGC',
      'Glass Visible Transmittance',
      'Frame Conductance',
      'Divider Conductance',
      'NFRC Product Type',
      'Assembly U-Factor',
      'Assembly SHGC',
      'Assembly Visible Transmittance',
      'Shade Control',
      'Parent Surface',
      'Azimuth',
      'Tilt',
      'Cardinal Direction'
    ]
    raise "Unknown column '#{column_name}'. Available: #{known_columns}" unless known_columns.include?(column_name)

    sql_query = <<~SQL
      SELECT Value FROM TabularDataWithStrings
        WHERE ReportName='EnvelopeSummary'
          AND ReportForString='Entire Facility'
          AND TableName='Exterior Fenestration'
          AND RowName='#{sub_surface.nameString.upcase}'
          AND ColumnName='#{column_name}'
    SQL

    val_ = sub_surface.model.sqlFile.get.execAndReturnFirstDouble(sql_query)
    raise "Query failed: #{sql_query}" if val_.empty?

    val_.get
  end

  def get_exterior_fenestration_value_with_fallback(sub_surface, metric)
    get_exterior_fenestration_value(sub_surface, "Glass #{metric}")
  rescue RuntimeError
    get_exterior_fenestration_value(sub_surface, "Assembly #{metric}")
  end

  def sub_surface_get_window_property(sub_surface)
    sql_file = sub_surface.model.sqlFile
    if !sql_file.is_initialized
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'Model has no sql file containing results, cannot lookup data.')
      return nil
    end

    window_type = sub_surface.subSurfaceType
    unless ['window', 'skylight'].any? { |x| window_type.downcase.include?(x) }
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SubSurface', 'SubSurface is a not a window or skylight.')
      return nil
    end

    sub_surface_name = sub_surface.name.to_s

    window_shgc = get_exterior_fenestration_value_with_fallback(sub_surface, 'SHGC')
    window_u_value = get_exterior_fenestration_value_with_fallback(sub_surface, 'U-Factor')
    window_area = get_exterior_fenestration_value(sub_surface, 'Area of Multiplied Openings')

    surface_type = nil
    surface_ = sub_surface.surface
    surface_type = surface_.get.surfaceType if surface_.is_initialized

    {
      'name' => sub_surface_name,
      'window_type' => window_type,
      'surface_type' => surface_type,
      'area_m2' => window_area,
      'shgc' => window_shgc,
      'u_value' => window_u_value,
    }
  end

  # Old names. Remove after one release.
  alias model_apply_179d_hvac_and_exhaust_availability_schedules model_apply_occupancy_hvac_and_exhaust_availability_schedules
end
