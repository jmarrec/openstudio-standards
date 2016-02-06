# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class CreateAllDOEPrototypeBuildings < OpenStudio::Ruleset::ModelUserScript

  require 'openstudio-standards'
  
  # human readable name
  def name
    return "Create All DOE PrototypeBuildings"
  end

  # human readable description
  def description
    return "This measure creates all DOE prototype buildings, naming the OSM files {building_type}-{template}-{climate_zone}.osm"
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure creates all DOE prototype buildings, naming the OSM files {building_type}-{template}-{climate_zone}.osm"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end # arguments

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    building_type_chs = []
=begin
    building_type_chs << 'SecondarySchool'
    building_type_chs << 'PrimarySchool'
    building_type_chs << 'SmallOffice'
    building_type_chs << 'MediumOffice'
    building_type_chs << 'LargeOffice'
=end
    building_type_chs << 'SmallHotel'
=begin
    building_type_chs << 'LargeHotel'
    building_type_chs << 'Warehouse'
    building_type_chs << 'RetailStandalone'
    building_type_chs << 'RetailStripmall'
    building_type_chs << 'QuickServiceRestaurant'
    building_type_chs << 'FullServiceRestaurant'
    building_type_chs << 'Hospital'
    building_type_chs << 'Outpatient'
    building_type_chs << 'MidriseApartment'
    building_type_chs << 'HighriseApartment'
=end    
    # Make an argument for the template
    template_chs = []
    template_chs << 'DOE Ref Pre-1980'
=begin
    template_chs << 'DOE Ref 1980-2004'
    template_chs << '90.1-2004'
    template_chs << '90.1-2007'
    template_chs << '90.1-2010'
    template_chs << '90.1-2013'
=end
    cz_ba2ashrae_hash = Hash.new
    cz_ba2ashrae_hash['BA-HotHumid'] = 'ASHRAE 169-2006-2A'
    cz_ba2ashrae_hash['BA-HotDry'] = 'ASHRAE 169-2006-3B'
    cz_ba2ashrae_hash['BA-MixedDry'] = 'ASHRAE 169-2006-4B'
    cz_ba2ashrae_hash['BA-MixedHumid'] = 'ASHRAE 169-2006-4A'
    cz_ba2ashrae_hash['BA-Marine'] = 'ASHRAE 169-2006-3C'
    cz_ba2ashrae_hash['BA-Cold'] = 'ASHRAE 169-2006-5A'
    cz_ba2ashrae_hash['BA-VeryCold'] = 'ASHRAE 169-2006-7A'
    cz_ba2ashrae_hash['BA-SubArctic'] = 'ASHRAE 169-2006-8A'

    # Make an argument for the climate zone
    climate_zone_chs = []
=begin
    climate_zone_chs << 'BA-HotHumid'
    climate_zone_chs << 'BA-HotDry'
    climate_zone_chs << 'BA-MixedDry'
    climate_zone_chs << 'BA-MixedHumid'
    climate_zone_chs << 'BA-Marine'
    climate_zone_chs << 'BA-Cold'
    climate_zone_chs << 'BA-VeryCold'
=end
    climate_zone_chs << 'BA-SubArctic'

    # Turn debugging output on/off
    @debug = false
    
    # Open a channel to log info/warning/error messages
    @msg_log = OpenStudio::StringStreamLogSink.new
    if @debug
      @msg_log.setLogLevel(OpenStudio::Debug)
    else
      @msg_log.setLogLevel(OpenStudio::Info)
    end
    @start_time = Time.new
    @runner = runner

    # Make a directory to save the resulting models for debugging
    pb_dir = "#{Dir.home}/prototype_buildings"

    if !Dir.exists?(pb_dir)
      Dir.mkdir(pb_dir)
    end
