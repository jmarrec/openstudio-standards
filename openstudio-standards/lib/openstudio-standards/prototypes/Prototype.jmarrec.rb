# open the class to add methods to size all HVAC equipment
class OpenStudio::Model::Model


  def set_sizing_parameters_appendix_G(building_type, building_vintage)

    # Default unless otherwise specified
    clg = 1.15
    htg = 1.25
    case building_vintage   
    when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013'
      clg = 1.15
      htg = 1.25
    end

    sizing_params = self.getSizingParameters
    sizing_params.setHeatingSizingFactor(htg)
    sizing_params.setCoolingSizingFactor(clg)

    OpenStudio::logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set sizing factors to #{htg} for heating and #{clg} for cooling, per App G 2007 through 2016")

  end

  def add_ptac(prototype_input, standards, thermal_zones)

    # hvac operation schedule
    hvac_op_sch = self.add_schedule(prototype_input['ptac_operation_schedule'])

    # motorized oa damper schedule
    motorized_oa_damper_sch = self.add_schedule(prototype_input['ptac_oa_damper_schedule'])

    # schedule: always off
    always_off = OpenStudio::Model::ScheduleRuleset.new(self)
    always_off.setName("ALWAYS_OFF")
    always_off.defaultDaySchedule.setName("ALWAYS_OFF day")
    always_off.defaultDaySchedule.addValue(OpenStudio::Time.new(0,24,0,0), 0.0)
    always_off.setSummerDesignDaySchedule(always_off.defaultDaySchedule)
    always_off.setWinterDesignDaySchedule(always_off.defaultDaySchedule)

    # Make a PTAC for each zone
    thermal_zones.each do |zone|

      # Zone sizing
      sizing_zone = zone.sizingZone
      
      # G3.1.2.8 Design Airflow Rates. System design supply 
      # airflow rates for the baseline building design shall be based on
      # a supply-air-to-room-air temperature difference of 20°F or the
      # required ventilation air or makeup air, whichever is greater
      # In SI version, a difference of 11°C is specified
      
      
      # Get the supply base temps
      tstat = zone.thermostatSetpointDualSetpoint.get
      
      # Initialize base temps in case you can't find better
      # Base temp is 72F
      htg_base_temp = 22.2222222222223
      # Base temp is 78F
      clg_base_temp = 25.5555555555556
      if !tstat.empty? 
        htg_sch = tstat.heatingSetpointTemperatureSchedule
        if !htg_sch.empty?
          htg_sch = htg_sch.get
          if !htg_sch.to_ScheduleRuleset.empty?
            htg_sch = htg_sch.to_ScheduleRuleset.get
            htg_defaultDaySch = htg_sch.defaultDaySchedule
            # take the max
            htg_base_temp = htg_defaultDaySch.values.max
            # Issue some warnings...
            if htg_base_temp < 15.55
              OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', 'For zone #{zone.name.to_s}, heating base temp seems abnormally cool: #{"%.2f", htg_base_temp} C // #{"%.2f", OpenStudio::convert(htg_base_temp,"C","F").get} F')
            elsif htg_base_temp > 26.67
              OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', 'For zone #{zone.name.to_s}, heating base temp seems abnormally warm: #{"%.2f", htg_base_temp} C // #{"%.2f", OpenStudio::convert(htg_base_temp,"C","F").get} F')
            end
          end
        end
        clg_sch = tstat.coolingSetpointTemperatureSchedule
        if !clg_sch.empty?
          clg_sch = clg_sch.get
          if !clg_sch.to_ScheduleRuleset.empty?
            clg_sch = clg_sch.to_ScheduleRuleset.get
            clg_defaultDaySch = clg_sch.defaultDaySchedule
            # take the min
            clg_base_temp = clg_defaultDaySch.values.min
            # Issue some warnings...
            if clg_base_temp < 22.22
              OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', 'For zone #{zone.name.to_s}, cooling base temp seems abnormally cool: #{"%.2f", clg_base_temp} C // #{"%.2f", OpenStudio::convert(clg_base_temp,"C","F").get} F')
            elsif clg_base_temp > 27
              OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', 'For zone #{zone.name.to_s}, cooling base temp seems abnormally warm: #{"%.2f", clg_base_temp} C // #{"%.2f", OpenStudio::convert(clg_base_temp,"C","F").get} F')
            end
          end
        end
      end
      
      
      # 14C is 57.1F, almost good.
      # sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14)
      # I'm going with the IP delta of 20R instead of the 11K of SI (it's only 0.1C difference)
      cooling_sat = clg_base_temp - OpenStudio::convert(20,'R','K').get
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(cooling_sat)
      
      # 50C is 120F. This is no good
      # sizing_zone.setZoneHeatingDesignSupplyAirTemperature(50.0)
      heating_sat = clg_base_temp - OpenStudio::convert(20,'R','K').get
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(heating_sat)
      
      sizing_zone.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
      sizing_zone.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)

      # add fan
      fan = nil
      if prototype_input["ptac_fan_type"] == "ConstantVolume"
        # This will create a fan at 0.3 W/CFM
        # fan_power_w = pressure_rise_pa * dsn_air_flow_m3_per_s / fan_total_eff
        # <=> fan_power_w/dsn_air_flow_m3_per_s = pressure_rise_pa/fan_total_eff
        # 0.3 W/CFM = 635.664 W/(m3.s)
        # 635.664 W/(m3.s) * 0.52 = 331 Pa
        # this works too... 445 Pa, TotalFanEfficiency 0.7
      
        # Create a ConstantVolume fan with 0.3 W/CFM
        fan = OpenStudio::Model::FanConstantVolume.new(self,self.alwaysOnDiscreteSchedule)
        fan.setName("#{zone.name} PTAC Fan")
        fan_static_pressure_pa = 331
        fan.setPressureRise(fan_static_pressure_pa)
        fan.setFanEfficiency(0.52)
        fan.setMotorEfficiency(0.8)
      elsif prototype_input["ptac_fan_type"] == "Cycling"
        #
        fan = OpenStudio::Model::FanOnOff.new(self,self.alwaysOnDiscreteSchedule)
        fan.setName("#{zone.name} PTAC Fan")
        # Create a ConstantVolume fan with 0.3 W/CFM
        fan_static_pressure_pa = 331
        fan.setPressureRise(fan_static_pressure_pa)
        fan.setFanEfficiency(0.52)
        fan.setMotorEfficiency(0.8)
      else
        OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', "ptac_fan_type of #{prototype_input["ptac_fan_type"]} is not recognized.")
      end


      # add heating coil
      htg_coil = nil
      # New, this is useful for Sys 1 in ASHRAE Appendix G...
      if prototype_input["ptac_heating_type"] == "Hot Water"
        htg_coil = OpenStudio::Model::CoilHeatingWater.new(self,self.alwaysOnDiscreteSchedule)
        htg_coil.setName("#{zone.name} PTAC HW Htg Coil")
      elsif prototype_input["ptac_heating_type"] == "Gas"
        htg_coil = OpenStudio::Model::CoilHeatingGas.new(self,self.alwaysOnDiscreteSchedule)
        htg_coil.setName("#{zone.name} PTAC Gas Htg Coil")
      elsif prototype_input["ptac_heating_type"] == "Electric"
        htg_coil = OpenStudio::Model::CoilHeatingElectric.new(self,self.alwaysOnDiscreteSchedule)
        htg_coil.setName("#{zone.name} PTAC Electric Htg Coil")
      elsif prototype_input["ptac_heating_type"] == "Single Speed Heat Pump"
        htg_cap_f_of_temp = OpenStudio::Model::CurveCubic.new(self)
        htg_cap_f_of_temp.setCoefficient1Constant(0.758746)
        htg_cap_f_of_temp.setCoefficient2x(0.027626)
        htg_cap_f_of_temp.setCoefficient3xPOW2(0.000148716)
        htg_cap_f_of_temp.setCoefficient4xPOW3(0.0000034992)
        htg_cap_f_of_temp.setMinimumValueofx(-20.0)
        htg_cap_f_of_temp.setMaximumValueofx(20.0)

        htg_cap_f_of_flow = OpenStudio::Model::CurveCubic.new(self)
        htg_cap_f_of_flow.setCoefficient1Constant(0.84)
        htg_cap_f_of_flow.setCoefficient2x(0.16)
        htg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        htg_cap_f_of_flow.setCoefficient4xPOW3(0.0)
        htg_cap_f_of_flow.setMinimumValueofx(0.5)
        htg_cap_f_of_flow.setMaximumValueofx(1.5)

        htg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveCubic.new(self)
        htg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.19248)
        htg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.0300438)
        htg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00103745)
        htg_energy_input_ratio_f_of_temp.setCoefficient4xPOW3(-0.000023328)
        htg_energy_input_ratio_f_of_temp.setMinimumValueofx(-20.0)
        htg_energy_input_ratio_f_of_temp.setMaximumValueofx(20.0)

        htg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        htg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.3824)
        htg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.4336)
        htg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0512)
        htg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.0)
        htg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.0)

        htg_part_load_fraction = OpenStudio::Model::CurveQuadratic.new(self)
        htg_part_load_fraction.setCoefficient1Constant(0.85)
        htg_part_load_fraction.setCoefficient2x(0.15)
        htg_part_load_fraction.setCoefficient3xPOW2(0.0)
        htg_part_load_fraction.setMinimumValueofx(0.0)
        htg_part_load_fraction.setMaximumValueofx(1.0)

        htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(self,
                                                                  self.alwaysOnDiscreteSchedule,
                                                                  htg_cap_f_of_temp,
                                                                  htg_cap_f_of_flow,
                                                                  htg_energy_input_ratio_f_of_temp,
                                                                  htg_energy_input_ratio_f_of_flow,
                                                                  htg_part_load_fraction)

        htg_coil.setName("#{zone.name} PTAC HP Htg Coil")

      else
        OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', "ptac_heating_type of #{prototype_input["ptac_heating_type"]} is not recognized.")
      end


      # add cooling coil
      clg_coil = nil
      if prototype_input["ptac_cooling_type"] == "Two Speed DX AC"

        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_cap_f_of_temp.setCoefficient1Constant(0.42415)
        clg_cap_f_of_temp.setCoefficient2x(0.04426)
        clg_cap_f_of_temp.setCoefficient3xPOW2(-0.00042)
        clg_cap_f_of_temp.setCoefficient4y(0.00333)
        clg_cap_f_of_temp.setCoefficient5yPOW2(-0.00008)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.00021)
        clg_cap_f_of_temp.setMinimumValueofx(17.0)
        clg_cap_f_of_temp.setMaximumValueofx(22.0)
        clg_cap_f_of_temp.setMinimumValueofy(13.0)
        clg_cap_f_of_temp.setMaximumValueofy(46.0)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_cap_f_of_flow.setCoefficient1Constant(0.77136)
        clg_cap_f_of_flow.setCoefficient2x(0.34053)
        clg_cap_f_of_flow.setCoefficient3xPOW2(-0.11088)
        clg_cap_f_of_flow.setMinimumValueofx(0.75918)
        clg_cap_f_of_flow.setMaximumValueofx(1.13877)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.23649)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.02431)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00057)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(-0.01434)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.00063)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.00038)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(17.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(22.0)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(13.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.0)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.20550)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.32953)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.12308)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.75918)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.13877)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(self)
        clg_part_load_ratio.setCoefficient1Constant(0.77100)
        clg_part_load_ratio.setCoefficient2x(0.22900)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)

        clg_cap_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_cap_f_of_temp_low_spd.setCoefficient1Constant(0.42415)
        clg_cap_f_of_temp_low_spd.setCoefficient2x(0.04426)
        clg_cap_f_of_temp_low_spd.setCoefficient3xPOW2(-0.00042)
        clg_cap_f_of_temp_low_spd.setCoefficient4y(0.00333)
        clg_cap_f_of_temp_low_spd.setCoefficient5yPOW2(-0.00008)
        clg_cap_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00021)
        clg_cap_f_of_temp_low_spd.setMinimumValueofx(17.0)
        clg_cap_f_of_temp_low_spd.setMaximumValueofx(22.0)
        clg_cap_f_of_temp_low_spd.setMinimumValueofy(13.0)
        clg_cap_f_of_temp_low_spd.setMaximumValueofy(46.0)

        clg_energy_input_ratio_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient1Constant(1.23649)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient2x(-0.02431)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient3xPOW2(0.00057)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient4y(-0.01434)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient5yPOW2(0.00063)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00038)
        clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofx(17.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofx(22.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofy(13.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofy(46.0)

        clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(self,
                                                        self.alwaysOnDiscreteSchedule,
                                                        clg_cap_f_of_temp,
                                                        clg_cap_f_of_flow,
                                                        clg_energy_input_ratio_f_of_temp,
                                                        clg_energy_input_ratio_f_of_flow,
                                                        clg_part_load_ratio,
                                                        clg_cap_f_of_temp_low_spd,
                                                        clg_energy_input_ratio_f_of_temp_low_spd)

        clg_coil.setName("#{zone.name} PTAC 2spd DX AC Clg Coil")
        clg_coil.setRatedLowSpeedSensibleHeatRatio(OpenStudio::OptionalDouble.new(0.69))
        clg_coil.setBasinHeaterCapacity(10)
        clg_coil.setBasinHeaterSetpointTemperature(2.0)

      elsif prototype_input["ptac_cooling_type"] == "Single Speed DX AC"   # for small hotel

        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_cap_f_of_temp.setCoefficient1Constant(0.942587793)
        clg_cap_f_of_temp.setCoefficient2x(0.009543347)
        clg_cap_f_of_temp.setCoefficient3xPOW2(0.000683770)
        clg_cap_f_of_temp.setCoefficient4y(-0.011042676)
        clg_cap_f_of_temp.setCoefficient5yPOW2(0.000005249)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.000009720)
        clg_cap_f_of_temp.setMinimumValueofx(12.77778)
        clg_cap_f_of_temp.setMaximumValueofx(23.88889)
        clg_cap_f_of_temp.setMinimumValueofy(18.3)
        clg_cap_f_of_temp.setMaximumValueofy(46.11111)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_cap_f_of_flow.setCoefficient1Constant(0.8)
        clg_cap_f_of_flow.setCoefficient2x(0.2)
        clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        clg_cap_f_of_flow.setMinimumValueofx(0.5)
        clg_cap_f_of_flow.setMaximumValueofx(1.5)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.342414409)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.034885008)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000623700)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.004977216)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000437951)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000728028)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(12.77778)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(23.88889)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(18.3)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.11111)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.1552)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.1808)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0256)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.5)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.5)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(self)
        clg_part_load_ratio.setCoefficient1Constant(0.85)
        clg_part_load_ratio.setCoefficient2x(0.15)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)
        clg_part_load_ratio.setMinimumCurveOutput(0.7)
        clg_part_load_ratio.setMaximumCurveOutput(1.0)

        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(self,
                                                        self.alwaysOnDiscreteSchedule,
                                                        clg_cap_f_of_temp,
                                                        clg_cap_f_of_flow,
                                                        clg_energy_input_ratio_f_of_temp,
                                                        clg_energy_input_ratio_f_of_flow,
                                                        clg_part_load_ratio)

        clg_coil.setName("#{zone.name} PTAC 1spd DX AC Clg Coil")

      elsif prototype_input["ptac_cooling_type"] == "Single Speed Heat Pump"

        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_cap_f_of_temp.setCoefficient1Constant(0.766956)
        clg_cap_f_of_temp.setCoefficient2x(0.0107756)
        clg_cap_f_of_temp.setCoefficient3xPOW2(-0.0000414703)
        clg_cap_f_of_temp.setCoefficient4y(0.00134961)
        clg_cap_f_of_temp.setCoefficient5yPOW2(-0.000261144)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(0.000457488)
        clg_cap_f_of_temp.setMinimumValueofx(12.78)
        clg_cap_f_of_temp.setMaximumValueofx(23.89)
        clg_cap_f_of_temp.setMinimumValueofy(21.1)
        clg_cap_f_of_temp.setMaximumValueofy(46.1)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_cap_f_of_flow.setCoefficient1Constant(0.8)
        clg_cap_f_of_flow.setCoefficient2x(0.2)
        clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        clg_cap_f_of_flow.setMinimumValueofx(0.5)
        clg_cap_f_of_flow.setMaximumValueofx(1.5)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(self)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.297145)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.0430933)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000748766)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.00597727)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000482112)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000956448)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(12.78)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(23.89)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(21.1)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.1)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(self)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.156)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.1816)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0256)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.5)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.5)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(self)
        clg_part_load_ratio.setCoefficient1Constant(0.85)
        clg_part_load_ratio.setCoefficient2x(0.15)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)

        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(self,
                                                        self.alwaysOnDiscreteSchedule,
                                                        clg_cap_f_of_temp,
                                                        clg_cap_f_of_flow,
                                                        clg_energy_input_ratio_f_of_temp,
                                                        clg_energy_input_ratio_f_of_flow,
                                                        clg_part_load_ratio)

        clg_coil.setName("#{zone.name} PTAC 1spd DX HP Clg Coil")
        #clg_coil.setRatedSensibleHeatRatio(0.69)
        #clg_coil.setBasinHeaterCapacity(10)
        #clg_coil.setBasinHeaterSetpointTemperature(2.0)

      else
        OpenStudio::logFree(OpenStudio::Warn, 'openstudio.model.Model', "ptac_cooling_type of #{prototype_input["ptac_heating_type"]} is not recognized.")
      end



      # Wrap coils in a PTAC system
      ptac_system = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(self,
                                                                                  self.alwaysOnDiscreteSchedule,
                                                                                  fan,
                                                                                  htg_coil,
                                                                                  clg_coil)


      ptac_system.setName("#{zone.name} PTAC")
      ptac_system.setFanPlacement("DrawThrough")
      if prototype_input["ptac_fan_type"] == "ConstantVolume"
        ptac_system.setSupplyAirFanOperatingModeSchedule(self.alwaysOnDiscreteSchedule)
      elsif prototype_input["ptac_fan_type"] == "Cycling"
        ptac_system.setSupplyAirFanOperatingModeSchedule(always_off)
      end
      ptac_system.addToThermalZone(zone)

    end

    return true

  end
  
    # Creates a Hot Water Loop
  #  
  # @param prototype_input (TODO)
  # @param standards (TODO: is required?)
  # @param building_vintage [String] the building vintage
  # @param climate_zone [String] the climate zone
  # @param area_served_si [Float] Area served by this loop, in SQUARE METERS
  # @return [Bool] returns true if successful, false if not
  # @example Create a Small Office, 90.1-2010, in ASHRAE Climate Zone 5A (Chicago)
  #   model.create_prototype_building('SmallOffice', '90.1-2010', 'ASHRAE 169-2006-5A')
  def add_hw_loop_appG(prototype_input, standards, area_served_si)

    #hot water loop
    hot_water_loop = OpenStudio::Model::PlantLoop.new(self)
    hot_water_loop.setName('Hot Water Loop')
    hot_water_loop.setMinimumLoopTemperature(10)

    # G3.1.3.3 - HW Supply at 180°F, return at 130°F
    hw_temp_f = 180 #HW setpoint 180F   
    hw_delta_t_r = 50 #20F delta-T    
    
    hw_temp_c = OpenStudio.convert(hw_temp_f,'F','C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r,'R','K').get


    sizing_plant = hot_water_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(hw_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(hw_delta_t_k)  

    
    ##################  SetpointManagerOutdoorAirReset #########################
    # ASHRAE Appendix G - G3.1.3.4 (I check for ASHRAE 90.1-2004, 2007 and 2010)
    # HW reset: 180°F at 20°F and below, 150°F at 50°F and above
    
    # Low OAT = 20°F, HWST = 180°F
    oat_low_ip = 20
    sp_low_ip = 180
    oat_low_si = OpenStudio::convert(oat_low_ip,'F','C').get
    sp_low_si = OpenStudio::convert(sp_low_ip,'F','C').get

    # High OAT = 50°F, HWST = 150°F
    oat_high_ip = 50
    sp_high_ip = 150    
    oat_high_si = OpenStudio::convert(oat_high_ip,'F','C').get
    sp_high_si = OpenStudio::convert(sp_high_ip,'F','C').get
    
    hw_oareset_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
    hw_oareset_stpt_manager.setControlVariable("Temperature")
    hw_oareset_stpt_manager.setSetpointatOutdoorLowTemperature(sp_low_si)
    hw_oareset_stpt_manager.setOutdoorLowTemperature(oat_low_si)
    hw_oareset_stpt_manager.setSetpointatOutdoorHighTemperature(sp_high_si)
    hw_oareset_stpt_manager.setOutdoorHighTemperature(oat_high_si)
    hw_stpt_manager.setName("HW Loop SetpointManagerOutdoorAirReset App G")
    # Add to Loop supply outlet node
    hw_oareset_stpt_manager.addToNode(hot_water_loop.supplyOutletNode)
    ##################  End of SetpointManagerOutdoorAirReset ##################
    

    #hot water pump
    # G3.1.3.5 Hot water pumps
    # 19 W/GPM, or 301 kW/(m^3/s) in the SI version
    # If serving more than 120,000 ft^2: VSD, otherwise constant speed riding the pump curve
    # http://bigladdersoftware.com/epx/docs/8-4/engineering-reference/component-sizing.html#pump-sizing
       
    impeller_efficiency = 0.78
    motor_efficiency = 0.9
        
    # Rated_Power_Use = Rated_Volume_Flow_Rate * Rated_Pump_Head / Total_Efficiency
    # Rated_Power_Use / Rated_Volume_Flow_Rate =  Rated_Pump_Head / Total_Efficiency
    # Total_Efficiency = Motor_Efficiency * Impeler_Efficiency
    # Let's go with the IP version
    desired_power_per_m3_s = OpenStudio::convert(19,'W*min/gal', 'W*s/m^3').get
    hw_pump_head_press_pa = desired_power_per_m3_s * motor_efficiency * impeller_efficiency
    
    # G3.1.3.5 Hot Waters Pumps (Sys 1, 5, 7)
    # If serving 120,000 ft^2 **or more**: VSD, otherwise constant speed riding the pump curve
    if if area_served_si >= OpenStudio::convert(120000,'ft^2','m^2').get
      hw_pump = OpenStudio::Model::PumpVariableSpeed.new(self)
      hw_pump.setName('Hot Water Loop VSD Pump')
    else
      hw_pump = OpenStudio::Model::PumpConstantSpeed.new(self)
      hw_pump.setName('Hot Water Loop Constant Pump')
    end

    hw_pump.setRatedPumpHead(hw_pump_head_press_pa)
    hw_pump.setMotorEfficiency(motor_efficiency)
    hw_pump.setFractionofMotorInefficienciestoFluidStream(0)
    hw_pump.setCoefficient1ofthePartLoadPerformanceCurve(0)
    hw_pump.setCoefficient2ofthePartLoadPerformanceCurve(1)
    hw_pump.setCoefficient3ofthePartLoadPerformanceCurve(0)
    hw_pump.setCoefficient4ofthePartLoadPerformanceCurve(0)
    hw_pump.setPumpControlType('Intermittent')
    hw_pump.addToNode(hot_water_loop.supplyInletNode)


    
    #boiler
    boiler_max_t_f = 203
    boiler_max_t_c = OpenStudio.convert(boiler_max_t_f,'F','C').get
    boiler = OpenStudio::Model::BoilerHotWater.new(self)
    # Will set name below
    boiler.setEfficiencyCurveTemperatureEvaluationVariable('LeavingBoiler')
    boiler.setFuelType('NaturalGas')
    boiler.setDesignWaterOutletTemperature(hw_temp_c)
    
    # TODO CHECK THAT LATER IN THE CODE IT'LL GO CHECK TABLE 6.8.1F to Find efficiency based on the capacity
    # Apparnetly it doesn't
    # Set a baseline efficiency of 80%
    boiler.setNominalThermalEfficiency(0.8)
    boiler.setMaximumPartLoadRatio(1.2)
    boiler.setWaterOutletUpperTemperatureLimit(boiler_max_t_c)
    boiler.setBoilerFlowMode('LeavingSetpointModulated')
    

    if building_type == "LargeHotel"
      boiler.setEfficiencyCurveTemperatureEvaluationVariable("LeavingBoiler")
      boiler.setDesignWaterOutletTemperature(81)
      boiler.setMaximumPartLoadRatio(1.2)
      boiler.setSizingFactor(1.2)
      boiler.setWaterOutletUpperTemperatureLimit(95)
    end
    
    
    
    # G3.1.3.2 - Type and Number of boilers (Systems 1, 5, 7)
    # 1 boilers if more than 15000ft² (or 1400m²) **or less**
    # 2 boilers above 15000 ft²
    
    if area_served_si <= OpenStudio::convert(15000,'ft^2','m^2').get
      boiler.setName('Hot Water Loop Boiler 1')
      # Add at least one boiler to it.
      hot_water_loop.addSupplyBranchForComponent(boiler)
    else
      # Rename to boiler 1
      boiler.setName('Hot Water Loop Boiler 1')
      
      # Clone it
      boiler2 = boiler.clone()
      boiler2.setName('Hot Water Loop Boiler 2')
      # Add both boilers to loop
      hot_water_loop.addSupplyBranchForComponent(boiler)
    end
      
    
    

    # TODO: Yixing. Add the temperature setpoint will cost the simulation with
    # thousands of Severe Errors. Need to figure this out later.
    #boiler_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(self,hw_temp_sch)
    #boiler_stpt_manager.setName("Boiler outlet setpoint manager")
    #boiler_stpt_manager.addToNode(boiler.outletModelObject.get.to_Node.get)


    #hot water loop pipes
    boiler_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(self)
    hot_water_loop.addSupplyBranchForComponent(boiler_bypass_pipe)
    coil_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(self)
    hot_water_loop.addDemandBranchForComponent(coil_bypass_pipe)
    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(self)
    supply_outlet_pipe.addToNode(hot_water_loop.supplyOutletNode)
    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(self)
    demand_inlet_pipe.addToNode(hot_water_loop.demandInletNode)
    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(self)
    demand_outlet_pipe.addToNode(hot_water_loop.demandOutletNode)

    return hot_water_loop

  end
  
  
end # Close the class 'OpenStudio::Model::Model'