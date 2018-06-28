class Standard
  # @!group hvac_systems

  # Creates a hot water loop with a boiler, district heating, or a
  # water-to-water heat pump and adds it to the model.
  #
  # @param boiler_fuel_type [String] valid choices are Electricity, NaturalGas, PropaneGas, FuelOil#1, FuelOil#2, DistrictHeating, HeatPump
  # @param ambient_loop [OpenStudio::Model::PlantLoop] The condenser loop for the heat pump. Only used when boiler_fuel_type is HeatPump.
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 180F
  # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 20R
  # @param pump_spd_ctrl [String] pump speed control type, Constant or Variable (default)
  # @param pump_tot_hd [Double] pump head in ft H2O
  # @param boiler_draft_type [String] Boiler type Condensing, MechanicalNoncondensing, Natural (default)
  # @param boiler_eff_curve_temp_eval_var [String] LeavingBoiler or EnteringBoiler temperature for the boiler efficiency curve
  # @param boiler_lvg_temp_dsgn F [Double] boiler leaving design temperature
  # @param boiler_out_temp_lmt [Double] boiler outlet temperature limit
  # @param boiler_max_plr [Double] boiler maximum part load ratio
  # @param boiler_sizing_factor [Double] boiler oversizing factor
  # @return [OpenStudio::Model::PlantLoop] the resulting hot water loop
  def model_add_hw_loop(model,
                        boiler_fuel_type,
                        ambient_loop: nil,
                        system_name: "Hot Water Loop",
                        dsgn_sup_wtr_temp: 180.0,
                        dsgn_sup_wtr_temp_delt: 20.0,
                        pump_spd_ctrl: "Variable",
                        pump_tot_hd: nil,
                        boiler_draft_type: nil,
                        boiler_eff_curve_temp_eval_var: nil,
                        boiler_lvg_temp_dsgn: nil,
                        boiler_out_temp_lmt: nil,
                        boiler_max_plr: nil,
                        boiler_sizing_factor: nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding hot water loop.')

    # create hot water loop
    hot_water_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      hot_water_loop.setName("Hot Water Loop")
    else
      hot_water_loop.setName(system_name)
    end

    # hot water loop sizing and controls
    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp_c = OpenStudio.convert(180.0, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(20.0, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end

    sizing_plant = hot_water_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    hot_water_loop.setMinimumLoopTemperature(10.0)
    hw_temp_sch = model_add_constant_schedule_ruleset(model, dsgn_sup_wtr_temp_c, name = "#{hot_water_loop.name.to_s} #{dsgn_sup_wtr_temp}F")
    hw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hw_temp_sch)
    hw_stpt_manager.setName("#{hot_water_loop.name.to_s} Setpoint Manager")
    hw_stpt_manager.addToNode(hot_water_loop.supplyOutletNode)

    # create hot water pump
    if pump_spd_ctrl == 'Constant'
      hw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    elsif pump_spd_ctrl == 'Variable'
      hw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    else
      hw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    end
    hw_pump.setName("#{hot_water_loop.name.to_s} Pump")
    if pump_tot_hd.nil?
      pump_tot_hd_pa =  OpenStudio.convert(60, 'ftH_{2}O', 'Pa').get
    else
      pump_tot_hd_pa =  OpenStudio.convert(pump_tot_hd, 'ftH_{2}O', 'Pa').get
    end
    hw_pump.setRatedPumpHead(pump_tot_hd_pa)
    hw_pump.setMotorEfficiency(0.9)
    hw_pump.setPumpControlType('Intermittent')
    hw_pump.addToNode(hot_water_loop.supplyInletNode)

    # create boiler and add to loop
    case boiler_fuel_type
      # District Heating
      when 'DistrictHeating'
        district_heat = OpenStudio::Model::DistrictHeating.new(model)
        district_heat.setName("#{hot_water_loop.name.to_s} District Heating")
        district_heat.autosizeNominalCapacity
        hot_water_loop.addSupplyBranchForComponent(district_heat)
      # Ambient Loop
      when 'HeatPump'
        water_to_water_hp = OpenStudio::Model::HeatPumpWaterToWaterEquationFitHeating.new(model)
        water_to_water_hp.setName("#{hot_water_loop.name.to_s} Water to Water Heat Pump")
        hot_water_loop.addSupplyBranchForComponent(water_to_water_hp)
        # Get or add an ambient loop
        if ambient_loop.nil?
          ambient_loop = model_get_or_add_ambient_water_loop(model)
        end
        ambient_loop.addDemandBranchForComponent(water_to_water_hp)
      # Boiler
      when 'Electricity', 'NaturalGas', 'PropaneGas', 'FuelOil#1', 'FuelOil#2'
        if boiler_lvg_temp_dsgn.nil?
          lvg_temp_dsgn = dsgn_sup_wtr_temp
        else
          lvg_temp_dsgn = boiler_lvg_temp_dsgn
        end

        if boiler_out_temp_lmt.nil?
          out_temp_lmt = OpenStudio.convert(203, 'F', 'C').get
        else
          out_temp_lmt = boiler_out_temp_lmt
        end

        boiler = create_boiler_hot_water(model,
                                         hot_water_loop: hot_water_loop,
                                         fuel_type: boiler_fuel_type,
                                         draft_type: boiler_draft_type,
                                         nominal_thermal_efficiency: 0.78,
                                         eff_curve_temp_eval_var: boiler_eff_curve_temp_eval_var,
                                         lvg_temp_dsgn: lvg_temp_dsgn,
                                         out_temp_lmt: out_temp_lmt,
                                         max_plr: boiler_max_plr,
                                         sizing_factor: boiler_sizing_factor)

        # TODO: Yixing. Adding temperature setpoint controller at boiler outlet causes simulation errors
        # boiler_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(self,hw_temp_sch)
        # boiler_stpt_manager.setName("Boiler outlet setpoint manager")
        # boiler_stpt_manager.addToNode(boiler.outletModelObject.get.to_Node.get)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Boiler fuel type #{boiler_fuel_type} is not valid, no boiler will be added.")
    end

    # add hot water loop pipes
    boiler_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    boiler_bypass_pipe.setName("#{hot_water_loop.name.to_s} Boiler Bypass Pipe")
    hot_water_loop.addSupplyBranchForComponent(boiler_bypass_pipe)

    coil_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    coil_bypass_pipe.setName("#{hot_water_loop.name.to_s} Coil Bypass Pipe")
    hot_water_loop.addDemandBranchForComponent(coil_bypass_pipe)

    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe.setName("#{hot_water_loop.name.to_s} Supply Outlet Pipe")
    supply_outlet_pipe.addToNode(hot_water_loop.supplyOutletNode)

    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet_pipe.setName("#{hot_water_loop.name.to_s} Demand Inlet Pipe")
    demand_inlet_pipe.addToNode(hot_water_loop.demandInletNode)

    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet_pipe.setName("#{hot_water_loop.name.to_s} Demand Outlet Pipe")
    demand_outlet_pipe.addToNode(hot_water_loop.demandOutletNode)

    return hot_water_loop
  end

  # Creates a chilled water loop and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param cooling_fuel [String] cooling fuel. Valid choices are: Electricity, DistrictCooling
  # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 44F
  # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 10R
  # @param chw_pumping_type [String] valid choices are const_pri, const_pri_var_sec
  # @param chiller_cooling_type [String] valid choices are AirCooled, WaterCooled
  # @param chiller_condenser_type [String] valid choices are WithCondenser, WithoutCondenser, nil
  # @param chiller_compressor_type [String] valid choices are Centrifugal, Reciprocating, Rotary Screw, Scroll, nil
  # @param num_chillers [Integer] the number of chillers
  # @param chiller_sizing_factor [Double] chiller oversizing factor
  # @param condenser_water_loop [OpenStudio::Model::PlantLoop] optional condenser water loop for water-cooled chillers.
  #   If this is not passed in, the chillers will be air cooled.
  # @return [OpenStudio::Model::PlantLoop] the resulting chilled water loop
  def model_add_chw_loop(model,
                         system_name: "Chilled Water Loop",
                         cooling_fuel: "Electricity",
                         dsgn_sup_wtr_temp: 44.0,
                         dsgn_sup_wtr_temp_delt: 10.1,
                         chw_pumping_type: nil,
                         chiller_cooling_type: nil,
                         chiller_condenser_type: nil,
                         chiller_compressor_type: nil,
                         num_chillers: 1,
                         chiller_sizing_factor: nil,
                         condenser_water_loop: nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding chilled water loop.')

    # create chilled water loop
    chilled_water_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      chilled_water_loop.setName("Chilled Water Loop")
    else
      chilled_water_loop.setName(system_name)
    end

    # chilled water loop sizing and controls
    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp_c = OpenStudio.convert(44.0, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(10.1, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end
    chilled_water_loop.setMinimumLoopTemperature(1.0)
    chilled_water_loop.setMaximumLoopTemperature(40.0)
    sizing_plant = chilled_water_loop.sizingPlant
    sizing_plant.setLoopType('Cooling')
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    chw_temp_sch = model_add_constant_schedule_ruleset(model, dsgn_sup_wtr_temp_c, name = "#{chilled_water_loop.name.to_s} #{dsgn_sup_wtr_temp}F")
    chw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, chw_temp_sch)
    chw_stpt_manager.setName("#{chilled_water_loop.name.to_s} Setpoint Manager")
    chw_stpt_manager.addToNode(chilled_water_loop.supplyOutletNode)
    # TODO: Yixing check the CHW Setpoint from standards
    # TODO: Should be a OutdoorAirReset, see the changes I've made in Standards.PlantLoop.apply_prm_baseline_temperatures

    # create chilled water pumps
    if chw_pumping_type == 'const_pri'
      # primary chilled water pump
      pri_chw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
      pri_chw_pump.setName("#{chilled_water_loop.name.to_s} Pump")
      pri_chw_pump.setRatedPumpHead(OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get)
      pri_chw_pump.setMotorEfficiency(0.9)
      # flat pump curve makes it behave as a constant speed pump
      pri_chw_pump.setFractionofMotorInefficienciestoFluidStream(0)
      pri_chw_pump.setCoefficient1ofthePartLoadPerformanceCurve(0)
      pri_chw_pump.setCoefficient2ofthePartLoadPerformanceCurve(1)
      pri_chw_pump.setCoefficient3ofthePartLoadPerformanceCurve(0)
      pri_chw_pump.setCoefficient4ofthePartLoadPerformanceCurve(0)
      pri_chw_pump.setPumpControlType('Intermittent')
      pri_chw_pump.addToNode(chilled_water_loop.supplyInletNode)
    elsif chw_pumping_type == 'const_pri_var_sec'
      # primary chilled water pump
      pri_chw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)
      pri_chw_pump.setName("#{chilled_water_loop.name.to_s} Primary Pump")
      pri_chw_pump.setRatedPumpHead(OpenStudio.convert(15.0, 'ftH_{2}O', 'Pa').get)
      pri_chw_pump.setMotorEfficiency(0.9)
      pri_chw_pump.setPumpControlType('Intermittent')
      pri_chw_pump.addToNode(chilled_water_loop.supplyInletNode)
      # secondary chilled water pump
      sec_chw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
      sec_chw_pump.setName("#{chilled_water_loop.name.to_s} Secondary Pump")
      sec_chw_pump.setRatedPumpHead(OpenStudio.convert(45.0, 'ftH_{2}O', 'Pa').get)
      sec_chw_pump.setMotorEfficiency(0.9)
      # curve makes it perform like variable speed pump
      sec_chw_pump.setFractionofMotorInefficienciestoFluidStream(0)
      sec_chw_pump.setCoefficient1ofthePartLoadPerformanceCurve(0)
      sec_chw_pump.setCoefficient2ofthePartLoadPerformanceCurve(0.0205)
      sec_chw_pump.setCoefficient3ofthePartLoadPerformanceCurve(0.4101)
      sec_chw_pump.setCoefficient4ofthePartLoadPerformanceCurve(0.5753)
      sec_chw_pump.setPumpControlType('Intermittent')
      sec_chw_pump.addToNode(chilled_water_loop.demandInletNode)
      # Change the chilled water loop to have a two-way common pipes
      chilled_water_loop.setCommonPipeSimulation('CommonPipe')
    end

    # check for existence of condenser_water_loop if WaterCooled
    if chiller_cooling_type == 'WaterCooled'
      if condenser_water_loop.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Requested chiller is WaterCooled but no condenser loop specified.")
      end
    end

    # check for non-existence of condenser_water_loop if AirCooled
    if chiller_cooling_type == 'AirCooled'
      if !condenser_water_loop.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Requested chiller is AirCooled but condenser loop specified.")
      end
    end

    if cooling_fuel == 'DistrictCooling'
      # DistrictCooling
      dist_clg = OpenStudio::Model::DistrictCooling.new(model)
      dist_clg.setName('Purchased Cooling')
      dist_clg.autosizeNominalCapacity
      chilled_water_loop.addSupplyBranchForComponent(dist_clg)
    else
      # make the correct type of chiller based these properties
      num_chillers.times do |i|
        chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
        chiller.setName("#{template} #{chiller_cooling_type} #{chiller_condenser_type} #{chiller_compressor_type} Chiller #{i}")
        chilled_water_loop.addSupplyBranchForComponent(chiller)
        chiller.setReferenceLeavingChilledWaterTemperature(dsgn_sup_wtr_temp_c)
        chiller.setLeavingChilledWaterLowerTemperatureLimit(OpenStudio.convert(36.0, 'F', 'C').get)
        chiller.setReferenceEnteringCondenserFluidTemperature(OpenStudio.convert(95.0, 'F', 'C').get)
        chiller.setMinimumPartLoadRatio(0.15)
        chiller.setMaximumPartLoadRatio(1.0)
        chiller.setOptimumPartLoadRatio(1.0)
        chiller.setMinimumUnloadingRatio(0.25)
        chiller.setChillerFlowMode('ConstantFlow')
        chiller.setSizingFactor(chiller_sizing_factor) if !chiller_sizing_factor.nil?

        # connect the chiller to the condenser loop if one was supplied
        if condenser_water_loop.nil?
          chiller.setCondenserType('AirCooled')
        else
          condenser_water_loop.addDemandBranchForComponent(chiller)
          chiller.setCondenserType('WaterCooled')
        end
      end
    end

    # chilled water loop pipes
    chiller_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    chiller_bypass_pipe.setName("#{chilled_water_loop.name.to_s} Chiller Bypass Pipe")
    chilled_water_loop.addSupplyBranchForComponent(chiller_bypass_pipe)

    coil_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    coil_bypass_pipe.setName("#{chilled_water_loop.name.to_s} Coil Bypass Pipe")
    chilled_water_loop.addDemandBranchForComponent(coil_bypass_pipe)

    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe.setName("#{chilled_water_loop.name.to_s} Supply Outlet Pipe")
    supply_outlet_pipe.addToNode(chilled_water_loop.supplyOutletNode)

    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet_pipe.setName("#{chilled_water_loop.name.to_s} Demand Inlet Pipe")
    demand_inlet_pipe.addToNode(chilled_water_loop.demandInletNode)

    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet_pipe.setName("#{chilled_water_loop.name.to_s} Demand Outlet Pipe")
    demand_outlet_pipe.addToNode(chilled_water_loop.demandOutletNode)

    return chilled_water_loop
  end

  # Creates a condenser water loop and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param cooling_tower_type [String] valid choices are Open Cooling Tower, Closed Cooling Tower
  # @param cooling_tower_fan_type [String] valid choices are Centrifugal, "Propeller or Axial"
  # @param cooling_tower_capacity_control [String] valid choices are Fluid Bypass, Fan Cycling, TwoSpeed Fan, Variable Speed Fan
  # @param number_of_cells_per_tower [Integer] the number of discrete cells per tower
  # @param number_cooling_towers [Integer] the number of cooling towers to be added (in parallel)
  # @param sup_wtr_temp [Double] supply water temperature in degrees Fahrenheit, default 70F
  # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 85F
  # @param dsgn_sup_wtr_temp_delt [Double] design water range temperature in degrees Rankine, default 10R
  # @param wet_bulb_approach [Double] design wet bulb approach temperature, default 7R
  # @param pump_spd_ctrl [String] pump speed control type, Constant or Variable (default)
  # @param pump_tot_hd [Double] pump head in ft H2O
  # @return [OpenStudio::Model::PlantLoop] the resulting condenser water plant loop
  def model_add_cw_loop(model,
                        system_name: "Condenser Water Loop",
                        cooling_tower_type: "Open Cooling Tower",
                        cooling_tower_fan_type: "Propeller or Axial",
                        cooling_tower_capacity_control: "TwoSpeed Fan",
                        number_of_cells_per_tower: 1,
                        number_cooling_towers: 1,
                        sup_wtr_temp: 70.0,
                        dsgn_sup_wtr_temp: 85.0,
                        dsgn_sup_wtr_temp_delt: 10.0,
                        wet_bulb_approach: 7.0,
                        pump_spd_ctrl: "Constant",
                        pump_tot_hd: 49.7)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding condenser water loop.')

    # create condenser water loop
    condenser_water_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      condenser_water_loop.setName("Condenser Water Loop")
    else
      condenser_water_loop.setName(system_name)
    end

    # condenser water loop sizing and controls
    if sup_wtr_temp.nil?
      sup_wtr_temp_c = OpenStudio.convert(70.0, 'F', 'C').get
    else
      sup_wtr_temp_c = OpenStudio.convert(sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp_c = OpenStudio.convert(85.0, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(10.0, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end
    if wet_bulb_approach.nil?
      wet_bulb_approach_k = OpenStudio.convert(7.0, 'R', 'K').get
    else
      wet_bulb_approach_k = OpenStudio.convert(wet_bulb_approach, 'R', 'K').get
    end
    condenser_water_loop.setMinimumLoopTemperature(5.0)
    condenser_water_loop.setMaximumLoopTemperature(80.0)
    sizing_plant = condenser_water_loop.sizingPlant
    sizing_plant.setLoopType('Condenser')
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    cw_temp_sch = model_add_constant_schedule_ruleset(model, sup_wtr_temp_c, name = "#{condenser_water_loop.name.to_s} #{sup_wtr_temp}F")
    cw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, cw_temp_sch)
    cw_stpt_manager.setName("#{condenser_water_loop.name.to_s} Setpoint Manager")
    cw_stpt_manager.addToNode(condenser_water_loop.supplyOutletNode)

    # create condenser water pump
    if pump_spd_ctrl == 'Constant'
      cw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    elsif pump_spd_ctrl == 'Variable'
      cw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    elsif pump_spd_ctrl == 'HeaderedVariable'
      cw_pump = OpenStudio::Model::HeaderedPumpsVariableSpeed.new(model)
      cw_pump.setNumberofPumpsinBank(2)
    elsif pump_spd_ctrl == 'HeaderedConstant'
      cw_pump = OpenStudio::Model::HeaderedPumpsConstantSpeed.new(model)
      cw_pump.setNumberofPumpsinBank(2)
    else
      cw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    end
    cw_pump.setName("#{condenser_water_loop.name.to_s} #{pump_spd_ctrl} Pump")
    cw_pump.setPumpControlType('Intermittent')

    if pump_tot_hd.nil?
      pump_tot_hd_pa =  OpenStudio.convert(49.7, 'ftH_{2}O', 'Pa').get
    else
      pump_tot_hd_pa =  OpenStudio.convert(pump_tot_hd, 'ftH_{2}O', 'Pa').get
    end
    cw_pump.setRatedPumpHead(pump_tot_hd_pa)
    cw_pump.addToNode(condenser_water_loop.supplyInletNode)

    # Cooling towers
    # Per PNNL PRM Reference Manual
    number_cooling_towers.times do |_i|

      # Tower object depends on the control type
      cooling_tower = nil
      case cooling_tower_capacity_control
      when 'Fluid Bypass', 'Fan Cycling'
        cooling_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
        if cooling_tower_capacity_control == 'Fluid Bypass'
          cooling_tower.setCellControl('FluidBypass')
        else
          cooling_tower.setCellControl('FanCycling')
        end
      when 'TwoSpeed Fan'
        cooling_tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(model)
        # TODO: expose newer cooling tower sizing fields in API
        # cooling_tower.setLowFanSpeedAirFlowRateSizingFactor(0.5)
        # cooling_tower.setLowFanSpeedFanPowerSizingFactor(0.3)
        # cooling_tower.setLowFanSpeedUFactorTimesAreaSizingFactor
        # cooling_tower.setLowSpeedNominalCapacitySizingFactor
      when 'Variable Speed Fan'
        cooling_tower = OpenStudio::Model::CoolingTowerVariableSpeed.new(model)
        cooling_tower.setDesignRangeTemperature(dsgn_sup_wtr_temp_delt_k)
        cooling_tower.setDesignApproachTemperature(wet_bulb_approach_k)
        cooling_tower.setFractionofTowerCapacityinFreeConvectionRegime(0.125)
        twr_fan_curve = model_add_curve(model, 'VSD-TWR-FAN-FPLR')
        cooling_tower.setFanPowerRatioFunctionofAirFlowRateRatioCurve(twr_fan_curve)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "#{cooling_tower_capacity_control} is not a valid choice of cooling tower capacity control.  Valid choices are Fluid Bypass, Fan Cycling, TwoSpeed Fan, Variable Speed Fan.")
      end

      # Set the properties that apply to all tower types and attach to the condenser loop.
      unless cooling_tower.nil?
        cooling_tower.setName("#{cooling_tower_fan_type} #{cooling_tower_capacity_control} #{cooling_tower_type}")
        cooling_tower.setSizingFactor(1 / number_cooling_towers)
        cooling_tower.setNumberofCells(number_of_cells_per_tower)
        condenser_water_loop.addSupplyBranchForComponent(cooling_tower)
      end
    end

    # Condenser water loop pipes
    cooling_tower_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    cooling_tower_bypass_pipe.setName("#{condenser_water_loop.name.to_s} Cooling Tower Bypass Pipe")
    condenser_water_loop.addSupplyBranchForComponent(cooling_tower_bypass_pipe)

    chiller_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    chiller_bypass_pipe.setName("#{condenser_water_loop.name.to_s} Chiller Bypass Pipe")
    condenser_water_loop.addDemandBranchForComponent(chiller_bypass_pipe)

    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe.setName("#{condenser_water_loop.name.to_s} Supply Outlet Pipe")
    supply_outlet_pipe.addToNode(condenser_water_loop.supplyOutletNode)

    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet_pipe.setName("#{condenser_water_loop.name.to_s} Demand Inlet Pipe")
    demand_inlet_pipe.addToNode(condenser_water_loop.demandInletNode)

    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet_pipe.setName("#{condenser_water_loop.name.to_s} Demand Outlet Pipe")
    demand_outlet_pipe.addToNode(condenser_water_loop.demandOutletNode)

    return condenser_water_loop
  end

  # Creates a heat pump loop which has a boiler and fluid cooler for supplemental heating/cooling and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param sup_wtr_high_temp [Double] target supply water temperature to enable cooling in degrees Fahrenheit, default 65.0F
  # @param sup_wtr_low_temp [Double] target supply water temperature to enable heating in degrees Fahrenheit, default 41.0F
  # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 102.2F
  # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 19.8R
  # @return [OpenStudio::Model::PlantLoop] the resulting plant loop
  # TODO: replace cooling tower with fluid cooler after fixing sizing inputs
  def model_add_hp_loop(model,
                        building_type = nil,
                        system_name: "Heat Pump Loop",
                        sup_wtr_high_temp: 65.0,
                        sup_wtr_low_temp: 41.0,
                        dsgn_sup_wtr_temp: 102.2,
                        dsgn_sup_wtr_temp_delt: 19.8)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding heat pump loop.')

    # create heat pump loop
    heat_pump_water_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      heat_pump_water_loop.setName("Heat Pump Loop")
    else
      heat_pump_water_loop.setName(system_name)
    end

    # hot water loop sizing and controls
    if sup_wtr_high_temp.nil?
      sup_wtr_high_temp_c = OpenStudio.convert(65.0, 'F', 'C').get
    else
      sup_wtr_high_temp_c = OpenStudio.convert(sup_wtr_high_temp, 'F', 'C').get
    end
    if sup_wtr_low_temp.nil?
      sup_wtr_low_temp_c = OpenStudio.convert(41.0, 'F', 'C').get
    else
      sup_wtr_low_temp_c = OpenStudio.convert(sup_wtr_low_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp_c = OpenStudio.convert(102.2, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(19.8, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end
    sizing_plant = heat_pump_water_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    heat_pump_water_loop.setMinimumLoopTemperature(5.0)
    heat_pump_water_loop.setMaximumLoopTemperature(80.0)
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    hp_high_temp_sch = model_add_constant_schedule_ruleset(model,
                                                           sup_wtr_high_temp_c,
                                                           name = "#{heat_pump_water_loop.name.to_s} High Temp #{sup_wtr_high_temp}F")
    hp_low_temp_sch = model_add_constant_schedule_ruleset(model,
                                                          sup_wtr_low_temp_c,
                                                           name = "#{heat_pump_water_loop.name.to_s} Low Temp #{sup_wtr_low_temp}F")
    hp_stpt_manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
    hp_stpt_manager.setName("#{heat_pump_water_loop.name.to_s} Scheduled Dual Setpoint")
    hp_stpt_manager.setHighSetpointSchedule(hp_high_temp_sch)
    hp_stpt_manager.setLowSetpointSchedule(hp_low_temp_sch)
    hp_stpt_manager.addToNode(heat_pump_water_loop.supplyOutletNode)

    # create pump
    hp_pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    hp_pump.setName("#{heat_pump_water_loop.name.to_s} Pump")
    hp_pump.setRatedPumpHead(OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get)
    hp_pump.setPumpControlType('Intermittent')
    hp_pump.addToNode(heat_pump_water_loop.supplyInletNode)

    # create cooling towers or fluid coolers
    if building_type == 'LargeOffice' || building_type == 'LargeOfficeDetail'
      # TODO: For some reason the FluidCoolorTwoSpeed is causing simulation failures.
      # might need to look into the defaults
      # cooling_tower = OpenStudio::Model::FluidCoolerTwoSpeed.new(self)
      cooling_tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(model)
      cooling_tower.setName("#{heat_pump_water_loop.name} Central Tower")
      heat_pump_water_loop.addSupplyBranchForComponent(cooling_tower)
      #### Add SPM Scheduled Dual Setpoint to outlet of Fluid Cooler so correct Plant Operation Scheme is generated
      cooling_tower_stpt_manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
      cooling_tower_stpt_manager.setName("#{heat_pump_water_loop.name.to_s} Fluid Cooler Scheduled Dual Setpoint")
      cooling_tower_stpt_manager.setHighSetpointSchedule(hp_high_temp_sch)
      cooling_tower_stpt_manager.setLowSetpointSchedule(hp_low_temp_sch)
      cooling_tower_stpt_manager.addToNode(cooling_tower.outletModelObject.get.to_Node.get)
    else
      # TODO: replace with FluidCooler:TwoSpeed when available
      # cooling_tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(self)
      # cooling_tower.setName("#{heat_pump_water_loop.name} Sup Cooling Tower")
      # heat_pump_water_loop.addSupplyBranchForComponent(cooling_tower)
      fluid_cooler = OpenStudio::Model::EvaporativeFluidCoolerSingleSpeed.new(model)
      fluid_cooler.setName("#{heat_pump_water_loop.name} Fluid Cooler")
      fluid_cooler.setDesignSprayWaterFlowRate(0.002208) # Based on HighRiseApartment
      fluid_cooler.setPerformanceInputMethod('UFactorTimesAreaAndDesignWaterFlowRate')
      heat_pump_water_loop.addSupplyBranchForComponent(fluid_cooler)
    end

    # create boiler
    boiler = create_boiler_hot_water(model,
                                     hot_water_loop: heat_pump_water_loop,
                                     name: "#{heat_pump_water_loop.name} Supplemental Boiler",
                                     fuel_type: "NaturalGas",
                                     flow_mode: "ConstantFlow",
                                     lvg_temp_dsgn: 86.0,
                                     max_plr: 1.2)
    # add setpoint manager schedule to boiler outlet so correct plant operation scheme is generated
    boiler_stpt_manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
    boiler_stpt_manager.setName("#{heat_pump_water_loop.name.to_s} Boiler Scheduled Dual Setpoint")
    boiler_stpt_manager.setHighSetpointSchedule(hp_high_temp_sch)
    boiler_stpt_manager.setLowSetpointSchedule(hp_low_temp_sch)
    boiler_stpt_manager.addToNode(boiler.outletModelObject.get.to_Node.get)

    # add heat pump water loop pipes
    supply_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_bypass_pipe.setName("#{heat_pump_water_loop.name} Supply Bypass Pipe")
    heat_pump_water_loop.addSupplyBranchForComponent(supply_bypass_pipe)

    demand_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_bypass_pipe.setName("#{heat_pump_water_loop.name} Demand Bypass Pipe")
    heat_pump_water_loop.addDemandBranchForComponent(demand_bypass_pipe)

    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe.setName("#{heat_pump_water_loop.name} Supply Outlet Pipe")
    supply_outlet_pipe.addToNode(heat_pump_water_loop.supplyOutletNode)

    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet_pipe.setName("#{heat_pump_water_loop.name} Demand Inlet Pipe")
    demand_inlet_pipe.addToNode(heat_pump_water_loop.demandInletNode)

    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet_pipe.setName("#{heat_pump_water_loop.name} Demand Outlet Pipe")
    demand_outlet_pipe.addToNode(heat_pump_water_loop.demandOutletNode)

    return heat_pump_water_loop
  end

  # Creates loop that roughly mimics a properly sized ground heat exchanger for supplemental heating/cooling and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @return [OpenStudio::Model::PlantLoop] the resulting plant loop
  def model_add_ground_hx_loop(model,
                               system_name: "Ground HX Loop")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding ground source loop.')

    # create ground hx loop
    ground_hx_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      ground_hx_loop.setName("Ground HX Loop")
    else
      ground_hx_loop.setName(system_name)
    end

    # ground hx loop sizing and controls
    ground_hx_loop.setMinimumLoopTemperature(5.0)
    ground_hx_loop.setMaximumLoopTemperature(80.0)
    delta_t_k = OpenStudio.convert(12.0, 'R', 'K').get # temp change at high and low entering condition
    min_inlet_c = OpenStudio.convert(30.0, 'F', 'C').get # low entering condition.
    max_inlet_c = OpenStudio.convert(90.0, 'F', 'C').get # high entering condition

    # calculate the linear formula that defines outlet temperature based on inlet temperature of the ground hx
    min_outlet_c = min_inlet_c + delta_t_k
    max_outlet_c = max_inlet_c - delta_t_k
    slope_c_per_c = (max_outlet_c - min_outlet_c) / (max_inlet_c - min_inlet_c)
    intercept_c = min_outlet_c - (slope_c_per_c * min_inlet_c)

    sizing_plant = ground_hx_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(max_outlet_c)
    sizing_plant.setLoopDesignTemperatureDifference(delta_t_k)

    # create pump
    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName("#{ground_hx_loop.name} Pump")
    pump.setRatedPumpHead(OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get)
    pump.setPumpControlType('Intermittent')
    pump.addToNode(ground_hx_loop.supplyInletNode)

    # use EMS and a PlantComponentTemperatureSource to mimic the operation of the ground heat exchanger.

    # schedule to actuate ground HX outlet temperature
    hx_temp_sch = OpenStudio::Model::ScheduleConstant.new(model)
    hx_temp_sch.setName('Ground HX Temp Sch')
    hx_temp_sch.setValue(24)
    # TODO:

    ground_hx = OpenStudio::Model::PlantComponentTemperatureSource.new(model)
    ground_hx.setName('Ground HX')
    ground_hx.setTemperatureSpecificationType('Scheduled')
    ground_hx.setSourceTemperatureSchedule(hx_temp_sch)
    ground_hx_loop.addSupplyBranchForComponent(ground_hx)

    hx_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hx_temp_sch)
    hx_stpt_manager.setName("#{ground_hx.name} Supply Outlet Setpoint")
    hx_stpt_manager.addToNode(ground_hx.outletModelObject.get.to_Node.get)

    loop_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, hx_temp_sch)
    loop_stpt_manager.setName("#{ground_hx_loop.name} Supply Outlet Setpoint")
    loop_stpt_manager.addToNode(ground_hx_loop.supplyOutletNode)

    # sensor to read supply inlet temperature
    inlet_temp_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'System Node Temperature')
    inlet_temp_sensor.setName("#{ground_hx.name} Inlet Temp Sensor")
    inlet_temp_sensor.setKeyName(ground_hx_loop.supplyInletNode.handle.to_s)

    # actuator to set supply outlet temperature
    outlet_temp_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(hx_temp_sch, 'Schedule:Constant', 'Schedule Value')
    outlet_temp_actuator.setName("#{ground_hx.name} Outlet Temp Actuator")

    # actuator to set supply outlet temperature
    outlet_temp_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(hx_temp_sch, 'Schedule:Constant', 'Schedule Value')
    outlet_temp_actuator.setName("#{ground_hx.name} Outlet Temp Actuator")

    # program to control outlet temperature
    # adjusts delta-t based on calculation of slope and intercept from control temperatures
    program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    program.setName("#{ground_hx.name} Temperature Control")
    program_body = <<-EMS
      SET Tin = #{inlet_temp_sensor.handle}
      SET Tout = #{slope_c_per_c.round(2)} * Tin + #{intercept_c.round(1)}
      SET #{outlet_temp_actuator.handle} = Tout
    EMS
    program.setBody(program_body)

    # program calling manager
    pcm = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    pcm.setName("#{program.name} Calling Manager")
    pcm.setCallingPoint('InsideHVACSystemIterationLoop')
    pcm.addProgram(program)

    return ground_hx_loop
  end

  # Adds an ambient condenser water loop that will be used in a district to connect buildings as a shared sink/source for heat pumps.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @return [OpenStudio::Model::PlantLoop] the ambient loop
  # TODO: add inputs for design temperatures like heat pump loop object
  # TODO: handle ground and heat pump with this; make heating/cooling source options (boiler, fluid cooler, district)
  def model_add_district_ambient_loop(model,
                                      system_name: "Ambient Loop")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding district ambient loop.')

    # create ambient loop
    ambient_loop = OpenStudio::Model::PlantLoop.new(model)
    if system_name.nil?
      ambient_loop.setName("Ambient Loop")
    else
      ambient_loop.setName(system_name)
    end

    # ambient loop sizing and controls
    ambient_loop.setMinimumLoopTemperature(5.0)
    ambient_loop.setMaximumLoopTemperature(80.0)

    amb_high_temp_f = 90 # Supplemental cooling below 65F
    amb_low_temp_f = 41 # Supplemental heat below 41F
    amb_temp_sizing_f = 102.2 # CW sized to deliver 102.2F
    amb_delta_t_r = 19.8 # 19.8F delta-T
    amb_high_temp_c = OpenStudio.convert(amb_high_temp_f, 'F', 'C').get
    amb_low_temp_c = OpenStudio.convert(amb_low_temp_f, 'F', 'C').get
    amb_temp_sizing_c = OpenStudio.convert(amb_temp_sizing_f, 'F', 'C').get
    amb_delta_t_k = OpenStudio.convert(amb_delta_t_r, 'R', 'K').get

    amb_high_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    amb_high_temp_sch.setName("Ambient Loop High Temp - #{amb_high_temp_f}F")
    amb_high_temp_sch.defaultDaySchedule.setName("Ambient Loop High Temp - #{amb_high_temp_f}F Default")
    amb_high_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), amb_high_temp_c)

    amb_low_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    amb_low_temp_sch.setName("Ambient Loop Low Temp - #{amb_low_temp_f}F")
    amb_low_temp_sch.defaultDaySchedule.setName("Ambient Loop Low Temp - #{amb_low_temp_f}F Default")
    amb_low_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), amb_low_temp_c)

    amb_stpt_manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
    amb_stpt_manager.setHighSetpointSchedule(amb_high_temp_sch)
    amb_stpt_manager.setLowSetpointSchedule(amb_low_temp_sch)
    amb_stpt_manager.addToNode(ambient_loop.supplyOutletNode)

    sizing_plant = ambient_loop.sizingPlant
    sizing_plant.setLoopType("Heating")
    sizing_plant.setDesignLoopExitTemperature(amb_temp_sizing_c)
    sizing_plant.setLoopDesignTemperatureDifference(amb_delta_t_k)

    # create pump
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    pump.setName("#{ambient_loop.name.to_s} Pump")
    pump.setRatedPumpHead(OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get)
    pump.setPumpControlType('Intermittent')
    pump.addToNode(ambient_loop.supplyInletNode)

    # cooling
    district_cooling = OpenStudio::Model::DistrictCooling.new(model)
    district_cooling.setNominalCapacity(1_000_000_000_000) # large number; no autosizing
    ambient_loop.addSupplyBranchForComponent(district_cooling)

    # heating
    district_heating = OpenStudio::Model::DistrictHeating.new(model)
    district_heating.setNominalCapacity(1_000_000_000_000) # large number; no autosizing
    ambient_loop.addSupplyBranchForComponent(district_heating)

    # add abmient water loop pipes
    supply_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_bypass_pipe.setName("#{ambient_loop.name} Supply Bypass Pipe")
    ambient_loop.addSupplyBranchForComponent(supply_bypass_pipe)

    demand_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_bypass_pipe.setName("#{ambient_loop.name} Demand Bypass Pipe")
    ambient_loop.addDemandBranchForComponent(demand_bypass_pipe)

    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet_pipe.setName("#{ambient_loop.name} Supply Outlet Pipe")
    supply_outlet_pipe.addToNode(ambient_loop.supplyOutletNode)

    demand_inlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet_pipe.setName("#{ambient_loop.name} Demand Inlet Pipe")
    demand_inlet_pipe.addToNode(ambient_loop.demandInletNode)

    demand_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet_pipe.setName("#{ambient_loop.name} Demand Outlet Pipe")
    demand_outlet_pipe.addToNode(ambient_loop.demandOutletNode)

    return ambient_loop
  end

  # Creates a DOAS system with terminal units for each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param doas_type [String] DOASCV or DOASVAV, determines whether the DOAS is operated at scheduled,
  #   constant flow rate, or airflow is variable to allow for economizing or demand controlled ventilation
  # @param doas_control_strategy [String] DOAS control strategy
  # @param hot_water_loop [String] hot water loop to connect to heating and zone fan coils
  # @param chilled_water_loop [String] chilled water loop to connect to cooling coil
  # @param hvac_op_sch [String] name of the HVAC operation schedule, default is always on
  # @param min_oa_sch [String] name of the minimum outdoor air schedule, default is always on
  # @param min_frac_oa_sch [String] name of the minimum fraction of outdoor air schedule, default is always on
  # @param fan_maximum_flow_rate [Double] fan maximum flow rate in cfm, default is autosize
  # @param econo_ctrl_mthd [String] economizer control type, default is Fixed Dry Bulb
  # @param energy_recovery [Bool] if true, an ERV will be added to the system
  # @param clg_dsgn_sup_air_temp [Double] design cooling supply air temperature in degrees Fahrenheit, default 65F
  # @param htg_dsgn_sup_air_temp [Double] design heating supply air temperature in degrees Fahrenheit, default 75F
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting DOAS air loop
  def model_add_doas(model,
                     thermal_zones,
                     system_name: nil,
                     doas_type: "DOASVAV",
                     hot_water_loop: nil,
                     chilled_water_loop: nil,
                     hvac_op_sch: nil,
                     min_oa_sch: nil,
                     min_frac_oa_sch: nil,
                     fan_maximum_flow_rate: nil,
                     econo_ctrl_mthd: "NoEconomizer",
                     energy_recovery: false,
                     doas_control_strategy: "NeutralSupplyAir",
                     clg_dsgn_sup_air_temp: 60.0,
                     htg_dsgn_sup_air_temp: 70.0)

    # Check the total OA requirement for all zones on the system
    tot_oa_req = 0
    thermal_zones.each do |zone|
      tot_oa_req += thermal_zone_outdoor_airflow_rate(zone)
      break if tot_oa_req > 0
    end

    # If the total OA requirement is zero do not add the DOAS system because the simulations will fail
    if tot_oa_req.zero?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Not adding DOAS system for #{thermal_zones.size} zones because combined OA requirement for all zones is zero.")
      return false
    end
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding DOAS system for #{thermal_zones.size} zones.")

    # Make DOAS air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone DOAS")
    else
      air_loop.setName(system_name)
    end

    # set availability schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    # DOAS Controls
    air_loop.setNightCycleControlType('CycleOnAny')
    clg_dsgn_sup_air_temp = OpenStudio.convert(clg_dsgn_sup_air_temp, 'F', 'C').get
    htg_dsgn_sup_air_temp = OpenStudio.convert(htg_dsgn_sup_air_temp, 'F', 'C').get

    # modify system sizing properties
    sizing_system = air_loop.sizingSystem
    sizing_system.setTypeofLoadtoSizeOn('VentilationRequirement')
    sizing_system.setAllOutdoorAirinCooling(true)
    sizing_system.setAllOutdoorAirinHeating(true)
    sizing_system.setMinimumSystemAirFlowRatio(0.3)
    sizing_system.setSizingOption('Coincident')
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_dsgn_sup_air_temp)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_dsgn_sup_air_temp)

    if doas_type == "DOASCV"
      fan = create_fan_by_name(model, 'Constant_DOAS_Fan', fan_name:'DOAS Fan', end_use_subcategory:'DOAS Fans')
    else # "DOASVAV"
      fan = create_fan_by_name(model, 'Variable_DOAS_Fan', fan_name:'DOAS Fan', end_use_subcategory:'DOAS Fans')
    end
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.setMaximumFlowRate(OpenStudio.convert(fan_maximum_flow_rate, 'cfm', 'm^3/s').get) if !fan_maximum_flow_rate.nil?
    fan.addToNode(air_loop.supplyInletNode)

    # create heating coil
    if hot_water_loop.nil?
      coil_heating = create_coil_heating_dx_single_speed(model, name: "#{air_loop.name.to_s} Htg Coil")
    else
      coil_heating = create_coil_heating_water(model, hot_water_loop, name: "#{air_loop.name} Htg Coil",
                                             controller_convergence_tolerance: 0.0001)
    end
    coil_heating.addToNode(air_loop.supplyInletNode)

    # create cooling coil
    if chilled_water_loop.nil?
      coil_cooling = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name.to_s} 2spd DX Clg Coil", type:'OS default')
    else
      coil_cooling = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    end
    coil_cooling.addToNode(air_loop.supplyInletNode)

    # minimum outdoor air schedule
    min_oa_sch = if min_oa_sch.nil?
                   model.alwaysOnDiscreteSchedule
                 else
                   model_add_schedule(model, min_oa_sch)
                 end

    # minimum outdoor air fraction schedule
    min_frac_oa_sch = if min_frac_oa_sch.nil?
                        model.alwaysOnDiscreteSchedule
                      else
                        model_add_schedule(model, min_frac_oa_sch)
                      end

    # create controller outdoor air
    controller_oa = OpenStudio::Model::ControllerOutdoorAir.new(model)
    controller_oa.setName("#{air_loop.name.to_s} OA Controller")
    controller_oa.setEconomizerControlType(econo_ctrl_mthd)
    controller_oa.setMinimumLimitType('FixedMinimum')
    controller_oa.autosizeMinimumOutdoorAirFlowRate
    controller_oa.setMinimumOutdoorAirSchedule(min_oa_sch)
    controller_oa.setMinimumFractionofOutdoorAirSchedule(min_frac_oa_sch)
    controller_oa.resetEconomizerMaximumLimitDryBulbTemperature
    controller_oa.resetEconomizerMaximumLimitEnthalpy
    controller_oa.resetMaximumFractionofOutdoorAirSchedule
    controller_oa.resetEconomizerMinimumLimitDryBulbTemperature
    controller_oa.setHeatRecoveryBypassControlType('BypassWhenWithinEconomizerLimits')

    # create outdoor air system
    system_oa = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, controller_oa)
    system_oa.addToNode(air_loop.supplyInletNode)

    # Create a setpoint manager
    sat_oa_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
    sat_oa_reset.setName("#{air_loop.name.to_s} SAT Reset")
    sat_oa_reset.setControlVariable('Temperature')
    sat_oa_reset.setSetpointatOutdoorLowTemperature(htg_dsgn_sup_air_temp)
    sat_oa_reset.setOutdoorLowTemperature(OpenStudio.convert(60, 'F', 'C').get)
    sat_oa_reset.setSetpointatOutdoorHighTemperature(clg_dsgn_sup_air_temp)
    sat_oa_reset.setOutdoorHighTemperature(OpenStudio.convert(70, 'F', 'C').get)
    sat_oa_reset.addToNode(air_loop.supplyOutletNode)

    # add energy recovery if requested
    if energy_recovery
      # Get the OA system and its outboard OA node
      oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
      oa_node = oa_system.outboardOANode.get

      # create the ERV and set its properties
      erv = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
      erv.addToNode(oa_node)
      erv.setHeatExchangerType('Rotary')
      # TODO: Come up with scheme for estimating power of ERV motor wheel
      # which might require knowing airlow (like prototype buildings do).
      # erv.setNominalElectricPower(value_new)
      erv.setEconomizerLockout(true)
      erv.setSupplyAirOutletTemperatureControl(false)

      erv.setSensibleEffectivenessat100HeatingAirFlow(0.76)
      erv.setSensibleEffectivenessat75HeatingAirFlow(0.81)
      erv.setLatentEffectivenessat100HeatingAirFlow(0.68)
      erv.setLatentEffectivenessat75HeatingAirFlow(0.73)

      erv.setSensibleEffectivenessat100CoolingAirFlow(0.76)
      erv.setSensibleEffectivenessat75CoolingAirFlow(0.81)
      erv.setLatentEffectivenessat100CoolingAirFlow(0.68)
      erv.setLatentEffectivenessat75CoolingAirFlow(0.73)

      # increase fan static pressure to account for ERV
      erv_pressure_rise = OpenStudio.convert(1.0, 'inH_{2}O', 'Pa').get
      new_pressure_rise = fan.pressureRise + erv_pressure_rise
      fan.setPressureRise(new_pressure_rise)
    end

    # add thermal zones to airloop
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---adding #{zone.name} to #{air_loop.name.to_s}")

      # make an air terminal for the zone
      if doas_type == "DOASCV"
        air_terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      else # "DOASVAV"
        air_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVNoReheat.new(model, model.alwaysOnDiscreteSchedule)
        air_terminal.setZoneMinimumAirFlowInputMethod('Constant')
        air_terminal.setConstantMinimumAirFlowFraction(0.1)
      end
      air_terminal.setName("#{zone.name.to_s} Air Terminal")

      # attach new terminal to the zone and to the airloop
      air_loop.addBranchForZone(zone, air_terminal.to_StraightComponent)

      # DOAS sizing
      zone_sizing = zone.sizingZone
      zone_sizing.setAccountforDedicatedOutdoorAirSystem(true)
      zone_sizing.setDedicatedOutdoorAirSystemControlStrategy(doas_control_strategy)
      zone_sizing.setDedicatedOutdoorAirLowSetpointTemperatureforDesign(clg_dsgn_sup_air_temp)
      zone_sizing.setDedicatedOutdoorAirHighSetpointTemperatureforDesign(htg_dsgn_sup_air_temp)
    end

    return air_loop
  end

  # Creates a VAV system and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param hot_water_loop [String] hot water loop to connect heating and reheat coils to
  # @param chilled_water_loop [String] chilled water loop to connect cooling coil to
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule, or nil in which case will be defaulted to always open
  # @param vav_fan_efficiency [Double] fan total efficiency, including motor and impeller
  # @param vav_fan_motor_efficiency [Double] fan motor efficiency
  # @param vav_fan_pressure_rise [Double] fan pressure rise, inH2O
  # @param return_plenum [OpenStudio::Model::ThermalZone] the zone to attach as the supply plenum, or nil, in which case no return plenum will be used
  # @param reheat_type [String] valid options are NaturalGas, Electricity, Water, nil (no heat)
  # @param building_type [String] the building type
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
  def model_add_vav_reheat(model,
                           system_name,
                           hot_water_loop,
                           chilled_water_loop,
                           thermal_zones,
                           hvac_op_sch,
                           oa_damper_sch,
                           vav_fan_efficiency,
                           vav_fan_motor_efficiency,
                           vav_fan_pressure_rise,
                           return_plenum,
                           reheat_type = 'Water',
                           building_type = nil)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding VAV system for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    hw_temp_f = 180 # HW setpoint 180F
    hw_delta_t_r = 20 # 20F delta-T
    hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # control temps used across all air handlers
    clg_sa_temp_f = 55.04 # Central deck clg temp 55F
    prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
    preclg_sa_temp_f = 55.04 # Precool to 55F
    htg_sa_temp_f = 55.04 # Central deck htg temp 55F
    if building_type == 'LargeHotel'
      htg_sa_temp_f = 62 # Central deck htg temp 55F
    end
    zone_htg_sa_temp_f = 104 # Zone heating design supply air temperature to 104 F
    rht_sa_temp_f = if building_type == 'LargeHotel'
                      90 # VAV box reheat to 90F for large hotel
                    else
                      104 # VAV box reheat to 104F
                    end

    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
    preclg_sa_temp_c = OpenStudio.convert(preclg_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
    rht_sa_temp_c = OpenStudio.convert(rht_sa_temp_f, 'F', 'C').get
    zone_htg_sa_temp_c = OpenStudio.convert(zone_htg_sa_temp_f, 'F', 'C').get
    sa_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sa_temp_sch.setName("Supply Air Temp - #{clg_sa_temp_f}F")
    sa_temp_sch.defaultDaySchedule.setName("Supply Air Temp - #{clg_sa_temp_f}F Default")
    sa_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_sa_temp_c)

    air_flow_ratio = if building_type == 'Hospital'
                       if system_name == 'VAV_PATRMS'
                         0.5
                       elsif system_name == 'VAV_1' || system_name == 'VAV_2'
                         0.3
                       else
                         1
                       end
                     else
                       0.3
                     end

    # air handler
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone VAV")
    else
      air_loop.setName(system_name)
    end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    sa_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sa_temp_sch)
    sa_stpt_manager.setName("#{thermal_zones.size} Zone VAV supply air setpoint manager")
    sa_stpt_manager.addToNode(air_loop.supplyOutletNode)

    # air handler controls
    sizing_system = air_loop.sizingSystem
    sizing_system.setMinimumSystemAirFlowRatio(air_flow_ratio)
    # sizing_system.setPreheatDesignTemperature(htg_oa_tdb_c)
    sizing_system.setPrecoolDesignTemperature(preclg_sa_temp_c)
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
    if building_type == 'Hospital'
      if system_name == 'VAV_2' || system_name == 'VAV_1'
        sizing_system.setSizingOption('Coincident')
      else
        sizing_system.setSizingOption('NonCoincident')
      end
    else
      sizing_system.setSizingOption('Coincident')
    end
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    sizing_system.setSystemOutdoorAirMethod('ZoneSum')

    # @type [OpenStudio::Model::FanVariableVolume] fan
    fan = create_fan_by_name(model, 'VAV_System_Fan',
                             fan_name:"#{air_loop.name} Fan",
                             fan_efficiency: vav_fan_efficiency,
                             pressure_rise: vav_fan_pressure_rise,
                             motor_efficiency: vav_fan_motor_efficiency,
                             end_use_subcategory: "VAV System Fan")
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.addToNode(air_loop.supplyInletNode)

    # heating coil
    if hot_water_loop.nil?
      htg_coil = create_coil_heating_gas(model, name: "Main Gas Htg Coil")
      htg_coil.addToNode(air_loop.supplyInletNode)
    else
      htg_coil = create_coil_heating_water(model,
                                           hot_water_loop,
                                           name: "#{air_loop.name} Main Htg Coil",
                                           rated_inlet_water_temperature: hw_temp_c,
                                           rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                           rated_inlet_air_temperature: htg_sa_temp_c,
                                           rated_outlet_air_temperature: rht_sa_temp_c)
      htg_coil.addToNode(air_loop.supplyInletNode)
    end

    # cooling coil
    clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    clg_coil.addToNode(air_loop.supplyInletNode)

    # outdoor air intake system
    oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_intake_controller.setName("#{air_loop.name} OA Controller")
    oa_intake_controller.setMinimumLimitType('FixedMinimum')
    oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
    # oa_intake_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)

    controller_mv = oa_intake_controller.controllerMechanicalVentilation
    controller_mv.setName("#{air_loop.name} Vent Controller")
    controller_mv.setSystemOutdoorAirMethod('VentilationRateProcedure')

    if building_type == 'LargeHotel'
      oa_intake_controller.setEconomizerControlType('DifferentialEnthalpy')
      oa_intake_controller.resetMaximumFractionofOutdoorAirSchedule
      oa_intake_controller.resetEconomizerMinimumLimitDryBulbTemperature
    end

    oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
    oa_intake.setName("#{air_loop.name} OA Sys")
    oa_intake.addToNode(air_loop.supplyInletNode)

    # The oa system need to be added before setting the night cycle control
    air_loop.setNightCycleControlType('CycleOnAny')

    # hook the VAV system to each zone
    thermal_zones.each do |zone|
      # reheat coil
      rht_coil = nil
      case reheat_type
      when 'NaturalGas'
        rht_coil = create_coil_heating_gas(model, name: "#{zone.name.to_s} Gas Reheat Coil")
      when 'Electricity'
        rht_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} Electric Reheat Coil")
      when 'Water'
        rht_coil = create_coil_heating_water(model, hot_water_loop, name: "#{zone.name} Reheat Coil",
                                             rated_inlet_water_temperature: hw_temp_c,
                                             rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                             rated_inlet_air_temperature: htg_sa_temp_c,
                                             rated_outlet_air_temperature: rht_sa_temp_c)
      when nil
        # Zero-capacity, always-off electric heating coil
        rht_coil = create_coil_heating_electric(model,
                                                name: "#{zone.name.to_s} No Reheat",
                                                schedule: model.alwaysOffDiscreteSchedule,
                                                nominal_capacity: 0)
      end

      # vav terminal
      terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, rht_coil)
      terminal.setName("#{zone.name} VAV Terminal")
      terminal.setZoneMinimumAirFlowMethod('Constant')
      air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(terminal, building_type, thermal_zone_outdoor_airflow_rate_per_area(zone))
      terminal.setMaximumFlowFractionDuringReheat(0.5)
      terminal.setMaximumReheatAirTemperature(rht_sa_temp_c)
      air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

      # Zone sizing
      # TODO Create general logic for cooling airflow method.
      # Large hotel uses design day with limit, school uses design day.
      sizing_zone = zone.sizingZone
      if building_type == 'SecondarySchool'
        sizing_zone.setCoolingDesignAirFlowMethod('DesignDay')
      else
        sizing_zone.setCoolingDesignAirFlowMethod('DesignDayWithLimit')
      end
      sizing_zone.setHeatingDesignAirFlowMethod('DesignDay')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zone_htg_sa_temp_c)

      unless return_plenum.nil?
        zone.setReturnPlenum(return_plenum)
      end
    end

    # Set the damper action based on the template.
    air_loop_hvac_apply_vav_damper_action(air_loop)

    return air_loop
  end

  # Creates a VAV system with parallel fan powered boxes and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param chilled_water_loop [String] chilled water loop to connect cooling coil to
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @param vav_fan_efficiency [Double] fan total efficiency, including motor and impeller
  # @param vav_fan_motor_efficiency [Double] fan motor efficiency
  # @param vav_fan_pressure_rise [Double] fan pressure rise, inH2O
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
  def model_add_vav_pfp_boxes(model,
                              system_name,
                              chilled_water_loop,
                              thermal_zones,
                              hvac_op_sch,
                              oa_damper_sch,
                              vav_fan_efficiency,
                              vav_fan_motor_efficiency,
                              vav_fan_pressure_rise)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding VAV with PFP Boxes and Reheat system for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # control temps used across all air handlers
    clg_sa_temp_f = 55.04 # Central deck clg temp 55F
    prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
    preclg_sa_temp_f = 55.04 # Precool to 55F
    htg_sa_temp_f = 55.04 # Central deck htg temp 55F
    rht_sa_temp_f = 104 # VAV box reheat to 104F
    zone_htg_sa_temp_f = 104 # Zone heating design supply air temperature to 104 F

    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
    preclg_sa_temp_c = OpenStudio.convert(preclg_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
    rht_sa_temp_c = OpenStudio.convert(rht_sa_temp_f, 'F', 'C').get
    zone_htg_sa_temp_c = OpenStudio.convert(zone_htg_sa_temp_f, 'F', 'C').get

    sa_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sa_temp_sch.setName("Supply Air Temp - #{clg_sa_temp_f}F")
    sa_temp_sch.defaultDaySchedule.setName("Supply Air Temp - #{clg_sa_temp_f}F Default")
    sa_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_sa_temp_c)

    # air handler
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone VAV with PFP Boxes and Reheat")
    else
      air_loop.setName(system_name)
    end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    sa_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sa_temp_sch)
    sa_stpt_manager.setName("#{thermal_zones.size} Zone VAV supply air setpoint manager")
    sa_stpt_manager.addToNode(air_loop.supplyOutletNode)

    # air handler controls
    sizing_system = air_loop.sizingSystem
    sizing_system.setPreheatDesignTemperature(prehtg_sa_temp_c)
    sizing_system.setPrecoolDesignTemperature(preclg_sa_temp_c)
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
    sizing_system.setSizingOption('Coincident')
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    sizing_system.setSystemOutdoorAirMethod('ZoneSum')

    # fan
    # @type [OpenStudio::Model::FanVariableVolume] fan
    fan = create_fan_by_name(model, 'VAV_System_Fan', fan_name:"#{air_loop.name} Fan",
                             fan_efficiency:vav_fan_efficiency, pressure_rise:vav_fan_pressure_rise,
                             motor_efficiency: vav_fan_motor_efficiency, end_use_subcategory:"VAV system Fans")
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.addToNode(air_loop.supplyInletNode)

    # heating coil
    htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Htg Coil")
    htg_coil.addToNode(air_loop.supplyInletNode)

    # cooling coil
    clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    clg_coil.addToNode(air_loop.supplyInletNode)

    # outdoor air intake system
    oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_intake_controller.setName("#{air_loop.name} OA Controller")
    oa_intake_controller.setMinimumLimitType('FixedMinimum')
    oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
    # oa_intake_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)

    controller_mv = oa_intake_controller.controllerMechanicalVentilation
    controller_mv.setName("#{air_loop.name} Vent Controller")
    controller_mv.setSystemOutdoorAirMethod('VentilationRateProcedure')

    oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
    oa_intake.setName("#{air_loop.name} OA Sys")
    oa_intake.addToNode(air_loop.supplyInletNode)

    # The oa system need to be added before setting the night cycle control
    air_loop.setNightCycleControlType('CycleOnAny')

    # hook the VAV system to each zone
    thermal_zones.each do |zone|
      # reheat coil
      rht_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} Electric Reheat Coil")

      # terminal fan
      # @type [OpenStudio::Model::FanConstantVolume] pfp_fan
      pfp_fan = create_fan_by_name(model, 'PFP_Fan', fan_name:"#{zone.name} PFP Term Fan")
      pfp_fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      # parallel fan powered terminal
      pfp_terminal = OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat.new(model,
                                                                                   model.alwaysOnDiscreteSchedule,
                                                                                   pfp_fan,
                                                                                   rht_coil)
      pfp_terminal.setName("#{zone.name} PFP Term")
      air_loop.addBranchForZone(zone, pfp_terminal.to_StraightComponent)

      # Zone sizing
      # TODO Create general logic for cooling airflow method.
      # Large hotel uses design day with limit, school uses design day.
      sizing_zone = zone.sizingZone
      sizing_zone.setCoolingDesignAirFlowMethod('DesignDay')
      sizing_zone.setHeatingDesignAirFlowMethod('DesignDay')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      # sizing_zone.setZoneHeatingDesignSupplyAirTemperature(rht_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zone_htg_sa_temp_c)
    end

    return air_loop
  end

  # Creates a packaged VAV system and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @param electric_reheat [Bool] if true electric reheat coils, if false the reheat coils served by hot_water_loop
  # @param hot_water_loop [String] hot water loop to connect heating and reheat coils to. If nil, will be electric heat and electric reheat
  # @param chilled_water_loop [String] chilled water loop to connect cooling coils to. If nil, will be DX cooling.
  # @param return_plenum [OpenStudio::Model::ThermalZone] the zone to attach as the supply plenum, or nil, in which case no return plenum will be used.
  # @param building_type [String] the building type
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting packaged VAV air loop
  def model_add_pvav(model,
                     system_name,
                     thermal_zones,
                     hvac_op_sch,
                     oa_damper_sch,
                     electric_reheat = false,
                     hot_water_loop = nil,
                     chilled_water_loop = nil,
                     return_plenum = nil,
                     building_type = nil)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding Packaged VAV for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # Control temps for HW loop
    # will only be used when hot_water_loop is provided.
    hw_temp_f = 180 # HW setpoint 180F
    hw_delta_t_r = 20 # 20F delta-T

    hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get

    # Control temps used across all air handlers
    sys_dsn_prhtg_temp_f = 44.6 # Design central deck to preheat to 44.6F
    sys_dsn_clg_sa_temp_f = 55 # Design central deck to cool to 55F
    sys_dsn_htg_sa_temp_f = 55 # Central heat to 55F
    zn_dsn_clg_sa_temp_f = 55 # Design VAV box for 55F from central deck
    zn_dsn_htg_sa_temp_f = 122 # Design VAV box to reheat to 122F
    rht_rated_air_in_temp_f = 55 # Reheat coils designed to receive 55F
    rht_rated_air_out_temp_f = 122 # Reheat coils designed to supply 122F
    clg_sa_temp_f = 55 # Central deck clg temp operates at 55F

    sys_dsn_prhtg_temp_c = OpenStudio.convert(sys_dsn_prhtg_temp_f, 'F', 'C').get
    sys_dsn_clg_sa_temp_c = OpenStudio.convert(sys_dsn_clg_sa_temp_f, 'F', 'C').get
    sys_dsn_htg_sa_temp_c = OpenStudio.convert(sys_dsn_htg_sa_temp_f, 'F', 'C').get
    zn_dsn_clg_sa_temp_c = OpenStudio.convert(zn_dsn_clg_sa_temp_f, 'F', 'C').get
    zn_dsn_htg_sa_temp_c = OpenStudio.convert(zn_dsn_htg_sa_temp_f, 'F', 'C').get
    rht_rated_air_in_temp_c = OpenStudio.convert(rht_rated_air_in_temp_f, 'F', 'C').get
    rht_rated_air_out_temp_c = OpenStudio.convert(rht_rated_air_out_temp_f, 'F', 'C').get
    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get

    sa_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sa_temp_sch.setName("Supply Air Temp - #{clg_sa_temp_f}F")
    sa_temp_sch.defaultDaySchedule.setName("Supply Air Temp - #{clg_sa_temp_f}F Default")
    sa_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_sa_temp_c)

    # Air handler
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone PVAV")
    else
      air_loop.setName(system_name)
    end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    # Air handler controls
    stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sa_temp_sch)
    stpt_manager.addToNode(air_loop.supplyOutletNode)
    sizing_system = air_loop.sizingSystem
    # sizing_system.setPreheatDesignTemperature(sys_dsn_prhtg_temp_c)
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(sys_dsn_clg_sa_temp_c)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(sys_dsn_htg_sa_temp_c)
    sizing_system.setSizingOption('Coincident')
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    air_loop.setNightCycleControlType('CycleOnAny')

    # create fan
    fan = create_fan_by_name(model, 'VAV_default', fan_name:"#{air_loop.name} Fan")
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.addToNode(air_loop.supplyInletNode)

    # Heating coil - depends on whether heating is hot water or electric, which is determined by whether or not a hot water loop is provided.
    if hot_water_loop.nil?
      htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Main Gas Htg Coil")
      htg_coil.addToNode(air_loop.supplyInletNode)
    else
      htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{air_loop.name} Main Htg Coil",
                                           rated_inlet_water_temperature: hw_temp_c,
                                           rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                           rated_inlet_air_temperature: sys_dsn_prhtg_temp_c,
                                           rated_outlet_air_temperature: rht_rated_air_out_temp_c)
      htg_coil.addToNode(air_loop.supplyInletNode)
    end

    # Cooling coil
    if chilled_water_loop.nil?
      clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name} 2spd DX Clg Coil", type:'OS default')
    else
      clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    end
    clg_coil.addToNode(air_loop.supplyInletNode)

    # Outdoor air intake system
    oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_intake_controller.setMinimumLimitType('FixedMinimum')
    oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
    oa_intake_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)
    oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
    oa_intake.setName("#{air_loop.name} OA Sys")
    oa_intake.addToNode(air_loop.supplyInletNode)
    controller_mv = oa_intake_controller.controllerMechanicalVentilation
    controller_mv.setName("#{air_loop.name} Ventilation Controller")
    controller_mv.setAvailabilitySchedule(oa_damper_sch)

    # Hook the VAV system to each zone
    thermal_zones.each do |zone|
      # Reheat coil
      rht_coil = nil

      # TODO: system_name.include? "Outpatient F2 F3"  is only for reheat coil of Outpatient Floor2&3
      # add reheat type to system in hvac_map.json for the Outpatient models
      if electric_reheat || hot_water_loop.nil?
        rht_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} Electric Reheat Coil")
      else
        rht_coil = create_coil_heating_water(model, hot_water_loop, name: "#{zone.name} Rht Coil",
                                             rated_inlet_water_temperature: hw_temp_c,
                                             rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                             rated_inlet_air_temperature: rht_rated_air_in_temp_c,
                                             rated_outlet_air_temperature: rht_rated_air_out_temp_c)
      end

      # VAV terminal
      terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, rht_coil)
      terminal.setName("#{zone.name} VAV Term")
      terminal.setZoneMinimumAirFlowMethod('Constant')
      terminal.setMaximumReheatAirTemperature(rht_rated_air_out_temp_c)
      air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(terminal, building_type, thermal_zone_outdoor_airflow_rate_per_area(zone))
      air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

      unless return_plenum.nil?
        zone.setReturnPlenum(return_plenum)
      end

      # Zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(zn_dsn_clg_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zn_dsn_htg_sa_temp_c)
    end

    # Set the damper action based on the template.
    air_loop_hvac_apply_vav_damper_action(air_loop)

    return true
  end

  # Creates a packaged VAV system with parallel fan powered boxes and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @param vav_fan_efficiency [Double] fan total efficiency, including motor and impeller
  # @param vav_fan_motor_efficiency [Double] fan motor efficiency
  # @param vav_fan_pressure_rise [Double] fan pressure rise, inH2O
  # @param chilled_water_loop [String] chilled water loop to connect cooling coils to. If nil, will be DX cooling.
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
  def model_add_pvav_pfp_boxes(model,
                               system_name,
                               thermal_zones,
                               hvac_op_sch,
                               oa_damper_sch,
                               vav_fan_efficiency,
                               vav_fan_motor_efficiency,
                               vav_fan_pressure_rise,
                               chilled_water_loop = nil)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding PVAV with PFP Boxes and Reheat system for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # control temps used across all air handlers
    clg_sa_temp_f = 55.04 # Central deck clg temp 55F
    prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
    preclg_sa_temp_f = 55.04 # Precool to 55F
    htg_sa_temp_f = 55.04 # Central deck htg temp 55F
    rht_sa_temp_f = 104 # VAV box reheat to 104F
    zone_htg_sa_temp_f = 104 # Zone heating design supply air temperature to 104 F

    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
    preclg_sa_temp_c = OpenStudio.convert(preclg_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
    rht_sa_temp_c = OpenStudio.convert(rht_sa_temp_f, 'F', 'C').get
    zone_htg_sa_temp_c = OpenStudio.convert(zone_htg_sa_temp_f, 'F', 'C').get

    sa_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sa_temp_sch.setName("Supply Air Temp - #{clg_sa_temp_f}F")
    sa_temp_sch.defaultDaySchedule.setName("Supply Air Temp - #{clg_sa_temp_f}F Default")
    sa_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_sa_temp_c)

    # air handler
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone VAV with PFP Boxes and Reheat")
    else
      air_loop.setName(system_name)
    end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    sa_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sa_temp_sch)
    sa_stpt_manager.setName("#{thermal_zones.size} Zone VAV supply air setpoint manager")
    sa_stpt_manager.addToNode(air_loop.supplyOutletNode)

    # air handler controls
    sizing_system = air_loop.sizingSystem
    sizing_system.setPreheatDesignTemperature(prehtg_sa_temp_c)
    sizing_system.setPrecoolDesignTemperature(preclg_sa_temp_c)
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
    sizing_system.setSizingOption('Coincident')
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    sizing_system.setSystemOutdoorAirMethod('ZoneSum')

    # fan
    # @type [OpenStudio::Model::FanVariableVolume] fan
    fan = create_fan_by_name(model, 'VAV_System_Fan', fan_name:"#{air_loop.name} Fan",
                             fan_efficiency:vav_fan_efficiency, pressure_rise:vav_fan_pressure_rise,
                             motor_efficiency: vav_fan_motor_efficiency, end_use_subcategory:"VAV system Fans")
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.addToNode(air_loop.supplyInletNode)

    # heating coil
    htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Main Htg Coil")
    htg_coil.addToNode(air_loop.supplyInletNode)

    # Cooling coil
    if chilled_water_loop.nil?
      clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name} 2spd DX Clg Coil", type:'OS default')
    else
      clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    end
    clg_coil.addToNode(air_loop.supplyInletNode)

    # outdoor air intake system
    oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_intake_controller.setName("#{air_loop.name} OA Controller")
    oa_intake_controller.setMinimumLimitType('FixedMinimum')
    oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
    oa_intake_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)

    controller_mv = oa_intake_controller.controllerMechanicalVentilation
    controller_mv.setName("#{air_loop.name} Vent Controller")
    controller_mv.setSystemOutdoorAirMethod('VentilationRateProcedure')

    oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
    oa_intake.setName("#{air_loop.name} OA Sys")
    oa_intake.addToNode(air_loop.supplyInletNode)

    # The oa system need to be added before setting the night cycle control
    air_loop.setNightCycleControlType('CycleOnAny')

    # hook the VAV system to each zone
    thermal_zones.each do |zone|
      # reheat coil
      rht_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} Electric Reheat Coil")

      # terminal fan
      # @type [OpenStudio::Model::FanConstantVolume] pfp_fan
      pfp_fan = create_fan_by_name(model, 'PFP_Fan', fan_name:"#{zone.name} PFP Term Fan")
      pfp_fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      # parallel fan powered terminal
      pfp_terminal = OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat.new(model,
                                                                                   model.alwaysOnDiscreteSchedule,
                                                                                   pfp_fan,
                                                                                   rht_coil)
      pfp_terminal.setName("#{zone.name} PFP Term")
      air_loop.addBranchForZone(zone, pfp_terminal.to_StraightComponent)

      # Zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setCoolingDesignAirFlowMethod('DesignDay')
      sizing_zone.setHeatingDesignAirFlowMethod('DesignDay')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      # sizing_zone.setZoneHeatingDesignSupplyAirTemperature(rht_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zone_htg_sa_temp_c)
    end

    return air_loop
  end

  # Creates a packaged VAV system and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param hot_water_loop [String] hot water loop to connect heating and reheat coils to.
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule
  # or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule,
  # or nil in which case will be defaulted to always open
  # @param fan_efficiency [Double] fan total efficiency, including motor and impeller
  # @param fan_motor_efficiency [Double] fan motor efficiency
  # @param fan_pressure_rise [Double] fan pressure rise, inH2O
  # @param chilled_water_loop [String] chilled water loop to connect cooling coil to.
  # @param building_type [String] the building type
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting packaged VAV air loop
  def model_add_cav(model,
                    system_name,
                    hot_water_loop,
                    thermal_zones,
                    hvac_op_sch,
                    oa_damper_sch,
                    fan_efficiency,
                    fan_motor_efficiency,
                    fan_pressure_rise,
                    chilled_water_loop = nil,
                    building_type = nil)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding CAV for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # Hot water loop control temperatures
    hw_temp_f = 152.6 # HW setpoint 152.6F
    hw_temp_f = 180 if building_type == 'Hospital'
    hw_delta_t_r = 20 # 20F delta-T
    hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get
    air_flow_ratio = 1

    # Air handler control temperatures
    clg_sa_temp_f = 55.04 # Central deck clg temp 55F
    prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
    prehtg_sa_temp_f = 55.04 if building_type == 'Hospital'
    preclg_sa_temp_f = 55.04 # Precool to 55F
    htg_sa_temp_f = 62.06 # Central deck htg temp 62.06F
    rht_sa_temp_f = 122 # VAV box reheat to 104F
    zone_htg_sa_temp_f = 122 # Zone heating design supply air temperature to 122F
    if building_type == 'Hospital'
      htg_sa_temp_f = 104 # Central deck htg temp 104F
      # rht_sa_temp_f = 122 # VAV box reheat to 104F
      zone_htg_sa_temp_f = 104 # Zone heating design supply air temperature to 122F
    end
    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
    preclg_sa_temp_c = OpenStudio.convert(preclg_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
    rht_sa_temp_c = OpenStudio.convert(rht_sa_temp_f, 'F', 'C').get
    zone_htg_sa_temp_c = OpenStudio.convert(zone_htg_sa_temp_f, 'F', 'C').get

    # Air handler
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    if system_name.nil?
      air_loop.setName("#{thermal_zones.size} Zone CAV")
    else
      air_loop.setName(system_name)
    end
    air_loop.setAvailabilitySchedule(hvac_op_sch)

    # Air handler supply air setpoint
    sa_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    sa_temp_sch.setName("Supply Air Temp - #{clg_sa_temp_f}F")
    sa_temp_sch.defaultDaySchedule.setName("Supply Air Temp - #{clg_sa_temp_f}F Default")
    sa_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_sa_temp_c)

    sa_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sa_temp_sch)
    sa_stpt_manager.setName("#{air_loop.name} supply air setpoint manager")
    sa_stpt_manager.addToNode(air_loop.supplyOutletNode)

    # Air handler sizing
    sizing_system = air_loop.sizingSystem
    sizing_system.setMinimumSystemAirFlowRatio(air_flow_ratio)
    sizing_system.setPreheatDesignTemperature(prehtg_sa_temp_c)
    sizing_system.setPrecoolDesignTemperature(preclg_sa_temp_c)
    sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
    sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
    sizing_system.setSizingOption('Coincident')
    sizing_system.setAllOutdoorAirinCooling(false)
    sizing_system.setAllOutdoorAirinHeating(false)
    sizing_system.setSystemOutdoorAirMethod('ZoneSum')

    # TODO: remove building type specific logic
    sizing_system.setSizingOption('NonCoincident') if building_type == 'Hospital'

    # create fan
    if building_type == 'Hospital'
      fan = create_fan_by_name(model, 'Hospital_CAV_Sytem_Fan', fan_name:"#{air_loop.name} Fan",
                               end_use_subcategory:'CAV system Fans')
    else
      fan = create_fan_by_name(model, 'Packaged_RTU_SZ_AC_CAV_Fan', fan_name:"#{air_loop.name} Fan",
                               fan_efficiency:fan_efficiency, pressure_rise:fan_pressure_rise,
                               motor_efficiency: fan_motor_efficiency, end_use_subcategory:'CAV system Fans')
    end
    fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    fan.addToNode(air_loop.supplyInletNode)

    # Air handler heating coil
    htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{air_loop.name} Main Htg Coil",
                                         rated_inlet_water_temperature: hw_temp_c,
                                         rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                         rated_inlet_air_temperature: prehtg_sa_temp_c,
                                         rated_outlet_air_temperature: htg_sa_temp_c)
    htg_coil.addToNode(air_loop.supplyInletNode)

    # Air handler cooling coil
    if chilled_water_loop.nil?
      clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name} 2spd DX Clg Coil", type:'OS default')
    else
      clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Clg Coil")
    end
    clg_coil.addToNode(air_loop.supplyInletNode)

    # Outdoor air intake system
    oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_intake_controller.setName("#{air_loop.name} OA Controller")
    oa_intake_controller.setMinimumLimitType('FixedMinimum')
    oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
    # oa_intake_controller.setMinimumOutdoorAirSchedule(motorized_oa_damper_sch)
    oa_intake_controller.setMinimumFractionofOutdoorAirSchedule(oa_damper_sch)

    controller_mv = oa_intake_controller.controllerMechanicalVentilation
    controller_mv.setName("#{air_loop.name} Vent Controller")
    controller_mv.setSystemOutdoorAirMethod('ZoneSum')

    oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
    oa_intake.setName("#{air_loop.name} OA Sys")
    oa_intake.addToNode(air_loop.supplyInletNode)

    # The oa system needs to be added before setting the night cycle control
    air_loop.setNightCycleControlType('CycleOnAny')

    # Connect the CAV system to each zone
    thermal_zones.each do |zone|
      if building_type == 'Hospital'
        # CAV terminal
        terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
        terminal.setName("#{zone.name} CAV Term")
      else
        # Reheat coil
        rht_coil = create_coil_heating_water(model, hot_water_loop, name: "#{zone.name} Rht Coil",
                                             rated_inlet_water_temperature: hw_temp_c,
                                             rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                             rated_inlet_air_temperature: htg_sa_temp_c,
                                             rated_outlet_air_temperature: rht_sa_temp_c)
        # VAV terminal
        terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, rht_coil)
        terminal.setName("#{zone.name} VAV Term")
        terminal.setZoneMinimumAirFlowMethod('Constant')
        air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(terminal, building_type, thermal_zone_outdoor_airflow_rate_per_area(zone))
        terminal.setMaximumFlowPerZoneFloorAreaDuringReheat(0.0)
        terminal.setMaximumFlowFractionDuringReheat(0.5)
        terminal.setMaximumReheatAirTemperature(rht_sa_temp_c)
      end
      air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

      # Zone sizing
      # TODO Create general logic for cooling airflow method.
      # Large hotel uses design day with limit, school uses design day.
      sizing_zone = zone.sizingZone
      if building_type == 'SecondarySchool'
        sizing_zone.setCoolingDesignAirFlowMethod('DesignDay')
      else
        sizing_zone.setCoolingDesignAirFlowMethod('DesignDayWithLimit')
      end
      sizing_zone.setHeatingDesignAirFlowMethod('DesignDay')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      # sizing_zone.setZoneHeatingDesignSupplyAirTemperature(rht_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(zone_htg_sa_temp_c)
    end

    # Set the damper action based on the template.
    air_loop_hvac_apply_vav_damper_action(air_loop)

    return true
  end

  # Creates a PSZ-AC system for each zone and adds it to the model.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param hot_water_loop [String] hot water loop to connect heating coil to, or nil
  # @param chilled_water_loop [String] chilled water loop to connect cooling coil to, or nil
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @param fan_location [Double] valid choices are BlowThrough, DrawThrough
  # @param fan_type [Double] valid choices are ConstantVolume, Cycling
  # @param heating_type [Double] valid choices are NaturalGas, Electricity, Water, nil (no heat),
  #   Single Speed Heat Pump, Water To Air Heat Pump
  # @param supplemental_heating_type [Double] valid choices are Electricity, NaturalGas,  nil (no heat)
  # @param cooling_type [String] valid choices are Water, Two Speed DX AC,
  #   Single Speed DX AC, Single Speed Heat Pump, Water To Air Heat Pump
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting PSZ-AC air loops
  def model_add_psz_ac(model,
                       system_name,
                       hot_water_loop,
                       chilled_water_loop,
                       thermal_zones,
                       hvac_op_sch,
                       oa_damper_sch,
                       fan_location,
                       fan_type,
                       heating_type,
                       supplemental_heating_type,
                       cooling_type)

    hw_temp_f = 180 # HW setpoint 180F
    hw_delta_t_r = 20 # 20F delta-T
    hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
    hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get

    # control temps used across all air handlers
    clg_sa_temp_f = 55 # Central deck clg temp 55F
    prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
    htg_sa_temp_f = 55 # Central deck htg temp 55F
    rht_sa_temp_f = 104 # VAV box reheat to 104F

    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
    rht_sa_temp_c = OpenStudio.convert(rht_sa_temp_f, 'F', 'C').get

    # hvac operation schedule
    hvac_op_sch = if hvac_op_sch.nil?
                    model.alwaysOnDiscreteSchedule
                  else
                    model_add_schedule(model, hvac_op_sch)
                  end

    # oa damper schedule
    oa_damper_sch = if oa_damper_sch.nil?
                      model.alwaysOnDiscreteSchedule
                    else
                      model_add_schedule(model, oa_damper_sch)
                    end

    # Make a PSZ-AC for each zone
    air_loops = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding PSZ-AC for #{zone.name}.")

      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      if system_name.nil?
        air_loop.setName("#{zone.name} PSZ-AC")
      else
        air_loop.setName("#{zone.name} #{system_name}")
      end
      air_loop.setAvailabilitySchedule(hvac_op_sch)
      air_loops << air_loop

      # When an air_loop is contructed, its constructor creates a sizing:system object
      # the default sizing:system contstructor makes a system:sizing object
      # appropriate for a multizone VAV system
      # this systems is a constant volume system with no VAV terminals,
      # and therfore needs different default settings
      air_loop_sizing = air_loop.sizingSystem # TODO units
      air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
      air_loop_sizing.autosizeDesignOutdoorAirFlowRate
      air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
      air_loop_sizing.setPreheatDesignTemperature(7.0)
      air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
      air_loop_sizing.setPrecoolDesignTemperature(12.8)
      air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
      air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(12.8)
      air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(40.0)
      air_loop_sizing.setSizingOption('Coincident')
      air_loop_sizing.setAllOutdoorAirinCooling(false)
      air_loop_sizing.setAllOutdoorAirinHeating(false)
      air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
      air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
      air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

      # Zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(12.8)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(40.0)

      # Add a setpoint manager single zone reheat to control the
      # supply air temperature based on the needs of this zone
      setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
      setpoint_mgr_single_zone_reheat.setControlZone(zone)

      # ConstantVolume: Packaged Rooftop Single Zone Air conditioner;
      # Cycling: Unitary System;
      # CyclingHeatPump: Unitary Heat Pump system
      if fan_type == 'ConstantVolume'
        fan = create_fan_by_name(model, 'Packaged_RTU_SZ_AC_CAV_Fan', fan_name:"#{air_loop.name} Fan")
        fan.setAvailabilitySchedule(hvac_op_sch)
      elsif fan_type == 'Cycling'
        fan = create_fan_by_name(model, 'Packaged_RTU_SZ_AC_Cycling_Fan', fan_name:"#{air_loop.name} Fan")
        fan.setAvailabilitySchedule(hvac_op_sch)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Fan type '#{fan_type}' not recognized, cannot add PSZ-AC.")
        return []
      end

      htg_coil = nil
      case heating_type
      when 'NaturalGas', 'Gas'
        htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Gas Htg Coil")
      when nil
        # Zero-capacity, always-off electric heating coil
        htg_coil = create_coil_heating_electric(model,
                                                name: "#{air_loop.name.to_s} No Heat",
                                                schedule: model.alwaysOffDiscreteSchedule,
                                                nominal_capacity: 0)
      when 'Water'
        if hot_water_loop.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No hot water plant loop supplied')
          return false
        end
        htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{air_loop.name} Water Htg Coil",
                                             rated_inlet_water_temperature: hw_temp_c,
                                             rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                             rated_inlet_air_temperature: prehtg_sa_temp_c,
                                             rated_outlet_air_temperature: htg_sa_temp_c)
      when 'Single Speed Heat Pump'
        htg_coil = create_coil_heating_dx_single_speed(model, name: "#{zone.name} HP Htg Coil", type: "PSZ-AC", cop: 3.3)
      when 'Water To Air Heat Pump'
        htg_coil = create_coil_heating_water_to_air_heat_pump_equation_fit(model, hot_water_loop, name: "#{air_loop.name} Water-to-Air HP Htg Coil")
      when 'Electricity', 'Electric'
        htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Htg Coil")
      end

      supplemental_htg_coil = nil
      case supplemental_heating_type
      when 'Electricity', 'Electric' # TODO: change spreadsheet to Electricity
        supplemental_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Backup Htg Coil")
      when 'NaturalGas', 'Gas'
        supplemental_htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Gas Backup Htg Coil")
      when nil
        # Zero-capacity, always-off electric heating coil
        supplemental_htg_coil = create_coil_heating_electric(model,
                                                             name: "#{air_loop.name.to_s} No Backup Heat",
                                                             schedule: model.alwaysOffDiscreteSchedule,
                                                             nominal_capacity: 0)
      end

      clg_coil = nil
      if cooling_type == 'Water'
        if chilled_water_loop.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No chilled water plant loop supplied')
          return false
        end
        clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{air_loop.name} Water Clg Coil")
      elsif cooling_type == 'Two Speed DX AC'
        clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name} 2spd DX AC Clg Coil")
      elsif cooling_type == 'Single Speed DX AC'
        clg_coil = create_coil_cooling_dx_single_speed(model,
                                                       name:"#{air_loop.name} 1spd DX AC Clg Coil",
                                                       type:'PSZ-AC')
      elsif cooling_type == 'Single Speed Heat Pump'
        clg_coil = create_coil_cooling_dx_single_speed(model,
                                                       name:"#{air_loop.name} 1spd DX HP Clg Coil",
                                                       type:'Heat Pump')
        # clg_coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(OpenStudio::OptionalDouble.new(10.0))
        # clg_coil.setRatedSensibleHeatRatio(0.69)
        # clg_coil.setBasinHeaterCapacity(10)
        # clg_coil.setBasinHeaterSetpointTemperature(2.0)
      elsif cooling_type == 'Water To Air Heat Pump'
        if chilled_water_loop.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No chilled water plant loop supplied')
          return false
        end
        clg_coil = create_coil_cooling_water_to_air_heat_pump_equation_fit(model, chilled_water_loop, name: "#{air_loop.name} Water-to-Air HP Clg Coil")
      end

      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.setName("#{air_loop.name} OA Sys Controller")
      oa_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
      oa_system.setName("#{air_loop.name} OA Sys")
      econ_eff_sch = model_add_schedule(model, 'RetailStandalone PSZ_Econ_MaxOAFrac_Sch')

      # Add the components to the air loop in order from closest to zone to furthest from zone

      # Wrap coils in a unitary system or not, depending on the system type
      if fan_type == 'Cycling'

        if heating_type == 'Water To Air Heat Pump'
          unitary_system = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
          unitary_system.setSupplyFan(fan)
          unitary_system.setHeatingCoil(htg_coil)
          unitary_system.setCoolingCoil(clg_coil)
          unitary_system.setSupplementalHeatingCoil(supplemental_htg_coil)
          unitary_system.setName("#{zone.name} Unitary HP")
          unitary_system.setControllingZoneorThermostatLocation(zone)
          unitary_system.setMaximumSupplyAirTemperature(50)
          unitary_system.setFanPlacement('BlowThrough')
          unitary_system.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
          unitary_system.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
          unitary_system.setSupplyAirFlowRateMethodWhenNoCoolingorHeatingisRequired('SupplyAirFlowRate')
          unitary_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOnDiscreteSchedule)
          unitary_system.addToNode(air_loop.supplyInletNode)
          setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(50)
        else
          unitary_system = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model,
                                                                                     model.alwaysOnDiscreteSchedule,
                                                                                     fan,
                                                                                     htg_coil,
                                                                                     clg_coil,
                                                                                     supplemental_htg_coil)
          unitary_system.setName("#{air_loop.name} Unitary HP")
          unitary_system.setControllingZone(zone)
          unitary_system.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(OpenStudio.convert(40, 'F', 'C').get)
          unitary_system.setFanPlacement(fan_location)
          unitary_system.setSupplyAirFanOperatingModeSchedule(hvac_op_sch)
          unitary_system.addToNode(air_loop.supplyInletNode)

          setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(OpenStudio.convert(55, 'F', 'C').get)
          setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(OpenStudio.convert(104, 'F', 'C').get)
        end

      else
        if fan_location == 'DrawThrough'
          # Add the fan
          unless fan.nil?
            fan.addToNode(air_loop.supplyInletNode)
          end

          # Add the supplemental heating coil
          unless supplemental_htg_coil.nil?
            supplemental_htg_coil.addToNode(air_loop.supplyInletNode)
          end

          # Add the heating coil
          unless htg_coil.nil?
            htg_coil.addToNode(air_loop.supplyInletNode)
          end

          # Add the cooling coil
          unless clg_coil.nil?
            clg_coil.addToNode(air_loop.supplyInletNode)
          end
        elsif fan_location == 'BlowThrough'
          # Add the supplemental heating coil
          unless supplemental_htg_coil.nil?
            supplemental_htg_coil.addToNode(air_loop.supplyInletNode)
          end

          # Add the cooling coil
          unless clg_coil.nil?
            clg_coil.addToNode(air_loop.supplyInletNode)
          end

          # Add the heating coil
          unless htg_coil.nil?
            htg_coil.addToNode(air_loop.supplyInletNode)
          end

          # Add the fan
          unless fan.nil?
            fan.addToNode(air_loop.supplyInletNode)
          end
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Invalid fan location')
          return false
        end

        setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(OpenStudio.convert(50, 'F', 'C').get)
        setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(OpenStudio.convert(122, 'F', 'C').get)

      end

      # Add the OA system
      oa_system.addToNode(air_loop.supplyInletNode)

      # Attach the nightcycle manager to the supply outlet node
      setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)
      air_loop.setNightCycleControlType('CycleOnAny')

      # Create a diffuser and attach the zone/diffuser pair to the air loop
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName("#{air_loop.name} Diffuser")
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
    end

    return air_loops
  end

  # Creates a packaged single zone VAV system for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param heating_type [Double] valid choices are NaturalGas, Electricity, Water, nil (no heat)
  # @param supplemental_heating_type [Double] valid choices are Electricity, NaturalGas,  nil (no heat)
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting PSZ-AC air loops
  def model_add_psz_vav(model,
                        thermal_zones,
                        system_name: nil,
                        heating_type: nil,
                        supplemental_heating_type: nil,
                        hvac_op_sch: nil,
                        oa_damper_sch: nil)

    # hvac operation schedule
    if hvac_op_sch.nil?
      hvac_op_sch = model.alwaysOnDiscreteSchedule
    else
      hvac_op_sch = model_add_schedule(model, hvac_op_sch)
    end

    # oa damper schedule
    if oa_damper_sch.nil?
      oa_damper_sch = model.alwaysOnDiscreteSchedule
    else
      oa_damper_sch = model_add_schedule(model, oa_damper_sch)
    end

    # create a PSZ-VAV for each zone
    air_loops = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding PSZ-VAV for #{zone.name}.")

      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      if system_name.nil?
        air_loop.setName("#{zone.name} PSZ-VAV")
      else
        air_loop.setName("#{zone.name} #{system_name}")
      end
      air_loop.setAvailabilitySchedule(hvac_op_sch)
      air_loop.setNightCycleControlType('CycleOnAny')

      # adjust system sizing
      air_loop_sizing = air_loop.sizingSystem
      air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
      air_loop_sizing.autosizeDesignOutdoorAirFlowRate
      air_loop_sizing.setMinimumSystemAirFlowRatio(0.0)
      air_loop_sizing.setPreheatDesignTemperature(7.0)
      air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
      air_loop_sizing.setPrecoolDesignTemperature(12.8)
      air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
      air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(12.8)
      air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(40.0)
      air_loop_sizing.setSizingOption('Coincident')
      air_loop_sizing.setAllOutdoorAirinCooling(false)
      air_loop_sizing.setAllOutdoorAirinHeating(false)
      air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
      air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
      air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(40.0)

      # add a setpoint manager single zone reheat to control the supply air temperature
      setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
      setpoint_mgr_single_zone_reheat.setControlZone(zone)

      # create fan
      # @type [OpenStudio::Model::FanVariableVolume] fan
      fan = create_fan_by_name(model, 'VAV_System_Fan', fan_name:"#{air_loop.name} Fan",
                               end_use_subcategory:"VAV System Fans")
      fan.setAvailabilitySchedule(hvac_op_sch)

      # create heating coil
      htg_coil = nil
      case heating_type
      when 'NaturalGas', 'Gas'
        htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Gas Htg Coil")
      when 'Electricity', 'Electric'
        htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Htg Coil")
      when nil
        # Zero-capacity, always-off electric heating coil
        htg_coil = create_coil_heating_electric(model,
                                                name: "#{air_loop.name.to_s} No Heat",
                                                schedule: model.alwaysOffDiscreteSchedule,
                                                nominal_capacity: 0.0)
      end

      # create supplemental heating coil
      supplemental_htg_coil = nil
      case supplemental_heating_type
      when 'Electricity', 'Electric'
        supplemental_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Backup Htg Coil")
      when 'NaturalGas', 'Gas'
        supplemental_htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Gas Backup Htg Coil")
      when nil
        # zero-capacity, always-off electric heating coil
        supplemental_htg_coil = create_coil_heating_electric(model,
                                                             name: "#{air_loop.name.to_s} No Backup Heat",
                                                             schedule: model.alwaysOffDiscreteSchedule,
                                                             nominal_capacity: 0.0)
      end

      # create cooling coil
      clg_coil = OpenStudio::Model::CoilCoolingDXVariableSpeed.new(model)
      clg_coil.setName("#{air_loop.name} Var spd DX AC Clg Coil")
      clg_coil.setBasinHeaterCapacity(10)
      clg_coil.setBasinHeaterSetpointTemperature(2.0)
      # first speed level
      clg_spd_1 = OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData.new(model)
      clg_coil.addSpeed(clg_spd_1)
      clg_coil.setNominalSpeedLevel(1)

      # TODO: assign economizer schedule
      econ_eff_sch = model_add_schedule(model, 'RetailStandalone PSZ_Econ_MaxOAFrac_Sch')

      # wrap coils in a unitary system
      unitary_system = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      unitary_system.setSupplyFan(fan)
      unitary_system.setHeatingCoil(htg_coil)
      unitary_system.setCoolingCoil(clg_coil)
      unitary_system.setSupplementalHeatingCoil(supplemental_htg_coil)
      unitary_system.setName("#{zone.name} Unitary PSZ-VAV")
      unitary_system.setString(2, 'SingleZoneVAV') # TODO add setControlType() method
      unitary_system.setControllingZoneorThermostatLocation(zone)
      unitary_system.setMaximumSupplyAirTemperature(50)
      unitary_system.setFanPlacement('BlowThrough')
      unitary_system.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
      unitary_system.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      unitary_system.setSupplyAirFlowRateMethodWhenNoCoolingorHeatingisRequired('SupplyAirFlowRate')
      unitary_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOnDiscreteSchedule)
      unitary_system.addToNode(air_loop.supplyInletNode)

      # create outdoor air system
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.setName("#{air_loop.name} OA Sys Controller")
      oa_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)
      oa_controller.autosizeMinimumOutdoorAirFlowRate
      oa_controller.setHeatRecoveryBypassControlType('BypassWhenOAFlowGreaterThanMinimum')
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
      oa_system.setName("#{air_loop.name} OA Sys")
      oa_system.addToNode(air_loop.supplyInletNode)

      # create a VAV no reheat terminal and attach the zone/terminal pair to the air loop
      diffuser = OpenStudio::Model::AirTerminalSingleDuctVAVNoReheat.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName("#{air_loop.name} Diffuser")
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
      air_loops << air_loop
    end

    return air_loops
  end
  
  # Adds a data center load to a given space.
  #
  # @param space [OpenStudio::Model::Space] which space to assign the data center loads to
  # @param dc_watts_per_area [Double] data center load, in W/m^2
  # @return [Bool] returns true if successful, false if not
  def model_add_data_center_load(model, space, dc_watts_per_area)
    # create data center load
    data_center_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    data_center_definition.setName('Data Center Load')
    data_center_definition.setWattsperSpaceFloorArea(dc_watts_per_area)
    data_center_equipment = OpenStudio::Model::ElectricEquipment.new(data_center_definition)
    data_center_equipment.setName('Data Center Load')
    data_center_sch = model.alwaysOnDiscreteSchedule
    data_center_equipment.setSchedule(data_center_sch)
    data_center_equipment.setSpace(space)

    return true
  end

  # Creates a data center PSZ-AC system for each zone.
  #
  # @param system_name [String] the name of the system, or nil in which case it will be defaulted
  # @param hot_water_loop [String] hot water loop to connect to the heating coil
  # @param heat_pump_loop [String] heat pump water loop to connect to heat pump
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule or nil in which case will be defaulted to always open
  # @param main_data_center [Bool] whether or not this is the main data center in the building.
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting air loops
  def model_add_data_center_hvac(model,
                                 thermal_zones,
                                 hot_water_loop,
                                 heat_pump_loop,
                                 system_name: nil,
                                 hvac_op_sch: nil,
                                 oa_damper_sch: nil,
                                 main_data_center: false)

    # hvac operation schedule
    if hvac_op_sch.nil?
      hvac_op_sch = model.alwaysOnDiscreteSchedule
    else
      hvac_op_sch = model_add_schedule(model, hvac_op_sch)
    end

    # oa damper schedule
    if oa_damper_sch.nil?
      oa_damper_sch = model.alwaysOnDiscreteSchedule
    else
      oa_damper_sch = model_add_schedule(model, oa_damper_sch)
    end

    # create a PSZ-AC for each zone
    air_loops = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding data center HVAC for #{zone.name}.")

      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      if system_name.nil?
        air_loop.setName("#{zone.name} PSZ-AC Data Center")
      else
        air_loop.setName("#{zone.name} #{system_name}")
      end

      air_loop.setAvailabilitySchedule(hvac_op_sch)
      air_loop.setNightCycleControlType('CycleOnAny')

      # adjust system sizing for a constant volume system with no VAV terminals
      air_loop_sizing = air_loop.sizingSystem
      air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
      air_loop_sizing.autosizeDesignOutdoorAirFlowRate
      air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
      air_loop_sizing.setPreheatDesignTemperature(7.0)
      air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
      air_loop_sizing.setPrecoolDesignTemperature(12.8)
      air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
      air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(12.8)
      air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(40.0)
      air_loop_sizing.setSizingOption('Coincident')
      air_loop_sizing.setAllOutdoorAirinCooling(false)
      air_loop_sizing.setAllOutdoorAirinHeating(false)
      air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
      air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
      air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(12.8)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(40.0)

      # add the components to the air loop in order from closest to zone to furthest from zone
      if main_data_center

        # control temps used across all air handlers
        hw_temp_f = 180.0 # HW setpoint 180F
        hw_delta_t_r = 20.0 # 20F delta-T
        prehtg_sa_temp_f = 44.6 # Preheat to 44.6F
        htg_sa_temp_f = 55.0 # Central deck htg temp 55F
        hw_temp_c = OpenStudio.convert(hw_temp_f, 'F', 'C').get
        hw_delta_t_k = OpenStudio.convert(hw_delta_t_r, 'R', 'K').get
        prehtg_sa_temp_c = OpenStudio.convert(prehtg_sa_temp_f, 'F', 'C').get
        htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get
        extra_water_htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{air_loop.name} Water Htg Coil",
                                                         rated_inlet_water_temperature: hw_temp_c,
                                                         rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k),
                                                         rated_inlet_air_temperature: prehtg_sa_temp_c,
                                                         rated_outlet_air_temperature: htg_sa_temp_c)
        extra_water_htg_coil.addToNode(air_loop.supplyInletNode)
        extra_elec_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Htg Coil")
        extra_elec_htg_coil.addToNode(air_loop.supplyInletNode)

        # humidity controllers
        humidifier = OpenStudio::Model::HumidifierSteamElectric.new(model)
        humidifier.setRatedCapacity(3.72E-5)
        humidifier.setRatedPower(100_000)
        humidifier.setName("#{air_loop.name} Electric Steam Humidifier")
        humidifier.addToNode(air_loop.supplyInletNode)
        humidity_spm = OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum.new(model)
        humidity_spm.setControlZone(zone)
        humidity_spm.addToNode(humidifier.outletModelObject.get.to_Node.get)
        humidistat = OpenStudio::Model::ZoneControlHumidistat.new(model)
        humidistat.setHumidifyingRelativeHumiditySetpointSchedule(model_add_schedule(model, 'OfficeLarge DC_MinRelHumSetSch'))
        zone.setZoneControlHumidistat(humidistat)
      end

      # create fan
      # @type [OpenStudio::Model::FanConstantVolume]
      fan = create_fan_by_name(model, 'Packaged_RTU_SZ_AC_Cycling_Fan', fan_name:"#{air_loop.name} Fan")
      fan.setAvailabilitySchedule(hvac_op_sch)

      # create heating and cooling coils
      htg_coil = create_coil_heating_water_to_air_heat_pump_equation_fit(model, heat_pump_loop, name: "#{air_loop.name} Water-to-Air HP Htg Coil")
      clg_coil = create_coil_cooling_water_to_air_heat_pump_equation_fit(model, heat_pump_loop, name: "#{air_loop.name} Water-to-Air HP Clg Coil")
      supplemental_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Electric Backup Htg Coil")

      # wrap fan and coils in a unitary system object
      unitary_system = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      unitary_system.setName("#{zone.name} Unitary HP")
      unitary_system.setSupplyFan(fan)
      unitary_system.setHeatingCoil(htg_coil)
      unitary_system.setCoolingCoil(clg_coil)
      unitary_system.setSupplementalHeatingCoil(supplemental_htg_coil)
      unitary_system.setControllingZoneorThermostatLocation(zone)
      unitary_system.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(OpenStudio.convert(40.0, 'F', 'C').get)
      unitary_system.setFanPlacement('BlowThrough')
      unitary_system.setSupplyAirFanOperatingModeSchedule(hvac_op_sch)
      unitary_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOnDiscreteSchedule)
      unitary_system.addToNode(air_loop.supplyInletNode)

      # create outdoor air system
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.setName("#{air_loop.name} OA System Controller")
      oa_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)
      oa_controller.autosizeMinimumOutdoorAirFlowRate
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
      oa_system.setName("#{air_loop.name} OA System")
      oa_system.addToNode(air_loop.supplyInletNode)

      # add a setpoint manager single zone reheat to control the supply air temperature
      setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
      setpoint_mgr_single_zone_reheat.setControlZone(zone)
      setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(OpenStudio.convert(55.0, 'F', 'C').get)
      setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(OpenStudio.convert(104.0, 'F', 'C').get)
      setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

      # create a diffuser and attach the zone/diffuser pair to the air loop
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName("#{air_loop.name} Diffuser")
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      air_loops << air_loop
    end

    return air_loops
  end

  # Creates a split DX AC system for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC, Single Speed Heat Pump
  # @param heating_type [Double] valid choices are Gas, Single Speed Heat Pump
  # @param supplemental_heating_type [Double] valid choices are Electric, Gas
  # @param fan_type [Double] valid choices are ConstantVolume, Cycling
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param oa_damper_sch [Double] name of the oa damper schedule, or nil in which case will be defaulted to always open
  # @param econ_max_oa_frac_sch [Double] name of the economizer maximum outdoor air fraction schedule
  # @return [OpenStudio::Model::AirLoopHVAC] the resulting split AC air loop
  def model_add_split_ac(model,
                         thermal_zones,
                         cooling_type: "Two Speed DX AC",
                         heating_type: "Single Speed Heat Pump",
                         supplemental_heating_type: "Gas",
                         fan_type: "Cycling",
                         hvac_op_sch: nil,
                         oa_damper_sch: nil,
                         econ_max_oa_frac_sch: nil)

    # hvac operation schedule
    if hvac_op_sch.nil?
      hvac_op_sch = model.alwaysOnDiscreteSchedule
    else
      hvac_op_sch = model_add_schedule(model, hvac_op_sch)
    end

    # oa damper schedule
    if oa_damper_sch.nil?
      oa_damper_sch = model.alwaysOnDiscreteSchedule
    else
      oa_damper_sch = model_add_schedule(model, oa_damper_sch)
    end

    # create a split AC for each group of thermal zones
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setAvailabilitySchedule(hvac_op_sch)
    air_loop.setName("#{thermal_zones.size} zone SAC")

    # adjust system sizing for a constant volume system with no VAV terminals
    air_loop_sizing = air_loop.sizingSystem
    air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
    air_loop_sizing.setPreheatDesignTemperature(7.0)
    air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
    air_loop_sizing.setPrecoolDesignTemperature(11.0)
    air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(12.0)
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(50.0)
    air_loop_sizing.setSizingOption('NonCoincident')
    air_loop_sizing.setAllOutdoorAirinCooling(false)
    air_loop_sizing.setAllOutdoorAirinHeating(false)
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.008)
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
    air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
    air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

    # add the components to the air loop in order from closest to zone to furthest from zone
    # create fan
    fan = nil
    if fan_type == 'ConstantVolume'
      fan = create_fan_by_name(model,
                               'Split_AC_CAV_Fan',
                               fan_name:"#{air_loop.name.to_s} SAC Fan",
                               end_use_subcategory:'CAV system Fans')
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    elsif fan_type == 'Cycling'
      fan = create_fan_by_name(model,
                               'Split_AC_Cycling_Fan',
                               fan_name:"#{air_loop.name.to_s} SAC Fan",
                               end_use_subcategory:'CAV system Fans')
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "fan_type #{fan_type} invalid for split AC system.")
    end
    fan.addToNode(air_loop.supplyInletNode) if !fan.nil?

    # create supplemental heating coil
    supplemental_htg_coil = nil
    if supplemental_heating_type == 'Electric'
      supplemental_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} PSZ-AC Electric Backup Htg Coil")
    elsif supplemental_heating_type == 'Gas'
      supplemental_htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} PSZ-AC Gas Backup Htg Coil")
    end
    supplemental_htg_coil.addToNode(air_loop.supplyInletNode) if !supplemental_htg_coil.nil?

    # create heating coil
    htg_coil = nil
    if heating_type == 'Gas'
      htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} SAC Gas Htg Coil")
      htg_part_load_fraction_correlation = OpenStudio::Model::CurveCubic.new(model)
      htg_part_load_fraction_correlation.setCoefficient1Constant(0.8)
      htg_part_load_fraction_correlation.setCoefficient2x(0.2)
      htg_part_load_fraction_correlation.setCoefficient3xPOW2(0.0)
      htg_part_load_fraction_correlation.setCoefficient4xPOW3(0.0)
      htg_part_load_fraction_correlation.setMinimumValueofx(0.0)
      htg_part_load_fraction_correlation.setMaximumValueofx(1.0)
      htg_coil.setPartLoadFractionCorrelationCurve(htg_part_load_fraction_correlation)
    elsif heating_type == 'Single Speed Heat Pump'
      htg_coil = create_coil_heating_dx_single_speed(model, name: "#{air_loop.name.to_s} SAC HP Htg Coil")
    end
    htg_coil.addToNode(air_loop.supplyInletNode) if !htg_coil.nil?

    # create cooling coil
    clg_coil = nil
    if cooling_type == 'Two Speed DX AC'
      clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{air_loop.name.to_s} SAC 2spd DX AC Clg Coil")
    elsif cooling_type == 'Single Speed DX AC'
      clg_coil = create_coil_cooling_dx_single_speed(model, name:"#{air_loop.name.to_s} SAC 1spd DX AC Clg Coil", type:'Split AC')
    elsif cooling_type == 'Single Speed Heat Pump'
      clg_coil = create_coil_cooling_dx_single_speed(model, name:"#{air_loop.name.to_s} SAC 1spd DX HP Clg Coil", type:'Heat Pump')
    end
    clg_coil.addToNode(air_loop.supplyInletNode) if !clg_coil.nil?

    # create outdoor air controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.setName("#{air_loop.name.to_s} SAC OA System Controller")
    oa_controller.setMinimumOutdoorAirSchedule(oa_damper_sch)
    oa_controller.autosizeMinimumOutdoorAirFlowRate
    oa_controller.setMaximumFractionofOutdoorAirSchedule(model_add_schedule(model, econ_max_oa_frac_sch)) if !econ_max_oa_frac_sch.nil?
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
    oa_system.setName("#{air_loop.name.to_s} SAC OA System")
    oa_system.addToNode(air_loop.supplyInletNode)

    # add a setpoint manager single zone reheat to control the supply air temperature
    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setName("#{air_loop.name.to_s} SAC Setpoint Manager SZ Reheat")
    controlzone = thermal_zones[0]
    setpoint_mgr_single_zone_reheat.setControlZone(controlzone)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(OpenStudio.convert(55.4, 'F', 'C').get)
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(OpenStudio.convert(113.0, 'F', 'C').get)
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    # create a diffuser and attach the zone/diffuser pair to the air loop
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding #{zone.name.to_s} to split DX AC system.")

      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName("#{zone.name} SAC Diffuser")
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(50.0)
      sizing_zone.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
      sizing_zone.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)
    end

    return air_loop
  end

  # Creates a PTAC system for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC
  # @param heating_type [Double] valid choices are NaturalGas, Electricity, Water, nil (no heat)
  # @param hot_water_loop [String] hot water loop to connect heating coil to. Set to nil for heating types besides water
  # @param fan_type [Double] valid choices are ConstantVolume, Cycling
  # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] an array of the resulting PTACs
  def model_add_ptac(model,
                     thermal_zones,
                     cooling_type: "Two Speed DX AC",
                     heating_type: "Gas",
                     hot_water_loop: nil,
                     fan_type: "ConstantVolume")

    # make a PTAC for each zone
    ptacs = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding PTAC for #{zone.name}.")

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(50.0)
      sizing_zone.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
      sizing_zone.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)

      # add fan
      if fan_type == 'ConstantVolume'
        fan = create_fan_by_name(model, 'PTAC_CAV_Fan', fan_name:"#{zone.name} PTAC Fan")
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      elsif fan_type == 'Cycling'
        fan = create_fan_by_name(model, 'PTAC_Cycling_Fan', fan_name:"#{zone.name} PTAC Fan")
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "ptac_fan_type of #{fan_type} is not recognized.")
      end

      # add heating coil
      case heating_type
      when 'NaturalGas', 'Gas'
        htg_coil = create_coil_heating_gas(model, name: "#{zone.name.to_s} PTAC Gas Htg Coil")
      when 'Electricity', 'Electric'
        htg_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} PTAC Electric Htg Coil")
      when nil
        htg_coil = create_coil_heating_electric(model,
                                                name: "#{zone.name.to_s} PTAC No Heat",
                                                schedule: model.alwaysOffDiscreteSchedule,
                                                nominal_capacity: 0)
      when 'Water'
        if hot_water_loop.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'No hot water plant loop supplied')
          return false
        end
        hw_sizing = hot_water_loop.sizingPlant
        hw_temp_c = hw_sizing.designLoopExitTemperature
        hw_delta_t_k = hw_sizing.loopDesignTemperatureDifference
        htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{hot_water_loop.name} Water Htg Coil",
                                             rated_inlet_water_temperature: hw_temp_c,
                                             rated_outlet_water_temperature: (hw_temp_c - hw_delta_t_k))
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "ptac_heating_type of #{heating_type} is not recognized.")
      end

      # add cooling coil
      if cooling_type == 'Two Speed DX AC'
        clg_coil = create_coil_cooling_dx_two_speed(model, name:"#{zone.name.to_s} PTAC 2spd DX AC Clg Coil")
      elsif cooling_type == 'Single Speed DX AC'
        clg_coil = create_coil_cooling_dx_single_speed(model, name:"#{zone.name} PTAC 1spd DX AC Clg Coil", type:'PTAC')
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "ptac_cooling_type of #{cooling_type} is not recognized.")
      end

      # wrap coils in a PTAC system
      ptac_system = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                                  model.alwaysOnDiscreteSchedule,
                                                                                  fan,
                                                                                  htg_coil,
                                                                                  clg_coil)
      ptac_system.setName("#{zone.name} PTAC")
      ptac_system.setFanPlacement('DrawThrough')
      if fan_type == 'ConstantVolume'
        ptac_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOnDiscreteSchedule)
      elsif fan_type == 'Cycling'
        ptac_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)
      end
      ptac_system.addToThermalZone(zone)
      ptacs << ptac_system
    end

    return ptacs
  end

  # Creates a PTHP system for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param fan_type [String] valid choices are ConstantVolume, Cycling
  # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] an array of the resulting PTACs.
  def model_add_pthp(model,
                     thermal_zones,
                     fan_type: "Cycling")
    # make a PTHP for each zone
    pthps = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding PTHP for #{zone.name.to_s}.")

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(50.0)
      sizing_zone.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
      sizing_zone.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)

      # add fan
      if fan_type == 'ConstantVolume'
        fan = create_fan_by_name(model, 'PTAC_CAV_Fan', fan_name:"#{zone.name} PTAC Fan")
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      elsif fan_type == 'Cycling'
        fan = create_fan_by_name(model, 'PTAC_Cycling_Fan', fan_name:"#{zone.name} PTAC Fan")
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "PTHP fan_type of #{fan_type} is not recognized.")
        return false
      end

      # add heating coil
      htg_coil = create_coil_heating_dx_single_speed(model, name: "#{zone.name} PTHP Htg Coil")
      # add cooling coil
      clg_coil = create_coil_cooling_dx_single_speed(model, name:"#{zone.name} PTHP Clg Coil", type:'Heat Pump')
      # supplemental heating coil
      supplemental_htg_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} PTHP Supplemental Htg Coil")
      # wrap coils in a PTHP system
      pthp_system = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(model,
                                                                            model.alwaysOnDiscreteSchedule,
                                                                            fan,
                                                                            htg_coil,
                                                                            clg_coil,
                                                                            supplemental_htg_coil)
      pthp_system.setName("#{zone.name} PTHP")
      pthp_system.setFanPlacement('DrawThrough')
      if fan_type == 'ConstantVolume'
        pthp_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOnDiscreteSchedule)
      elsif fan_type == 'Cycling'
        pthp_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)
      end
      pthp_system.addToThermalZone(zone)
      pthps << pthp_system
    end

    return pthps
  end

  # Creates a unit heater for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param hvac_op_sch [String] name of the HVAC operation schedule or nil in which case will be defaulted to always on
  # @param fan_control_type [Double] valid choices are OnOff, ConstantVolume, VariableVolume
  # @param fan_pressure_rise [Double] fan pressure rise, inH2O
  # @param heating_type [Double] valid choices are NaturalGas, Gas, Electricity, Electric, DistrictHeating
  # @param hot_water_loop [String] hot water loop to connect to the heating coil
  # @param rated_inlet_water_temperature [Double] rated inlet water temperature in degrees Fahrenheit, default is 180F
  # @param rated_outlet_water_temperature [Double] rated outlet water temperature in degrees Fahrenheit, default is 160F
  # @param rated_inlet_air_temperature [Double] rated inlet air temperature in degrees Fahrenheit, default is 60F
  # @param rated_outlet_air_temperature [Double] rated outlet air temperature in degrees Fahrenheit, default is 100F
  # @return [Array<OpenStudio::Model::ZoneHVACUnitHeater>] an array of the resulting unit heaters.
  def model_add_unitheater(model,
                           thermal_zones,
                           hvac_op_sch: nil,
                           fan_control_type: "ConstantVolume",
                           fan_pressure_rise: 0.2,
                           heating_type: nil,
                           hot_water_loop: nil,
                           rated_inlet_water_temperature: 180.0,
                           rated_outlet_water_temperature: 160.0,
                           rated_inlet_air_temperature: 60.0,
                           rated_outlet_air_temperature: 100.0)

    # hvac operation schedule
    if hvac_op_sch.nil?
      hvac_op_sch = model.alwaysOnDiscreteSchedule
    else
      hvac_op_sch = model_add_schedule(model, hvac_op_sch)
    end

    # set defaults if nil
    fan_control_type = "ConstantVolume" if fan_control_type.nil?
    fan_pressure_rise = 0.2 if fan_pressure_rise.nil?

    # make a unit heater for each zone
    unit_heaters = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding unit heater for #{zone.name}.")

      # zone sizing
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(14.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(50.0)
      sizing_zone.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
      sizing_zone.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)

      # add fan
      fan = create_fan_by_name(model,
                               'Unit_Heater_Fan',
                               fan_name:"#{zone.name} UnitHeater Fan",
                               pressure_rise: fan_pressure_rise)
      fan.setAvailabilitySchedule(hvac_op_sch)

      # add heating coil
      if heating_type == 'NaturalGas' || heating_type == 'Gas'
        htg_coil = create_coil_heating_gas(model, name: "#{zone.name} UnitHeater Gas Htg Coil", schedule: hvac_op_sch)
      elsif heating_type == 'Electricity' || heating_type == 'Electric'
        htg_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} UnitHeater Electric Htg Coil", schedule: hvac_op_sch)
      elsif heating_type == 'DistrictHeating' && !hot_water_loop.nil?
        # control temperature for hot water loop
        if rated_inlet_water_temperature.nil?
          rated_inlet_water_temperature_c = OpenStudio.convert(180.0, 'F', 'C').get
        else
          rated_inlet_water_temperature_c = OpenStudio.convert(rated_inlet_water_temperature, 'F', 'C').get
        end
        if rated_outlet_water_temperature.nil?
          rated_outlet_water_temperature_c = OpenStudio.convert(160.0, 'F', 'C').get
        else
          rated_outlet_water_temperature_c = OpenStudio.convert(rated_outlet_water_temperature, 'F', 'C').get
        end
        if rated_inlet_air_temperature.nil?
          rated_inlet_air_temperature_c = OpenStudio.convert(60.0, 'F', 'C').get
        else
          rated_inlet_air_temperature_c = OpenStudio.convert(rated_inlet_air_temperature, 'F', 'C').get
        end
        if rated_outlet_air_temperature.nil?
          rated_outlet_air_temperature_c = OpenStudio.convert(100.0, 'F', 'C').get
        else
          rated_outlet_air_temperature_c = OpenStudio.convert(rated_outlet_air_temperature, 'F', 'C').get
        end
        htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{zone.name} UnitHeater Water Htg Coil",
                                             rated_inlet_water_temperature: rated_inlet_water_temperature_c,
                                             rated_outlet_water_temperature: rated_outlet_water_temperature_c,
                                             rated_inlet_air_temperature: rated_inlet_air_temperature_c,
                                             rated_outlet_air_temperature: rated_outlet_air_temperature_c)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', 'No heating type was found when adding unit heater; no unit heater will be created.')
        return false
      end

      # create unit heater
      unit_heater = OpenStudio::Model::ZoneHVACUnitHeater.new(model, hvac_op_sch, fan, htg_coil)
      unit_heater.setName("#{zone.name} UnitHeater")
      unit_heater.setFanControlType(fan_control_type)
      unit_heater.addToThermalZone(zone)
      unit_heaters << unit_heater
    end

    return unit_heaters
  end

  # Creates a high temp radiant heater for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @param heating_type [Double] valid choices are Gas, Electric
  # @param combustion_efficiency [Double] combustion efficiency as decimal
  # @return [Array<OpenStudio::Model::ZoneHVACHighTemperatureRadiant>] an
  # array of the resulting radiant heaters.
  def model_add_high_temp_radiant(model,
                                  thermal_zones,
                                  heating_type: "Gas",
                                  combustion_efficiency: 0.8)

    # Make a high temp radiant heater for each zone
    radiant_heaters = []
    thermal_zones.each do |zone|
      high_temp_radiant = OpenStudio::Model::ZoneHVACHighTemperatureRadiant.new(model)
      high_temp_radiant.setName("#{zone.name} High Temp Radiant")

      if heating_type.nil?
        high_temp_radiant.setFuelType("Gas")
      else
        high_temp_radiant.setFuelType(heating_type)
      end

      if combustion_efficiency.nil?
        if heating_type == "Gas"
          high_temp_radiant.setCombustionEfficiency(0.8)
        elsif heating_type == "Electric"
          high_temp_radiant.setCombustionEfficiency(1.0)
        end
      else
        high_temp_radiant.setCombustionEfficiency(combustion_efficiency)
      end

      # set defaults
      high_temp_radiant.setTemperatureControlType(control_type)
      high_temp_radiant.setFractionofInputConvertedtoRadiantEnergy(0.8)
      high_temp_radiant.setHeatingThrottlingRange(2)
      high_temp_radiant.addToThermalZone(zone)
      radiant_heaters << high_temp_radiant
    end

    return radiant_heaters
  end

  # Creates an evaporative cooler for each zone and adds it to the model.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] the resulting evaporative coolers
  def model_add_evap_cooler(model,
                            thermal_zones)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding evaporative coolers for #{thermal_zones.size} zones.")
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Model.Model', "---#{zone.name}")
    end

    # Evap cooler control temperatures
    min_sa_temp_f = 55
    clg_sa_temp_f = 70
    max_sa_temp_f = 78
    htg_sa_temp_f = 122 # Not used

    min_sa_temp_c = OpenStudio.convert(min_sa_temp_f, 'F', 'C').get
    clg_sa_temp_c = OpenStudio.convert(clg_sa_temp_f, 'F', 'C').get
    max_sa_temp_c = OpenStudio.convert(max_sa_temp_f, 'F', 'C').get
    htg_sa_temp_c = OpenStudio.convert(htg_sa_temp_f, 'F', 'C').get

    approach_r = 3 # WetBulb approach
    approach_k = OpenStudio.convert(approach_r, 'R', 'K').get

    # EMS programs
    programs = []

    # Make an evap cooler for each zone
    evap_coolers = []
    thermal_zones.each do |zone|
      zone_name_clean = zone.name.get.delete(':')

      # Air loop
      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      air_loop.setName("#{zone_name_clean} Evap Cooler")

      # Schedule to control the airloop availability
      air_loop_avail_sch = OpenStudio::Model::ScheduleConstant.new(model)
      air_loop_avail_sch.setName("#{air_loop.name} Availability Sch")
      air_loop_avail_sch.setValue(1)
      air_loop.setAvailabilitySchedule(air_loop_avail_sch)

      # EMS to turn on Evap Cooler if there is a cooling load in the target zone.
      # Without this EMS, the airloop runs 24/7-365 even when there is no load in the zone.

      # Create a sensor to read the zone load
      zn_load_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Predicted Sensible Load to Cooling Setpoint Heat Transfer Rate')
      zn_load_sensor.setName("#{zone_name_clean} Clg Load Sensor")
      zn_load_sensor.setKeyName(zone.handle.to_s)

      # Create an actuator to set the airloop availability
      air_loop_avail_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(air_loop_avail_sch, 'Schedule:Constant', 'Schedule Value')
      air_loop_avail_actuator.setName("#{air_loop.name} Availability Actuator")

      # Create a program to turn on Evap Cooler if
      # there is a cooling load in the target zone.
      # Load < 0.0 is a cooling load.
      avail_program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      avail_program.setName("#{air_loop.name} Availability Control")
      avail_program_body = <<-EMS
        IF #{zn_load_sensor.handle} < 0.0
          SET #{air_loop_avail_actuator.handle} = 1
        ELSE
          SET #{air_loop_avail_actuator.handle} = 0
        ENDIF
      EMS
      avail_program.setBody(avail_program_body)

      programs << avail_program

      # Setpoint follows OAT WetBulb
      evap_stpt_manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(model)
      evap_stpt_manager.setName("#{approach_r} F above OATwb")
      evap_stpt_manager.setReferenceTemperatureType('OutdoorAirWetBulb')
      evap_stpt_manager.setMaximumSetpointTemperature(max_sa_temp_c)
      evap_stpt_manager.setMinimumSetpointTemperature(min_sa_temp_c)
      evap_stpt_manager.setOffsetTemperatureDifference(approach_k)
      evap_stpt_manager.addToNode(air_loop.supplyOutletNode)

      # Air handler sizing
      sizing_system = air_loop.sizingSystem
      sizing_system.setCentralCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      sizing_system.setCentralHeatingDesignSupplyAirTemperature(htg_sa_temp_c)
      sizing_system.setAllOutdoorAirinCooling(true)
      sizing_system.setAllOutdoorAirinHeating(true)
      sizing_system.setSystemOutdoorAirMethod('ZoneSum')

      # Direct Evap Cooler
      # TODO: better assumptions for evap cooler performance and fan pressure rise
      evap = OpenStudio::Model::EvaporativeCoolerDirectResearchSpecial.new(model, model.alwaysOnDiscreteSchedule)
      evap.setName("#{zone.name} Evap Media")
      evap.autosizePrimaryAirDesignFlowRate
      evap.addToNode(air_loop.supplyInletNode)

      # Fan (cycling), must be inside unitary system to cycle on airloop
      fan = create_fan_by_name(model, 'Evap_Cooler_Supply_Fan', fan_name:"#{zone.name} Evap Cooler Supply Fan")
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      # Dummy zero-capacity cooling coil
      clg_coil = create_coil_cooling_dx_single_speed(model,
                                                     name:"Dummy Always Off DX Coil",
                                                     schedule:alwaysOffDiscreteSchedule)
      unitary_system = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      unitary_system.setName("#{zone.name} Evap Cooler Cycling Fan")
      unitary_system.setSupplyFan(fan)
      unitary_system.setCoolingCoil(clg_coil)
      unitary_system.setControllingZoneorThermostatLocation(zone)
      unitary_system.setMaximumSupplyAirTemperature(50)
      unitary_system.setFanPlacement('BlowThrough')
      unitary_system.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
      unitary_system.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      unitary_system.setSupplyAirFlowRateMethodWhenNoCoolingorHeatingisRequired('SupplyAirFlowRate')
      unitary_system.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)
      unitary_system.addToNode(air_loop.supplyInletNode)

      # Outdoor air intake system
      oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_intake_controller.setName("#{air_loop.name} OA Controller")
      oa_intake_controller.setMinimumLimitType('FixedMinimum')
      oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
      oa_intake_controller.setMinimumFractionofOutdoorAirSchedule(model.alwaysOnDiscreteSchedule)

      controller_mv = oa_intake_controller.controllerMechanicalVentilation
      controller_mv.setName("#{air_loop.name} Vent Controller")
      controller_mv.setSystemOutdoorAirMethod('ZoneSum')

      oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
      oa_intake.setName("#{air_loop.name} OA Sys")
      oa_intake.addToNode(air_loop.supplyInletNode)

      # make an air terminal for the zone
      air_terminal = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      air_terminal.setName("#{zone.name} Air Terminal")

      # attach new terminal to the zone and to the airloop
      air_loop.addBranchForZone(zone, air_terminal.to_StraightComponent)

      sizing_zone = zone.sizingZone
      sizing_zone.setCoolingDesignAirFlowMethod('DesignDay')
      sizing_zone.setHeatingDesignAirFlowMethod('DesignDay')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(clg_sa_temp_c)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(htg_sa_temp_c)

      evap_coolers << air_loop
    end

    # Create a programcallingmanager
    avail_pcm = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    avail_pcm.setName('Evap Cooler Availability Program Calling Manager')
    avail_pcm.setCallingPoint('AfterPredictorAfterHVACManagers')
    programs.each do |program|
      avail_pcm.addProgram(program)
    end

    return evap_coolers
  end

  # Adds hydronic or electric baseboard heating to each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add baseboards to.
  # @param hot_water_loop [OpenStudio::Model::PlantLoop] The hot water loop that serves the baseboards.  If nil, baseboards are electric.
  # @return [Array<OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric, OpenStudio::Model::ZoneHVACBaseboardConvectiveWater>]
  #   array of baseboard heaters.
  def model_add_baseboard(model,
                          thermal_zones,
                          hot_water_loop: nil)

    # Make a baseboard heater for each zone
    baseboards = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding baseboard heat for #{zone.name}.")

      if hot_water_loop.nil?
        baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        baseboard.setName("#{zone.name} Electric Baseboard")
        baseboard.addToThermalZone(zone)
        baseboards << baseboard
      else
        htg_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
        htg_coil.setName("#{zone.name} Hydronic Baseboard Coil")
        hot_water_loop.addDemandBranchForComponent(htg_coil)
        baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model, model.alwaysOnDiscreteSchedule, htg_coil)
        baseboard.setName("#{zone.name} Hydronic Baseboard")
        baseboard.addToThermalZone(zone)
        baseboards << baseboard
      end
    end

    return baseboards
  end

  # Adds Variable Refrigerant Flow system and terminal units for each zone
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units
  # @return [Array<OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow>] array of vrf units.
  def model_add_vrf(model,
                    thermal_zones)

    # create vrf outdoor unit
    master_zone = thermal_zones[0]
    vrf_outdoor_unit = create_air_conditioner_variable_refrigerant_flow(model,
                                                                        name: "VRF System",
                                                                        master_zone: master_zone)
    vrfs = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding vrf unit for #{zone.name}.")

      # add vrf terminal unit
      vrf_terminal_unit = OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow.new(model)
      vrf_terminal_unit.setName("#{zone.name.to_s} VRF Terminal Unit")
      vrf_terminal_unit.addToThermalZone(zone)
      vrf_terminal_unit.setTerminalUnitAvailabilityschedule(model.alwaysOnDiscreteSchedule)

      # no outdoor air assumed
      vrf_terminal_unit.setOutdoorAirFlowRateDuringCoolingOperation(0)
      vrf_terminal_unit.setOutdoorAirFlowRateDuringHeatingOperation(0)
      vrf_terminal_unit.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(0)

      # set fan variables
      # always off denotes cycling fan
      vrf_terminal_unit.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)
      vrf_fan = vrf_terminal_unit.supplyAirFan.to_FanOnOff.get
      vrf_fan.setPressureRise(300)
      vrf_fan.setMotorEfficiency(0.8)
      vrf_fan.setFanEfficiency(0.6)
      vrf_fan.setName("#{zone.name.to_s} VRF Unit Cycling Fan")

      # add to main condensing unit
      vrf_outdoor_unit.addTerminal(vrf_terminal_unit)
    end

    return vrfs
  end

  # Adds four pipe fan coil units to each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units
  # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop that serves the fan coils.
  # @param hot_water_loop [OpenStudio::Model::PlantLoop] the hot water loop that serves the fan coils.
  #   If nil, a zero-capacity, electric heating coil set to Always-Off will be included in the unit.
  # @param ventilation [Bool] If true, ventilation will be supplied through the unit.  If false,
  #   no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
  # @return [Array<OpenStudio::Model::ZoneHVACFourPipeFanCoil>] array of fan coil units.
  def model_add_four_pipe_fan_coil(model,
                                   thermal_zones,
                                   chilled_water_loop,
                                   hot_water_loop: nil,
                                   ventilation: false)

    # supply temps used across all zones
    zn_dsn_clg_sa_temp_f = 55
    zn_dsn_htg_sa_temp_f = 104
    zn_dsn_clg_sa_temp_c = OpenStudio.convert(zn_dsn_clg_sa_temp_f, 'F', 'C').get
    zn_dsn_htg_sa_temp_c = OpenStudio.convert(zn_dsn_htg_sa_temp_f, 'F', 'C').get

    # make a fan coil unit for each zone
    fcus = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding fan coil for #{zone.name}.")
      zone_sizing = zone.sizingZone
      zone_sizing.setZoneCoolingDesignSupplyAirTemperature(zn_dsn_clg_sa_temp_c)
      zone_sizing.setZoneHeatingDesignSupplyAirTemperature(zn_dsn_htg_sa_temp_c)

      if chilled_water_loop
        fcu_clg_coil = create_coil_cooling_water(model, chilled_water_loop, name: "#{zone.name} FCU Cooling Coil")
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', 'Fan coil units require a chilled water loop, but none was provided.')
        return false
      end

      if hot_water_loop
        fcu_htg_coil = create_coil_heating_water(model, hot_water_loop, name: "#{zone.name} FCU Heating Coil")
      else
        # Zero-capacity, always-off electric heating coil
        fcu_htg_coil = create_coil_heating_electric(model,
                                                    name: "#{zone.name.to_s} No Heat",
                                                    schedule: model.alwaysOffDiscreteSchedule,
                                                    nominal_capacity: 0.0)
      end

      fcu_fan = create_fan_by_name(model, 'Fan_Coil_Fan',
                                   fan_name:"#{zone.name.to_s} Fan Coil fan",
                                   end_use_subcategory:'FCU Fans')
      fcu_fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      fcu_fan.autosizeMaximumFlowRate

      fcu = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model,
                                                           model.alwaysOnDiscreteSchedule,
                                                           fcu_fan,
                                                           fcu_clg_coil,
                                                           fcu_htg_coil)
      fcu.setName("#{zone.name} FCU")
      fcu.setCapacityControlMethod('CyclingFan')
      fcu.autosizeMaximumSupplyAirFlowRate
      unless ventilation
        fcu.setMaximumOutdoorAirFlowRate(0.0)
      end
      fcu.addToThermalZone(zone)
      fcus << fcu
    end

    return fcus
  end

  # Adds a window air conditioner to each zone.
  # Code adapted from: https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACRoomAirConditioner/measure.rb
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
  # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] and array of PTACs used as window AC units
  def model_add_window_ac(model,
                          thermal_zones)

    # Defaults
    eer = 8.5 # Btu/W-h
    cop = OpenStudio.convert(eer, 'Btu/h', 'W').get
    shr = 0.65 # The sensible heat ratio (ratio of the sensible portion of the load to the total load) at the nominal rated capacity
    airflow_cfm_per_ton = 350.0 # cfm/ton

    acs = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding window AC for #{zone.name}.")

      clg_coil = create_coil_cooling_dx_single_speed(model,
                                                     name:"#{zone.name.to_s} Window AC Cooling Coil",
                                                     type:'Window AC',
                                                     cop: cop)
      clg_coil.setRatedSensibleHeatRatio(shr)
      clg_coil.setRatedEvaporatorFanPowerPerVolumeFlowRate(OpenStudio::OptionalDouble.new(773.3))
      clg_coil.setEvaporativeCondenserEffectiveness(OpenStudio::OptionalDouble.new(0.9))
      clg_coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(OpenStudio::OptionalDouble.new(10))
      clg_coil.setBasinHeaterSetpointTemperature(OpenStudio::OptionalDouble.new(2))

      fan = create_fan_by_name(model,
                               'Window_AC_Supply_Fan',
                               fan_name:"#{zone.name.to_s} Window AC Supply Fan",
                               end_use_subcategory:'DOAS Fans')
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      htg_coil = create_coil_heating_electric(model,
                                              name: "#{zone.name.to_s} Window AC Always Off Htg Coil",
                                              schedule: model.alwaysOffDiscreteSchedule,
                                              nominal_capacity: 0)
      ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model, model.alwaysOnDiscreteSchedule, fan, htg_coil, clg_coil)
      ptac.setName("#{zone.name.to_s} Window AC")
      ptac.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)
      ptac.addToThermalZone(zone)
      acs << ptac
    end

    return acs
  end

  # Adds a forced air furnace or central AC to each zone.
  # Default is a forced air furnace without outdoor air
  # Code adapted from:
  # https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACFurnaceFuel/measure.rb
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
  # @param heating [Bool] if true, the unit will include a NaturalGas heating coil
  # @param cooling [Bool] if true, the unit will include a DX cooling coil
  # @param ventilation [Bool] if true, the unit will include an OA intake
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] and array of air loops representing the furnaces
  def model_add_furnace_central_ac(model,
                                   thermal_zones,
                                   heating: true,
                                   cooling: false,
                                   ventilation: false)

    if heating && cooling
      equip_name = 'Central Heating and AC'
    elsif heating && !cooling
      equip_name = 'Furnace'
    elsif cooling && !heating
      equip_name = 'Central AC'
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'Heating and cooling both disabled, not a valid Furnace or Central AC selection, no equipment was added.')
      return false
    end

    # defaults
    afue = 0.78
    seer = 13.0
    eer = 11.1
    shr = 0.73
    ac_w_per_cfm = 0.365
    sat_htg_f = 120.0
    sat_clg_f = 55.0
    crank_case_heat_w = 0.0
    crank_case_max_temp_f = 55.0

    furnaces = []
    thermal_zones.each do |zone|
      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      air_loop.setName("#{zone.name} #{equip_name}")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding furnace AC for #{zone.name}.")

      # create heating coil
      htg_coil = nil
      if heating
        htg_coil = create_coil_heating_gas(model, name: "#{air_loop.name.to_s} Heating Coil",
                                           efficiency: afue_to_thermal_eff(afue))
      end

      # create cooling coil
      clg_coil = nil
      if cooling
        clg_coil = create_coil_cooling_dx_single_speed(model, name: "#{air_loop.name.to_s} Cooling Coil",
                                                       type:'Residential Central AC')
        clg_coil.setRatedSensibleHeatRatio(shr)
        clg_coil.setRatedCOP(OpenStudio::OptionalDouble.new(eer_to_cop(eer)))
        clg_coil.setRatedEvaporatorFanPowerPerVolumeFlowRate(OpenStudio::OptionalDouble.new(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get))
        clg_coil.setNominalTimeForCondensateRemovalToBegin(OpenStudio::OptionalDouble.new(1000.0))
        clg_coil.setRatioOfInitialMoistureEvaporationRateAndSteadyStateLatentCapacity(OpenStudio::OptionalDouble.new(1.5))
        clg_coil.setMaximumCyclingRate(OpenStudio::OptionalDouble.new(3.0))
        clg_coil.setLatentCapacityTimeConstant(OpenStudio::OptionalDouble.new(45.0))
        clg_coil.setCondenserType('AirCooled')
        clg_coil.setCrankcaseHeaterCapacity(OpenStudio::OptionalDouble.new(crank_case_heat_w))
        clg_coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(OpenStudio::OptionalDouble.new(OpenStudio.convert(crank_case_max_temp_f, 'F', 'C').get))
      end

      # create fan
      fan = create_fan_by_name(model,
                               'Residential_HVAC_Fan',
                               fan_name:"#{air_loop.name.to_s} supply fan",
                               end_use_subcategory:'residential hvac fan')
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      if ventilation
        # create outdoor air intake
        oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
        oa_intake_controller.setName("#{air_loop.name.to_s} OA Controller")
        oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
        oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
        oa_intake.setName("#{air_loop.name.to_s} OA System")
        oa_intake.addToNode(air_loop.supplyInletNode)
      end

      # create unitary system (holds the coils and fan)
      unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      unitary.setName("#{air_loop.name.to_s} unitary system")
      unitary.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      unitary.setMaximumSupplyAirTemperature(OpenStudio.convert(120.0, 'F', 'C').get)
      unitary.setControllingZoneorThermostatLocation(zone)
      unitary.addToNode(air_loop.supplyInletNode)

      # set flow rates during different conditions
      unitary.setSupplyAirFlowRateDuringHeatingOperation(0.0) unless heating
      unitary.setSupplyAirFlowRateDuringCoolingOperation(0.0) unless cooling
      unitary.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(0.0) unless ventilation

      # attach the coils and fan
      unitary.setHeatingCoil(htg_coil) if htg_coil
      unitary.setCoolingCoil(clg_coil) if clg_coil
      unitary.setSupplyFan(fan)
      unitary.setFanPlacement('BlowThrough')
      unitary.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)

      # create a diffuser
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName(" #{zone.name} direct air")
      air_loop.addBranchForZone(zone, diffuser)

      furnaces << air_loop
    end

    return furnaces
  end

  # Adds an air source heat pump to each zone.
  # Code adapted from:
  # https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACAirSourceHeatPumpSingleSpeed/measure.rb
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
  # @param heating [Bool] if true, the unit will include a NaturalGas heating coil
  # @param cooling [Bool] if true, the unit will include a DX cooling coil
  # @param ventilation [Bool] if true, the unit will include an OA intake
  # @return [Array<OpenStudio::Model::AirLoopHVAC>] and array of air loops representing the heat pumps
  def model_add_central_air_source_heat_pump(model,
                                             thermal_zones,
                                             heating: true,
                                             cooling: true,
                                             ventilation: false)
    # defaults
    hspf = 7.7
    seer = 13
    eer = 11.4
    cop = 3.05
    shr = 0.73
    ac_w_per_cfm = 0.365
    min_hp_oat_f = 0
    sat_htg_f = 120
    sat_clg_f = 55
    crank_case_heat_w = 0
    crank_case_max_temp_f = 55

    hps = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding Central Air Source HP for #{zone.name}.")

      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      air_loop.setName("#{zone.name} Central Air Source HP")

      # create heating coil
      htg_coil = nil
      supplemental_htg_coil = nil
      if heating
        htg_coil = create_coil_heating_dx_single_speed(model, name: "#{air_loop.name.to_s} heating coil",
                                                       type: 'Residential Central Air Source HP',
                                                       cop: hspf_to_cop_heating_no_fan(hspf))
        htg_coil.setRatedSupplyFanPowerPerVolumeFlowRate(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get)
        htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(OpenStudio.convert(min_hp_oat_f, 'F', 'C').get)
        htg_coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(OpenStudio.convert(40.0, 'F', 'C').get)
        htg_coil.setCrankcaseHeaterCapacity(crank_case_heat_w)
        htg_coil.setMaximumOutdoorDryBulbTemperatureforCrankcaseHeaterOperation(OpenStudio.convert(crank_case_max_temp_f, 'F', 'C').get)
        htg_coil.setDefrostStrategy('ReverseCycle')
        htg_coil.setDefrostControl('OnDemand')

        # create supplemental heating coil
        supplemental_htg_coil = create_coil_heating_electric(model, name: "#{air_loop.name.to_s} Supplemental Htg Coil")
      end

      # create cooling coil
      clg_coil = nil
      if cooling
        clg_coil = create_coil_cooling_dx_single_speed(model,
                                                       name:"#{air_loop.name.to_s} cooling coil",
                                                       type:'Residential Central ASHP',
                                                       cop: cop)
        clg_coil.setRatedSensibleHeatRatio(shr)
        clg_coil.setRatedEvaporatorFanPowerPerVolumeFlowRate(OpenStudio::OptionalDouble.new(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get))
        clg_coil.setNominalTimeForCondensateRemovalToBegin(OpenStudio::OptionalDouble.new(1000.0))
        clg_coil.setRatioOfInitialMoistureEvaporationRateAndSteadyStateLatentCapacity(OpenStudio::OptionalDouble.new(1.5))
        clg_coil.setMaximumCyclingRate(OpenStudio::OptionalDouble.new(3.0))
        clg_coil.setLatentCapacityTimeConstant(OpenStudio::OptionalDouble.new(45.0))
        clg_coil.setCondenserType('AirCooled')
        clg_coil.setCrankcaseHeaterCapacity(OpenStudio::OptionalDouble.new(crank_case_heat_w))
        clg_coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(OpenStudio::OptionalDouble.new(OpenStudio.convert(crank_case_max_temp_f, 'F', 'C').get))
      end

      # create fan
      fan = create_fan_by_name(model, 'Residential_HVAC_Fan', fan_name:"#{air_loop.name.to_s} supply fan",
                               end_use_subcategory:'residential hvac fan')
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      # create outdoor air intake
      if ventilation
        oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
        oa_intake_controller.setName("#{air_loop.name} OA Controller")
        oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
        oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
        oa_intake.setName("#{air_loop.name} OA System")
        oa_intake.addToNode(air_loop.supplyInletNode)
      end

      # create unitary system (holds the coils and fan)
      unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
      unitary.setName("#{air_loop.name.to_s} zone unitary system")
      unitary.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
      unitary.setMaximumSupplyAirTemperature(OpenStudio.convert(170.0, 'F', 'C').get) # higher temp for supplemental heat as to not severely limit its use, resulting in unmet hours.
      unitary.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(OpenStudio.convert(40.0, 'F', 'C').get)
      unitary.setControllingZoneorThermostatLocation(zone)
      unitary.addToNode(air_loop.supplyInletNode)

      # set flow rates during different conditions
      unitary.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(0.0) unless ventilation

      # attach the coils and fan
      unitary.setHeatingCoil(htg_coil) if htg_coil
      unitary.setCoolingCoil(clg_coil) if clg_coil
      unitary.setSupplementalHeatingCoil(supplemental_htg_coil) if supplemental_htg_coil
      unitary.setSupplyFan(fan)
      unitary.setFanPlacement('BlowThrough')
      unitary.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)

      # create a diffuser
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
      diffuser.setName(" #{zone.name} direct air")
      air_loop.addBranchForZone(zone, diffuser)

      hps << air_loop
    end

    return hps
  end

  # Adds zone level water-to-air heat pumps for each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones served by heat pumps
  # @param condenser_loop [OpenStudio::Model::PlantLoop] the condenser loop for the heat pumps  #
  # @param ventilation [Bool] if true, ventilation will be supplied through the unit.
  #   If false, no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
  # @return [Array<OpenStudio::Model::ZoneHVACWaterToAirHeatPump>] an array of heat pumps
  def model_add_water_source_hp(model,
                                thermal_zones,
                                condenser_loop,
                                ventilation: true)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', 'Adding zone water-to-air heat pump.')

    water_to_air_hp_systems = []
    thermal_zones.each do |zone|
      supplemental_htg_coil = create_coil_heating_electric(model, name: "#{zone.name.to_s} Supplemental Htg Coil")
      htg_coil = create_coil_heating_water_to_air_heat_pump_equation_fit(model, condenser_loop, name: "#{zone.name} Water-to-Air HP Htg Coil")
      clg_coil = create_coil_cooling_water_to_air_heat_pump_equation_fit(model, condenser_loop, name: "#{zone.name} Water-to-Air HP Clg Coil")

      # add fan
      fan = create_fan_by_name(model, 'WSHP_Fan', fan_name:"#{zone.name} WSHP Fan")
      fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      water_to_air_hp_system = OpenStudio::Model::ZoneHVACWaterToAirHeatPump.new(model, model.alwaysOnDiscreteSchedule, fan, htg_coil, clg_coil, supplemental_htg_coil)
      water_to_air_hp_system.setName("#{zone.name} WSHP")
      unless ventilation
        water_to_air_hp_system.setOutdoorAirFlowRateDuringHeatingOperation(OpenStudio::OptionalDouble.new(0.0))
        water_to_air_hp_system.setOutdoorAirFlowRateDuringCoolingOperation(OpenStudio::OptionalDouble.new(0.0))
        water_to_air_hp_system.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(OpenStudio::OptionalDouble.new(0.0))
      end
      water_to_air_hp_system.addToThermalZone(zone)

      water_to_air_hp_systems << water_to_air_hp_system
    end

    return water_to_air_hp_systems
  end

  # Adds zone level ERVs for each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add heat pumps to.
  # @return [Array<OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator>] an array of zone ERVs
  # @todo review the static pressure rise for the ERV
  def model_add_zone_erv(model,
                         thermal_zones)
    ervs = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding ERV for #{zone.name.to_s}.")

      # Determine the OA requirement for this zone
      min_oa_flow_m3_per_s_per_m2 = thermal_zone_outdoor_airflow_rate_per_area(zone)
      supply_fan = create_fan_by_name(model, 'ERV_Supply_Fan', fan_name:"#{zone.name} ERV Supply Fan")
      impeller_eff = fan_baseline_impeller_efficiency(supply_fan)
      fan_change_impeller_efficiency(supply_fan, impeller_eff)
      exhaust_fan = create_fan_by_name(model, 'ERV_Supply_Fan', fan_name:"#{zone.name} ERV Exhaust Fan")
      fan_change_impeller_efficiency(exhaust_fan, impeller_eff)

      erv_controller = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilatorController.new(model)
      # erv_controller.setExhaustAirTemperatureLimit("NoExhaustAirTemperatureLimit")
      # erv_controller.setExhaustAirEnthalpyLimit("NoExhaustAirEnthalpyLimit")
      # erv_controller.setTimeofDayEconomizerFlowControlSchedule(self.alwaysOnDiscreteSchedule)
      # erv_controller.setHighHumidityControlFlag(false)

      heat_exchanger = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
      # heat_exchanger.setHeatExchangerType("Plate")
      # heat_exchanger.setEconomizerLockout(true)
      # heat_exchanger.setSupplyAirOutletTemperatureControl(false)
      # heat_exchanger.setSensibleEffectivenessat100HeatingAirFlow(0.76)
      # heat_exchanger.setSensibleEffectivenessat75HeatingAirFlow(0.81)
      # heat_exchanger.setLatentEffectivenessat100HeatingAirFlow(0.68)
      # heat_exchanger.setLatentEffectivenessat75HeatingAirFlow(0.73)
      # heat_exchanger.setSensibleEffectivenessat100CoolingAirFlow(0.76)
      # heat_exchanger.setSensibleEffectivenessat75CoolingAirFlow(0.81)
      # heat_exchanger.setLatentEffectivenessat100CoolingAirFlow(0.68)
      # heat_exchanger.setLatentEffectivenessat75CoolingAirFlow(0.73)

      zone_hvac = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator.new(model, heat_exchanger, supply_fan, exhaust_fan)
      zone_hvac.setName("#{zone.name} ERV")
      zone_hvac.setVentilationRateperUnitFloorArea(min_oa_flow_m3_per_s_per_m2)
      zone_hvac.setController(erv_controller)
      zone_hvac.addToThermalZone(zone)

      # Calculate ERV SAT during sizing periods
      # Heating design day
      oat_f = 0.0
      return_air_f = 68.0
      eff = heat_exchanger.sensibleEffectivenessat100HeatingAirFlow
      coldest_erv_supply_f = oat_f - (eff * (oat_f - return_air_f))
      coldest_erv_supply_c = OpenStudio.convert(coldest_erv_supply_f, 'F', 'C').get

      # Cooling design day
      oat_f = 110.0
      return_air_f = 75.0
      eff = heat_exchanger.sensibleEffectivenessat100CoolingAirFlow
      hottest_erv_supply_f = oat_f - (eff * (oat_f - return_air_f))
      hottest_erv_supply_c = OpenStudio.convert(hottest_erv_supply_f, 'F', 'C').get

      # Ensure that zone sizing accounts for OA from ERV
      zone_sizing = zone.sizingZone
      zone_sizing.setAccountforDedicatedOutdoorAirSystem(true)
      zone_sizing.setDedicatedOutdoorAirSystemControlStrategy('ColdSupplyAir')
      zone_sizing.setDedicatedOutdoorAirLowSetpointTemperatureforDesign(coldest_erv_supply_c)
      zone_sizing.setDedicatedOutdoorAirHighSetpointTemperatureforDesign(hottest_erv_supply_c)

      ervs << zone_hvac
    end

    return ervs
  end

  # Adds ideal air loads systems for each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add heat pumps to.
  # @return [Array<OpenStudio::Model::ZoneHVACIdealLoadsAirSystem>] an array of ideal air loads systems
  # TODO: enable default ventilation settings, see https://github.com/UnmetHours/openstudio-measures/tree/master/ideal_loads_options
  def model_add_ideal_air_loads(model,
                                thermal_zones)
    ideal_systems = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding ideal air loads for for #{zone.name.to_s}.")
      ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
      ideal_loads.addToThermalZone(zone)
      ideal_systems << ideal_loads
    end

    return ideal_systems
  end

  # Adds an exhaust fan to each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] an array of thermal zones
  # @param flow_rate [Double] the exhaust fan flow rate in m^3/s
  # @param availability_sch_name [String] the name of the fan availability schedule
  # @param flow_fraction_schedule_name [String] the name of the flow fraction schedule
  # @param balanced_exhaust_fraction_schedule_name [String] the name of the balanced exhaust fraction schedule
  # @return [Array<OpenStudio::Model::FanZoneExhaust>] an array of exhaust fans created
  def model_add_exhaust_fan(model,
                            thermal_zones,
                            flow_rate: nil,
                            availability_sch_name: nil,
                            flow_fraction_schedule_name: nil,
                            balanced_exhaust_fraction_schedule_name: nil)

    if availability_sch_name.nil?
      availability_schedule = model.alwaysOnDiscreteSchedule
    else
      availability_schedule = model_add_schedule(model, availability_sch_name)
    end

    # make an exhaust fan for each zone
    fans = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding zone exhaust fan for #{zone.name.to_s}.")
      fan = OpenStudio::Model::FanZoneExhaust.new(model)
      fan.setName("#{zone.name} Exhaust Fan")
      fan.setAvailabilitySchedule(availability_schedule)

      # input the flow rate as a number (assign directly) or from an array (assign each flow rate to each zone)
      if flow_rate.is_a? Numeric
        fan.setMaximumFlowRate(flow_rate)
      elsif flow_rate.class.to_s == 'Array'
        index = thermal_zones.index(zone)
        flow_rate_zone = flow_rate[index]
        fan.setMaximumFlowRate(flow_rate_zone)
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', 'Wrong format of flow rate')
      end

      unless flow_fraction_schedule_name.nil?
        fan.setFlowFractionSchedule(model_add_schedule(model, flow_fraction_schedule_name))
      end

      fan.setSystemAvailabilityManagerCouplingMode('Decoupled')
      unless balanced_exhaust_fraction_schedule_name.nil?
        fan.setBalancedExhaustFractionSchedule(model_add_schedule(model, balanced_exhaust_fraction_schedule_name))
      end

      fan.addToThermalZone(zone)
      fans << fan
    end

    return fans
  end

  # Adds a zone ventilation design flow rate to each zone.
  #
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] an array of thermal zones
  # @param ventilation_type [String] the zone ventilation type either Exhaust, Natural, or Intake
  # @param flow_rate [Double] the ventilation design flow rate in m^3/s
  # @param availability_sch_name [String] the name of the fan availability schedule
  # @return [Array<OpenStudio::Model::ZoneVentilationDesignFlowRate>] an array of zone ventilation objects created
  def model_add_zone_ventilation(model,
                                 thermal_zones,
                                 ventilation_type: nil,
                                 flow_rate: nil,
                                 availability_sch_name: nil)

    if availability_sch_name.nil?
      availability_schedule = model.alwaysOnDiscreteSchedule
    else
      availability_schedule = model_add_schedule(model, availability_sch_name)
    end

    if flow_rate.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "flow rate nil for zone ventilation.")
    end

    # make a zone ventilation object for each zone
    zone_ventilations = []
    thermal_zones.each do |zone|
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding zone ventilation fan for #{zone.name.to_s}.")
      ventilation = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
      ventilation.setName("#{zone.name} Ventilation")
      ventilation.setSchedule(availability_schedule)

      if ventilation_type == 'Exhaust'
        ventilation.setDesignFlowRateCalculationMethod('Flow/Zone')
        ventilation.setDesignFlowRate(flow_rate)
        ventilation.setFanPressureRise(31.1361206455786)
        ventilation.setFanTotalEfficiency(0.51)
        ventilation.setConstantTermCoefficient(1.0)
        ventilation.setVelocityTermCoefficient(0.0)
        ventilation.setMinimumIndoorTemperature(29.4444452244559)
        ventilation.setMaximumIndoorTemperature(100.0)
        ventilation.setDeltaTemperature(-100.0)
      elsif ventilation_type == 'Natural'
        ventilation.setDesignFlowRateCalculationMethod('Flow/Zone')
        ventilation.setDesignFlowRate(flow_rate)
        ventilation.setFanPressureRise(0.0)
        ventilation.setFanTotalEfficiency(1.0)
        ventilation.setConstantTermCoefficient(0.0)
        ventilation.setVelocityTermCoefficient(0.224)
        ventilation.setMinimumIndoorTemperature(-73.3333352760033)
        ventilation.setMaximumIndoorTemperature(29.4444452244559)
        ventilation.setDeltaTemperature(-100.0)
      elsif ventilation_type == 'Intake'
        ventilation.setDesignFlowRateCalculationMethod('Flow/Area')
        ventilation.setFlowRateperZoneFloorArea(flow_rate)
        ventilation.setFanPressureRise(49.8)
        ventilation.setFanTotalEfficiency(0.53625)
        ventilation.setConstantTermCoefficient(1.0)
        ventilation.setVelocityTermCoefficient(0.0)
        ventilation.setMinimumIndoorTemperature(7.5)
        ventilation.setMaximumIndoorTemperature(35)
        ventilation.setDeltaTemperature(-27.5)
        ventilation.setMinimumOutdoorTemperature(-30.0)
        ventilation.setMaximumOutdoorTemperature(50.0)
        ventilation.setMaximumWindSpeed(6.0)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "ventilation type #{ventilation_type} invalid for zone ventilation.")
      end
      ventilation.setVentilationType(ventilation_type)
      ventilation.setAirChangesperHour(0.0)
      ventilation.setTemperatureTermCoefficient(0.0)
      ventilation.addToThermalZone(zone)
      zone_ventilations << ventilation
    end

    return zone_ventilations
  end

  # Get the existing chilled water loop in the model or add a new one if there isn't one already.
  #
  # @param cool_fuel [String] the cooling fuel. Valid choices are Electricity, DistrictCooling, and HeatPump.
  # @param air_cooled [Bool] if true, the chiller will be air-cooled. if false, it will be water-cooled.
  def model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: true)
    # retrieve the existing chilled water loop or add a new one if necessary
    chilled_water_loop = nil
    if model.getPlantLoopByName('Chilled Water Loop').is_initialized
      chilled_water_loop = model.getPlantLoopByName('Chilled Water Loop').get
    else
      case cool_fuel
      when 'DistrictCooling'
        chilled_water_loop = model_add_chw_loop(model,
                                                chw_pumping_type: 'const_pri',
                                                cooling_fuel: cool_fuel)
      when 'HeatPump'
        condenser_water_loop = model_get_or_add_ambient_water_loop(model)
        chilled_water_loop = model_add_chw_loop(model,
                                                chw_pumping_type: 'const_pri_var_sec',
                                                chiller_cooling_type: 'WaterCooled',
                                                chiller_compressor_type: 'Rotary Screw',
                                                condenser_water_loop: condenser_water_loop)
      when 'Electricity'
        if air_cooled
          chilled_water_loop = model_add_chw_loop(model,
                                                  chw_pumping_type: 'const_pri',
                                                  cooling_fuel: cool_fuel)
        else
          fan_type = model_cw_loop_cooling_tower_fan_type(model)
          condenser_water_loop = model_add_cw_loop(model,
                                                   cooling_tower_type: 'Open Cooling Tower',
                                                   cooling_tower_fan_type: 'Propeller or Axial',
                                                   cooling_tower_capacity_control: fan_type,
                                                   number_of_cells_per_tower: 1,
                                                   number_cooling_towers: 1)
          chilled_water_loop = model_add_chw_loop(model,
                                                  chw_pumping_type: 'const_pri_var_sec',
                                                  chiller_cooling_type: 'WaterCooled',
                                                  chiller_compressor_type: 'Rotary Screw',
                                                  condenser_water_loop: condenser_water_loop)
        end
      end
    end

    return chilled_water_loop
  end

  # Determine which type of fan the cooling tower will have.  Defaults to TwoSpeed Fan.
  # @return [String] the fan type: TwoSpeed Fan, Variable Speed Fan
  def model_cw_loop_cooling_tower_fan_type(model)
    fan_type = 'TwoSpeed Fan'
    return fan_type
  end

  # Get the existing hot water loop in the model or add a new one if there isn't one already.
  #
  # @param heat_fuel [String] the heating fuel. Valid choices are NaturalGas, Electricity, DistrictHeating
  def model_get_or_add_hot_water_loop(model, heat_fuel)
    # retrieve the existing hot water loop or add a new one if necessary
    hot_water_loop = if model.getPlantLoopByName('Hot Water Loop').is_initialized
                       model.getPlantLoopByName('Hot Water Loop').get
                     else
                       model_add_hw_loop(model, heat_fuel)
                     end
    return hot_water_loop
  end

  # Get the existing ambient water loop in the model or add a new one if there isn't one already.
  def model_get_or_add_ambient_water_loop(model)
    # retrieve the existing hot water loop or add a new one if necessary
    ambient_water_loop = if model.getPlantLoopByName('Ambient Loop').is_initialized
                           model.getPlantLoopByName('Ambient Loop').get
                         else
                           model_add_district_ambient_loop(model)
                         end
    return ambient_water_loop
  end

  # Get the existing ground heat exchanger loop in the model or add a new one if there isn't one already.
  def model_get_or_add_ground_hx_loop(model)
    # retrieve the existing ground HX loop or add a new one if necessary
    ground_hx_loop = if model.getPlantLoopByName('Ground HX Loop').is_initialized
                       model.getPlantLoopByName('Ground HX Loop').get
                     else
                       model_add_ground_hx_loop(model)
                     end
    return ground_hx_loop
  end

  # Get the existing heat pump loop in the model or add a new one if there isn't one already.
  def model_get_or_add_heat_pump_loop(model)
    # retrieve the existing heat pump loop or add a new one if necessary
    heat_pump_loop = if model.getPlantLoopByName('Heat Pump Loop').is_initialized
                       model.getPlantLoopByName('Heat Pump Loop').get
                     else
                       model_add_hp_loop(model)
                     end
    return heat_pump_loop
  end

  # Add the specified system type to the specified zones based on the specified template.
  # For multi-zone system types, add one system per story.
  #
  # @param system_type [String] The system type.  Valid choices are
  # TODO: enumerate the valid strings
  # @return [Bool] returns true if successful, false if not
  def model_add_hvac_system(model, system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones)
    # Don't do anything if there are no zones
    return true if zones.empty?

    case system_type
    when 'PTAC'
      case main_heat_fuel
      when 'NaturalGas', 'DistrictHeating'
        heating_type = 'Water'
        hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      when 'Electricity'
        heating_type = main_heat_fuel
        hot_water_loop = nil
      when nil
        heating_type = zone_heat_fuel
        hot_water_loop = nil
      end

      model_add_ptac(model,
                     zones,
                     cooling_type: 'Single Speed DX AC',
                     heating_type: heating_type,
                     hot_water_loop: hot_water_loop,
                     fan_type: 'ConstantVolume')

    when 'PTHP'
      model_add_pthp(model,
                     zones,
                     fan_type: 'ConstantVolume')

    when 'PSZ-AC'
      case main_heat_fuel
      when 'NaturalGas'
        heating_type = main_heat_fuel
        supplemental_heating_type = 'Electricity'
        hot_water_loop = nil
      when 'DistrictHeating'
        heating_type = 'Water'
        supplemental_heating_type = 'Electricity'
        hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      when nil
        heating_type = nil
        supplemental_heating_type = nil
        hot_water_loop = nil
      when 'Electricity'
        heating_type = main_heat_fuel
        supplemental_heating_type = 'Electricity'
      end

      case cool_fuel
      when 'DistrictCooling'
        chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)
        cooling_type = 'Water'
      else
        chilled_water_loop = nil
        cooling_type = 'Single Speed DX AC'
      end

      model_add_psz_ac(model,
                       system_name = nil,
                       hot_water_loop,
                       chilled_water_loop,
                       zones,
                       hvac_op_sch = nil,
                       oa_damper_sch = nil,
                       fan_location = 'DrawThrough',
                       fan_type = 'ConstantVolume',
                       heating_type,
                       supplemental_heating_type,
                       cooling_type)

    when 'PSZ-HP'
      model_add_psz_ac(model,
                       system_name = 'PSZ-HP',
                       hot_water_loop = nil,
                       chilled_water_loop = nil,
                       zones,
                       hvac_op_sch = nil,
                       oa_damper_sch = nil,
                       fan_location = 'DrawThrough',
                       fan_type = 'ConstantVolume',
                       heating_type = 'Single Speed Heat Pump',
                       supplemental_heating_type = 'Electricity',
                       cooling_type = 'Single Speed Heat Pump')
    when 'PSZ-VAV'
      if main_heat_fuel.nil?
        supplemental_heating_type = nil
      else
        supplemental_heating_type = 'Electricity'
      end
      model_add_psz_vav(model,
                        zones,
                        system_name: 'PSZ-VAV',
                        heating_type: main_heat_fuel,
                        supplemental_heating_type: supplemental_heating_type,
                        hvac_op_sch: nil,
                        oa_damper_sch: nil)
    when 'VRF'
      model_add_vrf(model,
                    zones)

    when 'Fan Coil'
      case main_heat_fuel
      when 'NaturalGas', 'DistrictHeating', 'Electricity'
        hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      when nil
        hot_water_loop = nil
      end

      case cool_fuel
      when 'Electricity', 'DistrictCooling'
        chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: true)
      when nil
        chilled_water_loop = nil
      end

      model_add_four_pipe_fan_coil(model,
                                   zones,
                                   chilled_water_loop,
                                   hot_water_loop: hot_water_loop,
                                   ventilation: true)

    when 'Baseboards'
      case main_heat_fuel
      when 'NaturalGas', 'DistrictHeating'
        hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      when 'Electricity'
        hot_water_loop = nil
      when nil
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Baseboards must have heating_type specified.")
      end
      model_add_baseboard(model,
                          zones,
                          hot_water_loop: hot_water_loop)

    when 'Unit Heaters'
      model_add_unitheater(model,
                           zones,
                           hvac_op_sch = nil,
                           fan_control_type = 'ConstantVolume',
                           fan_pressure_rise = 0.2,
                           main_heat_fuel)

    when 'Window AC'
      model_add_window_ac(model,
                          zones)

    when 'Residential AC'
      model_add_furnace_central_ac(model,
                                   zones,
                                   heating: false,
                                   cooling: true,
                                   ventilation: false)

    when 'Forced Air Furnace'
      model_add_furnace_central_ac(model,
                                   zones,
                                   heating: true,
                                   cooling: false,
                                   ventilation: true)

    when 'Residential Forced Air Furnace'
      model_add_furnace_central_ac(model,
                                   zones,
                                   heating: true,
                                   cooling: false,
                                   ventilation: false)

    when 'Residential Air Source Heat Pump'
      heating = true unless main_heat_fuel.nil?
      cooling = true unless cool_fuel.nil?
      model_add_central_air_source_heat_pump(model,
                                             zones,
                                             heating: heating,
                                             cooling: cooling,
                                             ventilation: false)

    when 'VAV Reheat'
      hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)

      reheat_type = 'Water'
      if zone_heat_fuel == 'Electricity'
        reheat_type = 'Electricity'
      end

      model_add_vav_reheat(model,
                           system_name = nil,
                           hot_water_loop,
                           chilled_water_loop,
                           zones,
                           hvac_op_sch = nil,
                           oa_damper_sch = nil,
                           vav_fan_efficiency = 0.62,
                           vav_fan_motor_efficiency = 0.9,
                           vav_fan_pressure_rise = 4.0,
                           return_plenum = nil,
                           reheat_type)

    when 'VAV No Reheat'
      chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)

      model_add_vav_reheat(model,
                           system_name = nil,
                           hot_water_loop,
                           chilled_water_loop,
                           zones,
                           hvac_op_sch = nil,
                           oa_damper_sch = nil,
                           vav_fan_efficiency = 0.62,
                           vav_fan_motor_efficiency = 0.9,
                           vav_fan_pressure_rise = 4.0,
                           return_plenum = nil,
                           reheat_type = nil)

    when 'VAV Gas Reheat'
      chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)

      model_add_vav_reheat(model,
                           system_name = nil,
                           hot_water_loop,
                           chilled_water_loop,
                           zones,
                           hvac_op_sch = nil,
                           oa_damper_sch = nil,
                           vav_fan_efficiency = 0.62,
                           vav_fan_motor_efficiency = 0.9,
                           vav_fan_pressure_rise = 4.0,
                           return_plenum = nil,
                           reheat_type = 'NaturalGas')

    when 'PVAV Reheat'
      hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      chilled_water_loop = case cool_fuel
                           when 'Electricity'
                             nil
                           else
                             model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)
                           end

      electric_reheat = false
      if zone_heat_fuel == 'Electricity'
        electric_reheat = true
      end

      model_add_pvav(model,
                     system_name = nil,
                     zones,
                     hvac_op_sch = nil,
                     oa_damper_sch = nil,
                     electric_reheat,
                     hot_water_loop,
                     chilled_water_loop,
                     return_plenum = nil)

    when 'PVAV PFP Boxes'
      chilled_water_loop = case cool_fuel
                           when 'DistrictCooling'
                             model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)
                           end

      model_add_pvav_pfp_boxes(model,
                               system_name = nil,
                               zones,
                               hvac_op_sch = nil,
                               oa_damper_sch = nil,
                               vav_fan_efficiency = 0.62,
                               vav_fan_motor_efficiency = 0.9,
                               vav_fan_pressure_rise = 4.0,
                               chilled_water_loop)
    when 'VAV PFP Boxes'
      chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)

      model_add_pvav_pfp_boxes(model,
                               system_name = nil,
                               zones,
                               hvac_op_sch = nil,
                               oa_damper_sch = nil,
                               vav_fan_efficiency = 0.62,
                               vav_fan_motor_efficiency = 0.9,
                               vav_fan_pressure_rise = 4.0,
                               chilled_water_loop)

    when 'Water Source Heat Pumps'
      condenser_loop = case main_heat_fuel
                       when 'NaturalGas'
                         model_get_or_add_heat_pump_loop(model)
                       else
                         model_get_or_add_ambient_water_loop(model)
                       end

      model_add_water_source_hp(model,
                                zones,
                                condenser_loop,
                                ventilation: false)

    when 'Ground Source Heat Pumps'
      # TODO: replace condenser loop w/ ground HX model that does not involve district objects
      condenser_loop = model_get_or_add_ground_hx_loop(model)
      model_add_water_source_hp(model,
                                zones,
                                condenser_loop,
                                ventilation: false)

    when 'DOAS'
      hot_water_loop = model_get_or_add_hot_water_loop(model, main_heat_fuel)
      chilled_water_loop = model_get_or_add_chilled_water_loop(model, cool_fuel, air_cooled: false)
      model_add_doas(model,
                     zones,
                     doas_type: "DOASCV",
                     hot_water_loop: hot_water_loop,
                     chilled_water_loop: chilled_water_loop,
                     econo_ctrl_mthd: "FixedDryBulb",
                     doas_control_strategy: "ColdSupplyAir",
                     clg_dsgn_sup_air_temp: 55.0,
                     htg_dsgn_sup_air_temp: 60.0)

    when 'DOAS No Plant'
      model_add_doas(model, zones, energy_recovery: true)

    when 'ERVs'
      model_add_zone_erv(model, zones)

    when 'Evaporative Cooler'
      model_add_evap_cooler(model, zones)

    when 'Ideal Air Loads'
      model_add_ideal_air_loads(model, zones)

    ### Combination Systems ###
    when 'Water Source Heat Pumps with ERVs'
      model_add_hvac_system(model,
                            system_type = 'Water Source Heat Pumps',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'ERVs',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when 'Water Source Heat Pumps with DOAS'
      model_add_hvac_system(model,
                            system_type = 'Water Source Heat Pumps',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'DOAS',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when 'Ground Source Heat Pumps with ERVs'
      model_add_hvac_system(model,
                            system_type = 'Ground Source Heat Pumps',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'ERVs',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when 'Ground Source Heat Pumps with DOAS'
      model_add_hvac_system(model,
                            system_type = 'Ground Source Heat Pumps',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'DOAS',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when 'Fan Coil with DOAS'
      model_add_hvac_system(model,
                            system_type = 'Fan Coil',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'DOAS',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when 'Fan Coil with ERVs'
      model_add_hvac_system(model,
                            system_type = 'Fan Coil',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'ERVs',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    when  'VRF with DOAS'
      model_add_hvac_system(model,
                            system_type = 'VRF',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

      model_add_hvac_system(model,
                            system_type = 'DOAS No Plant',
                            main_heat_fuel,
                            zone_heat_fuel,
                            cool_fuel,
                            zones)

    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "HVAC system type '#{system_type}' not recognized")
      return false
    end
  end

  # Determine the typical system type given the inputs.
  #
  # @param area_type [String] Valid choices are residential
  # and nonresidential
  # @param delivery_type [String] Conditioning delivery type.
  # Valid choices are air and hydronic
  # @param heating_source [String] Valid choices are
  # Electricity, NaturalGas, DistrictHeating, DistrictAmbient
  # @param cooling_source [String] Valid choices are
  # Electricity, DistrictCooling, DistrictAmbient
  # @param area_m2 [Double] Area in m^2
  # @param num_stories [Integer] Number of stories
  # @return [String] The system type.  Possibilities are
  # PTHP, PTAC, PSZ_AC, PSZ_HP, PVAV_Reheat, PVAV_PFP_Boxes,
  # VAV_Reheat, VAV_PFP_Boxes, Gas_Furnace, Electric_Furnace
  def model_typical_hvac_system_type(model,
                                     climate_zone,
                                     area_type,
                                     delivery_type,
                                     heating_source,
                                     cooling_source,
                                     area_m2,
                                     num_stories)
    #             [type, central_heating_fuel, zone_heating_fuel, cooling_fuel]
    system_type = [nil, nil, nil, nil]

    # Convert area to ft^2
    area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

    # categorize building by type & size
    size_category = nil
    case area_type
    when 'residential'
      # residential and less than 4 stories
      size_category = if num_stories <= 3
                        'res_small'
                      # residential and more than 4 stories
                      else
                        'res_med'
                      end
    when 'nonresidential', 'retail', 'publicassembly', 'heatedonly'
      # nonresidential and 3 floors or less and < 75,000 ft2
      if num_stories <= 3 && area_ft2 < 75_000
        size_category = 'nonres_small'
      # nonresidential and 4 or 5 floors OR 5 floors or less and 75,000 ft2 to 150,000 ft2
      elsif ((num_stories == 4 || num_stories == 5) && area_ft2 < 75_000) || (num_stories <= 5 && (area_ft2 >= 75_000 && area_ft2 <= 150_000))
        size_category = 'nonres_med'
      # nonresidential and more than 5 floors or >150,000 ft2
      elsif num_stories >= 5 || area_ft2 > 150_000
        size_category = 'nonres_lg'
      end
    end

    # Define the lookup by row and by fuel type
    syts = Hash.new { |h, k| h[k] = Hash.new(&h.default_proc) }
    # [heating_source][cooling_source][delivery_type][size_category]
    #  = [type, central_heating_fuel, zone_heating_fuel, cooling_fuel]

    ## Forced Air ##

    # Gas, Electric, forced air
    syts['NaturalGas']['Electricity']['air']['res_small'] = ['PTAC', 'NaturalGas', nil, 'Electricity']
    syts['NaturalGas']['Electricity']['air']['res_med'] = ['PTAC', 'NaturalGas', nil, 'Electricity']
    syts['NaturalGas']['Electricity']['air']['nonres_small'] = ['PSZ-AC', 'NaturalGas', nil, 'Electricity']
    syts['NaturalGas']['Electricity']['air']['nonres_med'] = ['PVAV Reheat', 'NaturalGas', 'NaturalGas', 'Electricity']
    syts['NaturalGas']['Electricity']['air']['nonres_lg'] = ['VAV Reheat', 'NaturalGas', 'NaturalGas', 'Electricity']

    # Electric, Electric, forced air
    syts['Electricity']['Electricity']['air']['res_small'] = ['PTHP', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['air']['res_med'] = ['PTHP', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['air']['nonres_small'] = ['PSZ-HP', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['air']['nonres_med'] = ['PVAV PFP Boxes', 'Electricity', 'Electricity', 'Electricity']
    syts['Electricity']['Electricity']['air']['nonres_lg'] = ['VAV PFP Boxes', 'Electricity', 'Electricity', 'Electricity']

    # District Hot Water, Electric, forced air
    syts['DistrictHeating']['Electricity']['air']['res_small'] = ['PTAC', 'DistrictHeating', nil, 'Electricity']
    syts['DistrictHeating']['Electricity']['air']['res_med'] = ['PTAC', 'DistrictHeating', nil, 'Electricity']
    syts['DistrictHeating']['Electricity']['air']['nonres_small'] = ['PVAV Reheat', 'DistrictHeating', 'DistrictHeating', 'Electricity']
    syts['DistrictHeating']['Electricity']['air']['nonres_med'] = ['PVAV Reheat', 'DistrictHeating', 'DistrictHeating', 'Electricity']
    syts['DistrictHeating']['Electricity']['air']['nonres_lg'] = ['VAV Reheat', 'DistrictHeating', 'DistrictHeating', 'Electricity']

    # Ambient Loop, Ambient Loop, forced air
    syts['DistrictAmbient']['DistrictAmbient']['air']['res_small'] = ['Water Source Heat Pumps with ERVs', 'HeatPump', nil, 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['air']['res_med'] = ['Water Source Heat Pumps with DOAS', 'HeatPump', nil, 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['air']['nonres_small'] = ['PVAV Reheat', 'HeatPump', 'HeatPump', 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['air']['nonres_med'] = ['PVAV Reheat', 'HeatPump', 'HeatPump', 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['air']['nonres_lg'] = ['VAV Reheat', 'HeatPump', 'HeatPump', 'HeatPump']

    # Gas, District Chilled Water, forced air
    syts['NaturalGas']['DistrictCooling']['air']['res_small'] = ['PSZ-AC', 'NaturalGas', nil, 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['air']['res_med'] = ['PSZ-AC', 'NaturalGas', nil, 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['air']['nonres_small'] = ['PSZ-AC', 'NaturalGas', nil, 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['air']['nonres_med'] = ['PVAV Reheat', 'NaturalGas', 'NaturalGas', 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['air']['nonres_lg'] = ['VAV Reheat', 'NaturalGas', 'NaturalGas', 'DistrictCooling']

    # Electric, District Chilled Water, forced air
    syts['Electricity']['DistrictCooling']['air']['res_small'] = ['PSZ-AC', 'Electricity', nil, 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['air']['res_med'] = ['PSZ-AC', 'Electricity', nil, 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['air']['nonres_small'] = ['PSZ-AC', 'Electricity', nil, 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['air']['nonres_med'] = ['PVAV Reheat', 'Electricity', 'Electricity', 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['air']['nonres_lg'] = ['VAV Reheat', 'Electricity', 'Electricity', 'DistrictCooling']

    # District Hot Water, District Chilled Water, forced air
    syts['DistrictHeating']['DistrictCooling']['air']['res_small'] = ['PSZ-AC', 'DistrictHeating', nil, 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['air']['res_med'] = ['PSZ-AC', 'DistrictHeating', nil, 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['air']['nonres_small'] = ['PVAV Reheat', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['air']['nonres_med'] = ['PVAV Reheat', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['air']['nonres_lg'] = ['VAV Reheat', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']

    ## Hydronic ##

    # Gas, Electric, hydronic
    syts['NaturalGas']['Electricity']['hydronic']['res_med'] = ['Fan Coil with DOAS', 'NaturalGas', nil, 'Electricity']
    syts['NaturalGas']['Electricity']['hydronic']['nonres_small'] = ['Water Source Heat Pumps with DOAS', 'NaturalGas', nil, 'Electricity']
    syts['NaturalGas']['Electricity']['hydronic']['nonres_med'] = ['Fan Coil with DOAS', 'NaturalGas', 'NaturalGas', 'Electricity']
    syts['NaturalGas']['Electricity']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'NaturalGas', 'NaturalGas', 'Electricity']

    # Electric, Electric, hydronic
    syts['Electricity']['Electricity']['hydronic']['res_small'] = ['Ground Source Heat Pumps with ERVs', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['hydronic']['res_med'] = ['Ground Source Heat Pumps with DOAS', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['hydronic']['nonres_small'] = ['Ground Source Heat Pumps with DOAS', 'Electricity', nil, 'Electricity']
    syts['Electricity']['Electricity']['hydronic']['nonres_med'] = ['Ground Source Heat Pumps with DOAS', 'Electricity', 'Electricity', 'Electricity']
    syts['Electricity']['Electricity']['hydronic']['nonres_lg'] = ['Ground Source Heat Pumps with DOAS', 'Electricity', 'Electricity', 'Electricity']

    # District Hot Water, Electric, hydronic
    syts['DistrictHeating']['Electricity']['hydronic']['res_small'] = [] # TODO decide if there is anything reasonable for this
    syts['DistrictHeating']['Electricity']['hydronic']['res_med'] = ['Fan Coil with DOAS', 'DistrictHeating', nil, 'Electricity']
    syts['DistrictHeating']['Electricity']['hydronic']['nonres_small'] = ['Water Source Heat Pumps with DOAS', 'DistrictHeating', 'DistrictHeating', 'Electricity']
    syts['DistrictHeating']['Electricity']['hydronic']['nonres_med'] = ['Fan Coil with DOAS', 'DistrictHeating', 'DistrictHeating', 'Electricity']
    syts['DistrictHeating']['Electricity']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'DistrictHeating', 'DistrictHeating', 'Electricity']

    # Ambient Loop, Ambient Loop, hydronic
    syts['DistrictAmbient']['DistrictAmbient']['hydronic']['res_small'] = ['Water Source Heat Pumps with ERVs', 'HeatPump', nil, 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['hydronic']['res_med'] = ['Water Source Heat Pumps with DOAS', 'HeatPump', nil, 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['hydronic']['nonres_small'] = ['Water Source Heat Pumps with DOAS', 'HeatPump', 'HeatPump', 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['hydronic']['nonres_med'] = ['Water Source Heat Pumps with DOAS', 'HeatPump', 'HeatPump', 'HeatPump']
    syts['DistrictAmbient']['DistrictAmbient']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'DistrictHeating', nil, 'Electricity'] # TODO: is this reasonable?

    # Gas, District Chilled Water, hydronic
    syts['NaturalGas']['DistrictCooling']['hydronic']['res_med'] = ['Fan Coil with DOAS', 'NaturalGas', nil, 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['hydronic']['nonres_small'] = ['Fan Coil with DOAS', 'NaturalGas', nil, 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['hydronic']['nonres_med'] = ['Fan Coil with DOAS', 'NaturalGas', 'NaturalGas', 'DistrictCooling']
    syts['NaturalGas']['DistrictCooling']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'NaturalGas', 'NaturalGas', 'DistrictCooling']

    # Electric, District Chilled Water, hydronic
    syts['Electricity']['DistrictCooling']['hydronic']['res_med'] = ['Fan Coil with ERVs', 'Electricity', nil, 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['hydronic']['nonres_small'] = ['Fan Coil with DOAS', 'Electricity', nil, 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['hydronic']['nonres_med'] = ['Fan Coil with DOAS', 'Electricity', 'Electricity', 'DistrictCooling']
    syts['Electricity']['DistrictCooling']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'Electricity', 'Electricity', 'DistrictCooling']

    # District Hot Water, District Chilled Water, hydronic
    syts['DistrictHeating']['DistrictCooling']['hydronic']['res_small'] = ['Fan Coil with ERVs', 'DistrictHeating', nil, 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['hydronic']['res_med'] = ['Fan Coil with DOAS', 'DistrictHeating', nil, 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['hydronic']['nonres_small'] = ['Fan Coil with DOAS', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['hydronic']['nonres_med'] = ['Fan Coil with DOAS', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']
    syts['DistrictHeating']['DistrictCooling']['hydronic']['nonres_lg'] = ['Fan Coil with DOAS', 'DistrictHeating', 'DistrictHeating', 'DistrictCooling']

    # Get the system type
    system_type = syts[heating_source][cooling_source][delivery_type][size_category]

    if system_type.nil? || system_type.empty?
      system_type = [nil, nil, nil, nil]
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Could not determine system type for #{template}, #{area_type}, #{heating_source} heating, #{cooling_source} cooling, #{delivery_type} delivery, #{area_ft2.round} ft^2, #{num_stories} stories.")
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "System type is #{system_type[0]} for #{template}, #{area_type}, #{heating_source} heating, #{cooling_source} cooling, #{delivery_type} delivery, #{area_ft2.round} ft^2, #{num_stories} stories.")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type[1]} for main heating") unless system_type[1].nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type[2]} for zone heat/reheat") unless system_type[2].nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type[3]} for cooling") unless system_type[3].nil?
    end

    return system_type
  end
end