# =begin
    # Could use the OpenStudio link but the space in "OpenStudio 1.10.0" makes that nasty in some places
    ep_dir = "/Applications/EnergyPlus-8-4-0"
    
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new()

    building_type_chs.each do |building_type|
      template_chs.each do |template|
        climate_zone_chs.each do |climate_zone|
          
          file_prefix = "#{building_type}-#{template}-#{climate_zone}"

          model = OpenStudio::Model::Model.new()
          model.create_prototype_building(building_type,template,cz_ba2ashrae_hash[climate_zone],pb_dir,@debug)
          model.save(OpenStudio::Path.new("#{pb_dir}/#{building_type}-#{template}-#{climate_zone}.osm"), true)

          @runner.registerInfo("successfully saved model #{pb_dir}/#{file_prefix}.osm")

          idf_model = forward_translator.translateModel(model)
          idf_model.save(OpenStudio::Path.new("#{pb_dir}/#{file_prefix}.idf"))

          @runner.registerInfo("successfully saved model #{pb_dir}/#{file_prefix}.idf")

          weather_file = model.weatherFile.get.path.get.to_s
          run_string = "#{ep_dir}/energyplus -i #{ep_dir}/Energy+.idd -w #{weather_file} -p \"#{file_prefix}\" -d #{pb_dir} \"#{pb_dir}/#{file_prefix}.idf\""
          @runner.registerInfo("#{run_string}")

          if not system("#{run_string}")
            @runner.registerInfo("failed to run model #{pb_dir}/#{file_prefix}.idf")
            next
          end

          @runner.registerInfo("successfully ran model #{pb_dir}/#{file_prefix}.idf")

        end # @climate_zone_chs.each
      end # @template_chs.each
    end # @building_type_chs.each

    # cleanup
    system("rm -f #{pb_dir}/*.audit #{pb_dir}/*.bnd #{pb_dir}/*.err #{pb_dir}/*.dxf #{pb_dir}/*.shd #{pb_dir}/*.mdd #{pb_dir}/*.mtd #{pb_dir}/*.rdd #{pb_dir}/*.mtr #{pb_dir}/*.csv #{pb_dir}/*.eio")
