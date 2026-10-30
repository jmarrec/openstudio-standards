# CROP overrides for openstudio-standards 0.8.2 bugs. Remove each one when the gem has the fix.
#
# Typical service water heating (SWH): upstream puts the zone multiplier in the typical SWH
# peak flow, and EnergyPlus applies the zone multiplier again. This wrapper calls the upstream
# method, then removes the zone multiplier from the peak flows. The water heaters keep their
# size, because upstream sizes them for the whole building.
module OpenstudioStandards
  module ServiceWaterHeating
    class << self
      unless method_defined?(:create_typical_service_water_heating_without_crop_fix)
        alias_method :create_typical_service_water_heating_without_crop_fix, :create_typical_service_water_heating
      end

      def create_typical_service_water_heating(model, **kwargs)
        swh_loops = create_typical_service_water_heating_without_crop_fix(model, **kwargs)
        remove_zone_multiplier_from_typical_swh_flows_crop(model)
        swh_loops
      end

      # Divides a peak flow by its zone multiplier only if it equals the typical
      # per-space flow times the multiplier. Fixed flows that upstream does not
      # multiply, and flows that are already per space, do not change.
      def remove_zone_multiplier_from_typical_swh_flows_crop(model)
        swh_dir = File.dirname(method(:create_water_use).source_location.first)
        data = JSON.parse(File.read("#{swh_dir}/data/typical_water_use_equipment.json"), symbolize_names: true)
        done = {}
        model.getWaterUseEquipments.each do |equipment|
          definition = equipment.waterUseEquipmentDefinition
          next if done[definition.handle.to_s]

          per_space_flows = typical_per_space_flows_gal_per_hr_crop(equipment, data)
          next if per_space_flows.empty?

          multiplier = equipment.space.get.multiplier
          flow_gal_per_hr = OpenStudio.convert(definition.peakFlowRate, 'm^3/s', 'gal/hr').get
          next unless per_space_flows.any? { |flow| (flow_gal_per_hr - (flow * multiplier)).abs <= 1e-6 * flow_gal_per_hr }

          definition.setPeakFlowRate(definition.peakFlowRate / multiplier)
          gpm = OpenStudio.convert(definition.peakFlowRate, 'm^3/s', 'gal/min').get.round(2)
          [definition, equipment].each { |obj| obj.setName(obj.nameString.sub(/[\d.]+gpm/, "#{gpm}gpm")) }
          done[definition.handle.to_s] = true
        end
      end

      # Typical peak flows (gal/hr) for one space, for the equipment rows that
      # upstream multiplies by the zone multiplier (per-area flows and One Per Unit).
      def typical_per_space_flows_gal_per_hr_crop(equipment, data)
        return [] unless equipment.space.is_initialized

        space = equipment.space.get
        return [] if space.multiplier <= 1 || !space.spaceType.is_initialized
        return [] if space.hasAdditionalProperties && space.additionalProperties.hasFeature('num_units')

        space_type = space.spaceType.get
        return [] unless space_type.standardsBuildingType.is_initialized && space_type.standardsSpaceType.is_initialized

        area_ft2 = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get
        rows = data[:space_types].select do |row|
          row[:building_type] == space_type.standardsBuildingType.get && row[:space_type] == space_type.standardsSpaceType.get
        end
        rows.flat_map { |row| row[:water_use_equipment] }.filter_map do |w|
          if w[:peak_flow_rate].to_f.zero? && w[:peak_flow_rate_per_area].to_f.positive?
            w[:peak_flow_rate_per_area].to_f * area_ft2
          elsif w[:loop_type] == 'One Per Unit' && w[:peak_flow_rate].to_f.positive?
            w[:peak_flow_rate].to_f
          end
        end
      end
    end
  end
end

