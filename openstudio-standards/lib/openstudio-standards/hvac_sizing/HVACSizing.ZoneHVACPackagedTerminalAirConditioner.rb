# Author: Julien Marrec

# open the class to add methods to return sizing values
class OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner


   # A helper method to get component sizes from the model
  # returns the autosized value as an optional double
  def getAutosizedValue(value_name, units)

    result = OpenStudio::OptionalDouble.new

    name = self.name.get.upcase
    
    object_type = self.iddObject.type.valueDescription.gsub('OS:','')
    
    # Get the model's attached sqlFile
    sql = self.model.sqlFile
    
    if sql.is_initialized
      sql = sql.get
    
      #SELECT * FROM ComponentSizes WHERE CompType = 'Coil:Heating:Gas' AND CompName = "COIL HEATING GAS 3" AND Description = "Design Size Nominal Capacity"
      query = "SELECT Value 
              FROM ComponentSizes 
              WHERE CompType='#{object_type}' 
              AND CompName='#{name}' 
              AND Description='#{value_name}' 
              AND Units='#{units}'"
              
      val = sql.execAndReturnFirstDouble(query)
      
      if val.is_initialized
        result = OpenStudio::OptionalDouble.new(val.get)
      else
        #OpenStudio::logFree(OpenStudio::Warn, "openstudio.model.Model", "Data not found for query: #{query}")
      end
    else
      OpenStudio::logFree(OpenStudio::Error, 'openstudio.model.Model', 'Model has no sql file containing results, cannot lookup data.')
    end

    return result
  end   


  # Sets all auto-sizeable fields to autosize
  def autosize
    OpenStudio::logFree(OpenStudio::Warn, "openstudio.sizing.ZoneHVACPackagedTerminalAirConditioner", ".autosize not yet implemented for #{self.iddObject.type.valueDescription}.")
  end

  # Takes the values calculated by the EnergyPlus sizing routines
  # and puts them into this object model in place of the autosized fields.
  # Must have previously completed a run with sql output for this to work.
  def applySizingValues

    # Supply Air Flow Rate During Cooling Operation
    supply_air_flow_cooling = self.autosizedSupplyAirFlowRateDuringCoolingOperation
    if supply_air_flow_cooling.is_initialized
      self.setSupplyAirFlowRateDuringCoolingOperation(supply_air_flow_cooling.get)
    end
    
    # Supply Air Flow Rate During Heating Operation
    supply_air_flow_heating = self.autosizedSupplyAirFlowRateDuringHeatingOperation
    if supply_air_flow_heating.is_initialized
      self.setSupplyAirFlowRateDuringHeatingOperation(supply_air_flow_heating.get)
    end
    
    # Supply Air Flow Rate When No Cooling or Heating is Needed
    supply_air_flow_noload = self.autosizedSupplyAirFlowRateWhenNoCoolingorHeatingisNeeded
    if supply_air_flow_noload.is_initialized
      self.setSupplyAirFlowRateWhenNoCoolingorHeatingisNeeded(supply_air_flow_noload.get)
    end
    
    # Outdoor Air Flow Rate During Cooling Operation
    oa_air_flow_cooling = self.autosizedOutdoorAirFlowRateDuringCoolingOperation
    if oa_air_flow_cooling.is_initialized
      self.setOutdoorAirFlowRateDuringCoolingOperation(oa_air_flow_cooling.get)
    end
    
    # Outdoor Air Flow Rate During Heating Operation
    oa_air_flow_heating    = self.autosizedOutdoorAirFlowRateDuringHeatingOperation
    if oa_air_flow_heating.is_initialized
      self.setOutdoorAirFlowRateDuringHeatingOperation(oa_air_flow_heating.get)
    end
    
    # Outdoor Air Flow Rate When No Cooling or Heating is Needed
    oa_air_flow_noload = self.autosizedOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded
    if oa_air_flow_noload.is_initialized
      self.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(oa_air_flow_noload.get)
    end
    
        
  end


  # Supply Air Flow Rate During Cooling Operation
  def autosizedSupplyAirFlowRateDuringCoolingOperation
  
    return self.getAutosizedValue('Design Size Cooling Supply Air Flow Rate', 'm3/s')
  
  end
  
  # Supply Air Flow Rate During Heating Operation
  def autosizedSupplyAirFlowRateDuringHeatingOperation
  
    return self.getAutosizedValue('Design Size Heating Supply Air Flow Rate', 'm3/s')
  
  end
  
  # Supply Air Flow Rate When No Cooling or Heating is Needed
  def autosizedSupplyAirFlowRateWhenNoCoolingorHeatingisNeeded
  
    return self.getAutosizedValue('Design Size No Load Supply Air Flow Rate', 'm3/s')
  
  end
  
  # Outdoor Air Flow Rate During Cooling Operation
  def autosizedOutdoorAirFlowRateDuringCoolingOperation
  
    return self.getAutosizedValue('Design Size Outdoor Air Flow Rate During Cooling Operation', 'm3/s')
  
  end

  # Outdoor Air Flow Rate During Heating Operation
  def autosizedOutdoorAirFlowRateDuringHeatingOperation
  
    return self.getAutosizedValue('Design Size Outdoor Air Flow Rate During Heating Operation', 'm3/s')
  
  end
  
  # Outdoor Air Flow Rate When No Cooling or Heating is Needed
  def autosizedOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded
  
    return self.getAutosizedValue('Design Size Outdoor Air Flow Rate When No Cooling or Heating is Needed', 'm3/s')
  
  end
  
  
 
  
end