# =end
=begin
    results_table = {}
    results_table[:title] = 'Prototype Buildings'
    results_table[:header] = [
      'Climate Zone',
      'Building Type',
      'Template',

      'Status',
      
      'Floor Area (ft^2)',
      'Total Site Electricity (mmBtu)',
      'Net Site Electricity (mmBtu)',
      'Total Gas (mmBtu)',

      'Total Other Fuel (mmBtu)',
      'Total Water (ft^3)',
      'Net Water (ft^3)',

      'Interior Lighting Electricity (mmBtu)',
      'Exterior Lighting Electricity (mmBtu)',
      'Interior Equipment Electricity (mmBtu)',
      'Exterior Equipment Electricity (mmBtu)',
      'Heating Electricity (mmBtu)',
      'Cooling Electricity (mmBtu)',
      'Service Water Heating Electricity (mmBtu)',
      'Fan Electricity (mmBtu)',
      'Pump Electricity (mmBtu)',
      'Heat Recovery Electricity (mmBtu)',
      'Heat Rejection Electricity (mmBtu)',
      'Humidification Electricity (mmBtu)',
      'Refrigeration Electricity (mmBtu)',
      'Generated Electricity (mmBtu)',

      'Interior Equipment Gas (mmBtu)',
      'Exterior Equipment Gas (mmBtu)',
      'Heating Gas (mmBtu)',
      'Service Water Heating Gas (mmBtu)',

      'Interior Equipment Other Fuel (mmBtu)',
      'Exterior Equipment Other Fuel (mmBtu)',
      'Heating Other Fuel (mmBtu)',
      'Service Water Heating Other Fuel (mmBtu)',
      
      'District Hot Water Heating (mmBtu)',
      'District Hot Water Service Hot Water (mmBtu)',
      'District Chilled Water (mmBtu)',

      'Interior Equipment Water (ft^3)',
      'Exterior Equipment Water (ft^3)',
      'Service Water (ft^3)',
      'Cooling Water (ft^3)',
      'Heating Water (ft^3)',
      'Humidifcation Water (ft^3)',
      'Collected Water (ft^3)',

      'Peak Electricity January',
      'Peak Electricity February',
      'Peak Electricity March',
      'Peak Electricity April',
      'Peak Electricity May',
      'Peak Electricity June',
      'Peak Electricity July',
      'Peak Electricity August',
      'Peak Electricity September',
      'Peak Electricity October',
      'Peak Electricity November',
      'Peak Electricity December'
    ]

    results_table[:data] = []
    
    building_type_chs.each do |building_type|
      template_chs.each do |template|
        climate_zone_chs.each do |climate_zone|

          file_prefix = "#{building_type}-#{template}-#{climate_zone}"
          
          f = File.open("#{pb_dir}/#{file_prefix}out.end")
          l = f.readline()
          f.close()
          if l.index("Successfully") == nil
            @runner.registerInfo("error on run #{file_prefix}")
            results_table[:data] << [climate_zone, building_type, template, "Error"]
            next 
          end
                                          

          model = safe_load_model("#{pb_dir}/#{file_prefix}.osm")
          if not model
            @runner.registerInfo("failed load model #{pb_dir}/#{file_prefix}.osm")
            results_table[:data] << [climate_zone, building_type, template, "Error"]
            next
          end
          
          # Get floor area from the model, everything else has to come from the results file
          floor_area = OpenStudio::convert(model.building.get.floorArea, "m^2", "ft^2").get

          sql_file = OpenStudio::SqlFile.new("#{pb_dir}/#{file_prefix}out.sql")

          interior_lighting_electricity = OpenStudio::convert(sql_file.electricityInteriorLighting.get, "GJ", "kBtu").get / 1000
          exterior_lighting_electricity = OpenStudio::convert(sql_file.electricityExteriorLighting.get, "GJ", "kBtu").get / 1000
          interior_equipment_electricity = OpenStudio::convert(sql_file.electricityInteriorEquipment.get, "GJ", "kBtu").get / 1000
          exterior_equipment_electricity = OpenStudio::convert(sql_file.electricityExteriorEquipment.get, "GJ", "kBtu").get / 1000
          heating_electricity = OpenStudio::convert(sql_file.electricityHeating.get, "GJ", "kBtu").get / 1000
          cooling_electricity = OpenStudio::convert(sql_file.electricityCooling.get, "GJ", "kBtu").get / 1000
          service_water_heating_electricity = OpenStudio::convert(sql_file.electricityWaterSystems.get, "GJ", "kBtu").get / 1000
          fan_electricity = OpenStudio::convert(sql_file.electricityFans.get, "GJ", "kBtu").get / 1000
          pump_electricity = OpenStudio::convert(sql_file.electricityPumps.get, "GJ", "kBtu").get / 1000
          heat_recovery_electricity = OpenStudio::convert(sql_file.electricityHeatRecovery.get, "GJ", "kBtu").get / 1000
          heat_rejection_electricity = OpenStudio::convert(sql_file.electricityHeatRejection.get, "GJ", "kBtu").get / 1000
          humidification_electricity = OpenStudio::convert(sql_file.electricityHumidification.get, "GJ", "kBtu").get / 1000
          refrigeration_electricity = OpenStudio::convert(sql_file.electricityRefrigeration.get, "GJ", "kBtu").get / 1000
          generated_electricity = OpenStudio::convert(sql_file.electricityGenerators.get, "GJ", "kBtu").get / 1000

          total_site_electricity =
            interior_lighting_electricity +
            exterior_lighting_electricity +
            interior_equipment_electricity +
            exterior_equipment_electricity +
            heating_electricity +
            cooling_electricity +
            service_water_heating_electricity +
            fan_electricity +
            pump_electricity +
            heat_recovery_electricity +
            heat_rejection_electricity +
            humidification_electricity +
            refrigeration_electricity

          net_site_electricity =
            total_site_electricity -
            generated_electricity
          
          interior_equipment_gas = OpenStudio::convert(sql_file.naturalGasInteriorEquipment.get, "GJ", "kBtu").get / 1000
          exterior_equipment_gas = OpenStudio::convert(sql_file.naturalGasExteriorEquipment.get, "GJ", "kBtu").get / 1000
          heating_gas = OpenStudio::convert(sql_file.naturalGasHeating.get, "GJ", "kBtu").get / 1000
          service_water_heating_gas = OpenStudio::convert(sql_file.naturalGasWaterSystems.get, "GJ", "kBtu").get / 1000

          total_gas =
            interior_equipment_gas +
            exterior_equipment_gas +
            heating_gas +
            service_water_heating_gas

          interior_equipment_other_fuel = OpenStudio::convert(sql_file.otherFuelInteriorEquipment.get, "GJ", "kBtu").get / 1000
          exterior_equipment_other_fuel = OpenStudio::convert(sql_file.otherFuelExteriorEquipment.get, "GJ", "kBtu").get / 1000
          heating_other_fuel = OpenStudio::convert(sql_file.otherFuelHeating.get, "GJ", "kBtu").get / 1000
          service_water_heating_other_fuel = OpenStudio::convert(sql_file.otherFuelWaterSystems.get, "GJ", "kBtu").get / 1000

          total_other_fuel =
            interior_equipment_other_fuel +
            exterior_equipment_other_fuel +
            heating_other_fuel +
            service_water_heating_other_fuel
          
          district_hot_water_heating = OpenStudio::convert(sql_file.districtHeatingHeating.get, "GJ", "kBtu").get / 1000
          district_hot_water_service_hot_water = OpenStudio::convert(sql_file.districtHeatingWaterSystems.get, "GJ", "kBtu").get / 1000
          district_chilled_water = OpenStudio::convert(sql_file.districtCoolingCooling.get, "GJ", "kBtu").get / 1000

          interior_equipment_water = OpenStudio::convert(sql_file.waterInteriorEquipment.get, "m^3", "ft^3").get
          exterior_equipment_water = OpenStudio::convert(sql_file.waterExteriorEquipment.get, "m^3", "ft^3").get
          service_water = OpenStudio::convert(sql_file.waterWaterSystems.get, "m^3", "ft^3").get 
          cooling_water = OpenStudio::convert(sql_file.waterCooling.get, "m^3", "ft^3").get
          heating_water = OpenStudio::convert(sql_file.waterHeating.get, "m^3", "ft^3").get
          humidification_water = OpenStudio::convert(sql_file.waterHumidification.get, "m^3", "ft^3").get
          collected_water = OpenStudio::convert(sql_file.waterGenerators.get, "m^3", "ft^3").get

          total_water =
            interior_equipment_water +
            exterior_equipment_water +
            service_water +
            cooling_water +
            heating_water +
            humidification_water

          net_water =
            total_water -
            collected_water


          peak_electricity_Jan = 0.0
          peak_electricity_Feb = 0.0
          peak_electricity_Mar = 0.0
          peak_electricity_Apr = 0.0
          peak_electricity_May = 0.0
          peak_electricity_Jun = 0.0
          peak_electricity_Jul = 0.0
          peak_electricity_Aug = 0.0
          peak_electricity_Sep = 0.0
          peak_electricity_Oct = 0.0
          peak_electricity_Nov = 0.0
          peak_electricity_Dec = 0.0

          # peak values by fuel are not available via the SDK and need to be extracted from the time series
          # Get the weather file run period (as opposed to design day run period)
          if sql_file.hoursSimulated.get == 8760
            env_pd = sql_file.availableEnvPeriods[0]
            elec_ts = sql_file.timeSeries(env_pd, "Hourly", "Electricity:Facility")
            if elec_ts.length > 0
              elec_ts = elec_ts[0]
              year = elec_ts.firstReportDateTime.date.assumedBaseYear

              elec_ts_Jan = elec_ts.values(OpenStudio::DateTime.new(OpenStudio::Date.new(OpenStudio::MonthOfYear.new("Jan"), 1, year), OpenStudio::Time.new(0,1)),
                                           OpenStudio::DateTime.new(OpenStudio::Date.new(OpenStudio::MonthOfYear.new("Feb"), 1, year), OpenStudio::Time.new(0,0)))
              for i in 0 .. elec_ts_Jan.length-1 do 
                if elec_ts_Jan[i] > peak_electricity_Jan
                  peak_electricity_Jan = elec_ts_Jan[i]
                end
              end # for i

              peak_electricity_Jan = OpenStudio::convert(peak_electricity_Jan, elec_ts.units, "kBtu").get / 1000          
            end # if elec_ts.length > 0
          end # if sql_file.hoursSimulated == 8760                                                                                                     

          results_table[:data] << [
            climate_zone,
            building_type,
            template,

            "Success",
            
            floor_area,

            total_site_electricity,
            net_site_electricity,
            total_gas,

            total_other_fuel,
            total_water,
            net_water,
            
            interior_lighting_electricity,
            exterior_lighting_electricity,
            interior_equipment_electricity,
            exterior_equipment_electricity,
            heating_electricity,
            cooling_electricity,
            service_water_heating_electricity,
            fan_electricity,
            pump_electricity,
            heat_recovery_electricity,
            heat_rejection_electricity,
            humidification_electricity,
            refrigeration_electricity,
            generated_electricity,
            
            interior_equipment_gas,
            exterior_equipment_gas,
            heating_gas,
            service_water_heating_gas,
            
            interior_equipment_other_fuel,
            exterior_equipment_other_fuel,
            heating_other_fuel,
            service_water_heating_other_fuel,
            
            district_hot_water_heating,
            district_hot_water_service_hot_water,
            district_chilled_water,
            
            interior_equipment_water,
            exterior_equipment_water,
            service_water,
            cooling_water,
            heating_water,
            humidification_water,
            collected_water,
            
            peak_electricity_Jan,
            peak_electricity_Feb,
            peak_electricity_Mar,
            peak_electricity_Apr,
            peak_electricity_May,
            peak_electricity_Jun,
            peak_electricity_Jul,
            peak_electricity_Aug,
            peak_electricity_Sep,
            peak_electricity_Oct,
            peak_electricity_Nov,
            peak_electricity_Dec
          ]

        end # @climate_zone_chs.each
      end # @template_chs.each
    end # @building_type_chs.each
    
    @runner.registerInfo("#{results_table}")

    book = OsLib_Reporting.create_xls()
    OsLib_Reporting.write_xls(results_table, book)
    OsLib_Reporting.save_xls(book, "#{pb_dir}/PROTOTYPE_BLDGS.xlsx")
