require 'date'

# Winter solar cooling design day for hot climates, added to the proposed model before sizing.
module CropWinterSolarDesignDay
  WINTER_SOLAR_DESIGN_DAY_CLIMATE_ZONES = ['0A', '0B', '1A', '1B', '2A', '2B'].freeze
  WINTER_SOLAR_DESIGN_DAY_NAME = '179D hot-climate winter solar cooling design day'.freeze

  # Adds the winter EPW day with the highest exterior-window solar exposure.
  def model_add_hot_climate_winter_solar_design_day(model, climate_zone)
    return unless WINTER_SOLAR_DESIGN_DAY_CLIMATE_ZONES.include?(climate_zone.to_s.split('-')[-1].to_s.upcase)
    return if model.getDesignDays.any? { |design_day| design_day.nameString == WINTER_SOLAR_DESIGN_DAY_NAME }
    return unless model.getWeatherFile.path.is_initialized

    epw_path = model.getWeatherFile.path.get.to_s
    return unless File.file?(epw_path)

    window_planes = exterior_window_planes(model)
    return if window_planes.empty?

    location, records = read_epw_records(epw_path)
    selected_day = winter_window_solar_day(location, records, window_planes)
    return if selected_day.nil?

    add_winter_solar_design_day(model, location, selected_day)
  rescue StandardError => e
    OpenStudio.logFree(OpenStudio::Warn, 'crop.Model',
                       "Could not add winter solar cooling design day: #{e.message}")
  end

  def exterior_window_planes(model)
    model.getSubSurfaces.filter_map do |sub_surface|
      parent_surface = sub_surface.surface
      next unless parent_surface.is_initialized

      surface = parent_surface.get
      next unless sub_surface.subSurfaceType.downcase.include?('window')
      next unless surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'Outdoors'

      [sub_surface.netArea, surface.azimuth, surface.tilt]
    end
  end

  def read_epw_records(epw_path)
    lines = File.foreach(epw_path)
    location = parse_epw_location(lines.next)
    7.times { lines.next }
    records = lines.filter_map { |line| parse_epw_record(line) }
    [location, records]
  end

  def parse_epw_location(line)
    fields = line.split(',')
    {
      latitude_rad: fields[6].to_f * Math::PI / 180.0,
      latitude_deg: fields[6].to_f,
      longitude_deg: fields[7].to_f,
      time_zone: fields[8].to_f,
    }
  end

  def parse_epw_record(line)
    fields = line.split(',')
    return nil if fields.size < 22

    month = fields[1].to_i
    day = fields[2].to_i
    hour = fields[3].to_i
    return nil unless month.between?(1, 12) && day.between?(1, 31) && hour.between?(1, 24)

    {
      month:,
      day:,
      hour:,
      dry_bulb_c: fields[6].to_f,
      dew_point_c: fields[7].to_f,
      pressure_pa: fields[9].to_f,
      direct_normal_w_per_m2: fields[14].to_f,
      diffuse_horizontal_w_per_m2: fields[15].to_f,
      wind_direction_deg: fields[20].to_f,
      wind_speed_m_per_s: fields[21].to_f,
    }
  end

  def winter_window_solar_day(location, records, window_planes)
    winter_months = location[:latitude_deg].negative? ? [4, 5, 6, 7, 8, 9] : [10, 11, 12, 1, 2, 3]
    day_scores = Hash.new(0.0)

    records.each do |record|
      next unless winter_months.include?(record[:month])

      day_scores[[record[:month], record[:day]]] += window_solar_score(location, record, window_planes)
    end

    date = day_scores.max_by { |_day, score| score }&.first
    return nil if date.nil?

    selected_records = records.select { |record| record[:month] == date[0] && record[:day] == date[1] }
    selected_records.size == 24 ? selected_records : nil
  end

  def window_solar_score(location, record, window_planes)
    direct_normal = record[:direct_normal_w_per_m2]
    diffuse_horizontal = record[:diffuse_horizontal_w_per_m2]
    return 0.0 if direct_normal <= 0.0 && diffuse_horizontal <= 0.0

    hour_angle, declination = epw_solar_angles(record[:month], record[:day], record[:hour] - 0.5,
                                               location[:longitude_deg], location[:time_zone])
    sin_altitude = (Math.sin(location[:latitude_rad]) * Math.sin(declination)) +
                   (Math.cos(location[:latitude_rad]) * Math.cos(declination) * Math.cos(hour_angle))
    return 0.0 if sin_altitude <= 0.0

    altitude = Math.asin(sin_altitude)
    solar_azimuth = Math.atan2(Math.sin(hour_angle),
                               (Math.cos(hour_angle) * Math.sin(location[:latitude_rad])) -
                               (Math.tan(declination) * Math.cos(location[:latitude_rad]))) + Math::PI

    window_planes.sum do |area, azimuth, tilt|
      cosine_incidence = (Math.sin(altitude) * Math.cos(tilt)) +
                         (Math.cos(altitude) * Math.sin(tilt) * Math.cos(solar_azimuth - azimuth))
      (direct_normal * [cosine_incidence, 0.0].max * area) +
        (diffuse_horizontal * (1.0 + Math.cos(tilt)) * 0.5 * area)
    end
  end

  def epw_solar_angles(month, day, local_hour, longitude_deg, time_zone)
    day_of_year = Date.new(2000, month, day).yday
    gamma = 2.0 * Math::PI * (day_of_year - 1) / 365.0
    declination = [0.006918, -(0.399912 * Math.cos(gamma)), 0.070257 * Math.sin(gamma),
                   -(0.006758 * Math.cos(2.0 * gamma)), 0.000907 * Math.sin(2.0 * gamma),
                   -(0.002697 * Math.cos(3.0 * gamma)), 0.00148 * Math.sin(3.0 * gamma)].sum
    equation_of_time = 229.18 * (0.000075 + (0.001868 * Math.cos(gamma)) - (0.032077 * Math.sin(gamma)) -
                                 (0.014615 * Math.cos(2.0 * gamma)) - (0.040849 * Math.sin(2.0 * gamma)))
    minutes = (local_hour * 60.0) + equation_of_time + (4.0 * (longitude_deg - (15.0 * time_zone))) - 720.0
    [minutes * Math::PI / 180.0, declination]
  end

  def add_winter_solar_design_day(model, _location, records)
    max_dry_bulb = records.map { |record| record[:dry_bulb_c] }.max
    min_dry_bulb = records.map { |record| record[:dry_bulb_c] }.min
    dry_bulb_range = max_dry_bulb - min_dry_bulb
    max_record = records.max_by { |record| record[:dry_bulb_c] }

    design_day = OpenStudio::Model::DesignDay.new(model)
    design_day.setName(WINTER_SOLAR_DESIGN_DAY_NAME)
    design_day.setMonth(records.first[:month])
    design_day.setDayOfMonth(records.first[:day])
    design_day.setDayType('SummerDesignDay')
    design_day.setMaximumDryBulbTemperature(max_dry_bulb)
    design_day.setDailyDryBulbTemperatureRange(dry_bulb_range)
    design_day.setDryBulbTemperatureRangeModifierType('MultiplierSchedule')
    design_day.setDryBulbTemperatureRangeModifierDaySchedule(epw_day_schedule(model, 'Drybulb Range Modifier', records) do |record|
      dry_bulb_range.positive? ? (max_dry_bulb - record[:dry_bulb_c]) / dry_bulb_range : 0.0
    end)
    design_day.setHumidityConditionType('DewPoint')
    design_day.setWetBulbOrDewPointAtMaximumDryBulb(max_record[:dew_point_c])
    design_day.setBarometricPressure(max_record[:pressure_pa])
    design_day.setWindSpeed(max_record[:wind_speed_m_per_s])
    design_day.setWindDirection(max_record[:wind_direction_deg])
    design_day.setRainIndicator(false)
    design_day.setSnowIndicator(false)
    design_day.setDaylightSavingTimeIndicator(false)
    design_day.setSolarModelIndicator('Schedule')
    design_day.setBeamSolarDaySchedule(epw_day_schedule(model, 'Beam Solar', records) { |record| record[:direct_normal_w_per_m2] })
    design_day.setDiffuseSolarDaySchedule(epw_day_schedule(model, 'Diffuse Solar', records) { |record| record[:diffuse_horizontal_w_per_m2] })

    OpenStudio.logFree(OpenStudio::Info, 'crop.Model',
                       "Added #{WINTER_SOLAR_DESIGN_DAY_NAME} for #{records.first[:month]}/#{records.first[:day]}.")
  end

  def epw_day_schedule(model, label, records)
    schedule = OpenStudio::Model::ScheduleDay.new(model)
    schedule.setName("#{WINTER_SOLAR_DESIGN_DAY_NAME} #{label}")
    records.sort_by { |record| record[:hour] }.each do |record|
      schedule.addValue(OpenStudio::Time.new(0, record[:hour], 0, 0), yield(record))
    end
    schedule
  end

  module_function :model_add_hot_climate_winter_solar_design_day,
                  :exterior_window_planes,
                  :read_epw_records,
                  :parse_epw_location,
                  :parse_epw_record,
                  :winter_window_solar_day,
                  :window_solar_score,
                  :epw_solar_angles,
                  :add_winter_solar_design_day,
                  :epw_day_schedule
end