# Daylighted areas: upstream joins the sidelit polygons in pointer order. When the union has
# an inner hole (windows on all four walls), its fallback drops the first polygon, so the area
# changes from run to run and can be larger than the floor. This wrapper keeps the upstream
# polygons and replaces the three areas with an exact calculation that does not use the order.
class Standard
  unless method_defined?(:space_daylighted_areas_without_crop_fix)
    alias space_daylighted_areas_without_crop_fix space_daylighted_areas
    alias space_join_polygons_without_crop_fix space_join_polygons
  end

  def space_join_polygons(space, polygons, tol, name)
    @crop_daylight_polygons[name] = polygons if @crop_daylight_polygons
    space_join_polygons_without_crop_fix(space, polygons, tol, name)
  end

  def space_daylighted_areas(space, *args)
    @crop_daylight_polygons = {}
    result = space_daylighted_areas_without_crop_fix(space, *args)
    polygons = @crop_daylight_polygons
    return result unless polygons.key?('floor_polygons')

    result.merge(crop_daylighted_areas(*polygons.values_at('floor_polygons', 'toplit_polygons', 'pri_sidelit_polygons', 'sec_sidelit_polygons')))
  ensure
    @crop_daylight_polygons = nil
  end

  # Areas (m2) on the floor: toplit, then primary minus toplit, then secondary minus both.
  # Cuts the plane into vertical slabs at every vertex and edge crossing. No edges cross
  # inside a slab, so each strip between two edges is a trapezoid with one classification.
  def crop_daylighted_areas(floor, toplit, primary, secondary)
    sets = [floor, toplit, primary, secondary].map { |polys| (polys || []).map { |poly| poly.map { |pt| [pt.x, pt.y] } } }
    edges = sets.flatten(1).flat_map { |poly| poly.each_index.map { |i| [poly[i - 1], poly[i]] } }
    xs = edges.flatten(1).map(&:first)
    edges.combination(2) do |a, b|
      x = crop_edge_crossing_x(a, b)
      xs << x if x
    end
    areas = [0.0, 0.0, 0.0]
    xs.uniq.sort.each_cons(2) do |x0, x1|
      next if x1 - x0 < 1e-6

      xm = (x0 + x1) / 2.0
      ys = edges.filter_map { |(ax, ay), (bx, by)| ay + ((by - ay) * (xm - ax) / (bx - ax)) if (ax < xm) != (bx < xm) }.sort
      ys.each_cons(2) do |y0, y1|
        next if y1 - y0 < 1e-9

        pt = [xm, (y0 + y1) / 2.0]
        inside = ->(polys) { polys.any? { |poly| crop_point_in_polygon?(pt, poly) } }
        next unless inside.call(sets[0])

        k = (1..3).find { |i| inside.call(sets[i]) }
        areas[k - 1] += (x1 - x0) * (y1 - y0) if k
      end
    end
    { 'toplighted_area' => areas[0], 'primary_sidelighted_area' => areas[1], 'secondary_sidelighted_area' => areas[2] }
  end

  # The x of the point where two segments cross, or nil if they are parallel or do not touch.
  def crop_edge_crossing_x(edge_a, edge_b)
    (x1, y1), (x2, y2) = edge_a
    (x3, y3), (x4, y4) = edge_b
    d = ((x2 - x1) * (y4 - y3)) - ((y2 - y1) * (x4 - x3))
    return nil if d.abs < 1e-12

    t = (((x3 - x1) * (y4 - y3)) - ((y3 - y1) * (x4 - x3))) / d
    u = (((x3 - x1) * (y2 - y1)) - ((y3 - y1) * (x2 - x1))) / d
    return nil unless t.between?(0.0, 1.0) && u.between?(0.0, 1.0)

    x1 + (t * (x2 - x1))
  end

  # Even-odd test for a point [x, y] and a polygon given as [[x, y], ...].
  def crop_point_in_polygon?(point, poly)
    x, y = point
    inside = false
    poly.each_index do |i|
      xi, yi = poly[i]
      xj, yj = poly[i - 1]
      inside = !inside if ((yi > y) != (yj > y)) && (x < (((xj - xi) * (y - yi) / (yj - yi)) + xi))
    end
    inside
  end
end