=end
    log_msgs

    @runner.registerInfo("And we are done!")
    return true

  end # run
  

  # Get all the log messages and put into output
  # for users to see.
  def log_msgs
    @msg_log.logMessages.each do |msg|
      # DLM: you can filter on log channel here for now
      if /openstudio.*/.match(msg.logChannel) #/openstudio\.model\..*/
        # Skip certain messages that are irrelevant/misleading
        next if msg.logMessage.include?("Skipping layer") || # Annoying/bogus "Skipping layer" warnings
            msg.logChannel.include?("runmanager") || # RunManager messages
            msg.logChannel.include?("setFileExtension") || # .ddy extension unexpected
            msg.logChannel.include?("Translator") || # Forward translator and geometry translator
            msg.logMessage.include?("UseWeatherFile") # 'UseWeatherFile' is not yet a supported option for YearDescription
            
        # Report the message in the correct way
        if msg.logLevel == OpenStudio::Info
          @runner.registerInfo(msg.logMessage)
        elsif msg.logLevel == OpenStudio::Warn
          @runner.registerWarning("[#{msg.logChannel}] #{msg.logMessage}")
        elsif msg.logLevel == OpenStudio::Error
          @runner.registerError("[#{msg.logChannel}] #{msg.logMessage}")
        elsif msg.logLevel == OpenStudio::Debug && @debug
          @runner.registerInfo("DEBUG - #{msg.logMessage}")
        end
      end
    end
    @runner.registerInfo("Total Time = #{(Time.new - @start_time).round}sec.")
  end

end # log_msgs

# register the measure to be used by the application
CreateAllDOEPrototypeBuildings.new.registerWithApplication
