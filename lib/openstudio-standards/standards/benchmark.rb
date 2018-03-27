require 'json'
require 'benchmark'
require 'google_hash'

# Helper function to display a section break in terminal
def display_break(s)
  puts "\n"
  puts "="*80
  display_s = ""
  s.split("").each do |c|
    if c == " "
      display_s += " "*4
    else
      display_s += c.upcase + " "
    end
  end

  puts " "*((80-display_s.size) / 2) + display_s
  puts "="*80
end

# Method to search through a hash for an object that meets the
# desired search criteria, as passed via a hash.  If capacity is supplied,
# the object will only be returned if the specified capacity is between
# the minimum_capacity and maximum_capacity values.
#
#
# @param hash_of_objects [Hash] hash of objects to search through
# @param search_criteria [Hash] hash of search criteria
# @param capacity [Double] capacity of the object in question.  If capacity is supplied,
#   the objects will only be returned if the specified capacity is between
#   the minimum_capacity and maximum_capacity values.
# @return [Hash] Return tbe first matching object hash if successful, nil if not.
# @example Find the motor that meets these size criteria
#   search_criteria = {
#   'template' => template,
#   'number_of_poles' => 4.0,
#   'type' => 'Enclosed',
#   }
#   motor_properties = self.model.find_object(motors, search_criteria, 2.5)
def model_find_object(hash_of_objects, search_criteria, capacity = nil, date = nil)
  #    new_matching_objects = model_find_objects(self, hash_of_objects, search_criteria, capacity)

  if hash_of_objects.is_a?(Hash) and hash_of_objects.key?('table')
    hash_of_objects = hash_of_objects['table']
  end
  desired_object = nil
  search_criteria_matching_objects = []
  matching_objects = []

  # Compare each of the objects against the search criteria
  hash_of_objects.each do |object|
    meets_all_search_criteria = true
    search_criteria.each do |key, value|
      # Don't check non-existent search criteria
      next unless object.key?(key)
      # Stop as soon as one of the search criteria is not met
      # 'Any' is a special key that matches anything
      unless object[key] == value || object[key] == 'Any'
        meets_all_search_criteria = false
        break
      end
    end
    # Skip objects that don't meet all search criteria
    next unless meets_all_search_criteria
    # If made it here, object matches all search criteria
    search_criteria_matching_objects << object
  end

  # If capacity was specified, narrow down the matching objects
  if capacity.nil?
    matching_objects = search_criteria_matching_objects
  else
    # Round up if capacity is an integer
    if capacity == capacity.round
      capacity += (capacity * 0.01)
    end
    search_criteria_matching_objects.each do |object|
      # Skip objects that don't have fields for minimum_capacity and maximum_capacity
      next if !object.key?('minimum_capacity') || !object.key?('maximum_capacity')
      # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
      next if object['minimum_capacity'].nil? || object['maximum_capacity'].nil?
      # Skip objects whose the minimum capacity is below the specified capacity
      next if capacity <= object['minimum_capacity'].to_f
      # Skip objects whose max
      next if capacity > object['maximum_capacity'].to_f
      # Found a matching object
      matching_objects << object
    end
    # If no object was found, round the capacity down a little
    # to avoid issues where the number fell between the limits
    # in the json file.
    if matching_objects.size.zero?
      capacity *= 0.99
      search_criteria_matching_objects.each do |object|
        # Skip objects that don't have fields for minimum_capacity and maximum_capacity
        next if !object.key?('minimum_capacity') || !object.key?('maximum_capacity')
        # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
        next if object['minimum_capacity'].nil? || object['maximum_capacity'].nil?
        # Skip objects whose the minimum capacity is below the specified capacity
        next if capacity <= object['minimum_capacity'].to_f
        # Skip objects whose max
        next if capacity > object['maximum_capacity'].to_f
        # Found a matching object
        matching_objects << object
      end
    end
  end

  # If date was specified, narrow down the matching objects
  unless date.nil?
    date_matching_objects = []
    matching_objects.each do |object|
      # Skip objects that don't have fields for minimum_capacity and maximum_capacity
      next if !object.key?('start_date') || !object.key?('end_date')
      # Skip objects whose the start date is earlier than the specified date
      next if date <= Date.parse(object['start_date'])
      # Skip objects whose end date is beyond the specified date
      next if date > Date.parse(object['end_date'])
      # Found a matching object
      date_matching_objects << object
    end
    matching_objects = date_matching_objects
  end

  # Check the number of matching objects found
  if matching_objects.size.zero?
    desired_object = nil
    # OpenStudio::logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Find object search criteria returned no results. Search criteria: #{search_criteria}, capacity = #{capacity}.  Called from #{caller(0)[1]}")
  elsif matching_objects.size == 1
    desired_object = matching_objects[0]
  else
    desired_object = matching_objects[0]
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Find object search criteria returned #{matching_objects.size} results, the first one will be returned. Called from #{caller(0)[1]}. \n Search criteria: \n #{search_criteria}, capacity = #{capacity} \n  All results: \n #{matching_objects.join("\n")}")
  end

  return desired_object
end

standards_files = []
standards_files << 'OpenStudio_Standards_boilers.json'
standards_files << 'OpenStudio_Standards_chillers.json'
standards_files << 'OpenStudio_Standards_climate_zone_sets.json'
standards_files << 'OpenStudio_Standards_climate_zones.json'
standards_files << 'OpenStudio_Standards_construction_properties.json'
standards_files << 'OpenStudio_Standards_construction_sets.json'
standards_files << 'OpenStudio_Standards_constructions.json'
standards_files << 'OpenStudio_Standards_curves.json'
standards_files << 'OpenStudio_Standards_ground_temperatures.json'
standards_files << 'OpenStudio_Standards_heat_pumps_heating.json'
standards_files << 'OpenStudio_Standards_heat_pumps.json'
standards_files << 'OpenStudio_Standards_materials.json'
standards_files << 'OpenStudio_Standards_motors.json'
standards_files << 'OpenStudio_Standards_prototype_inputs.json'
standards_files << 'OpenStudio_Standards_schedules.json'
standards_files << 'OpenStudio_Standards_space_types.json'
standards_files << 'OpenStudio_Standards_templates.json'
standards_files << 'OpenStudio_Standards_unitary_acs.json'
standards_files << 'OpenStudio_Standards_heat_rejection.json'
standards_files << 'OpenStudio_Standards_exterior_lighting.json'
standards_files << 'OpenStudio_Standards_parking.json'
standards_files << 'OpenStudio_Standards_entryways.json'
standards_files << 'OpenStudio_Standards_necb_climate_zones.json'
standards_files << 'OpenStudio_Standards_necb_fdwr.json'
standards_files << 'OpenStudio_Standards_necb_hvac_system_selection_type.json'
standards_files << 'OpenStudio_Standards_necb_surface_conductances.json'
standards_files << 'OpenStudio_Standards_water_heaters.json'
standards_files << 'OpenStudio_Standards_economizers.json'
standards_files << 'OpenStudio_Standards_refrigerated_cases.json'
standards_files << 'OpenStudio_Standards_walkin_refrigeration.json'
standards_files << 'OpenStudio_Standards_refrigeration_compressors.json'

# standards_files << 'OpenStudio_Standards_unitary_hps.json'
# Combine the data from the JSON files into a single hash
top_dir = File.expand_path('../../..', File.dirname(__FILE__))
standards_data_dir = "#{top_dir}/data/standards"


###############################################################################
#            L O A D I N G     O N L Y     -     2 0     T I M E S
###############################################################################
display_break("loading only - 20 times")

# Load standards 20 times, as string and as symbols
Benchmark.bmbm do |bm|
  bm.report("Read Standards - strings:") {
    20.times do |i|
      standards_data = {}
      standards_files.sort.each do |standards_file|
        temp = ''
        File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
          temp = f.read
        end

        file_hash = JSON.parse(temp, :symbolize_name=>false)
        standards_data = standards_data.merge(file_hash)
      end
    end
  }

  bm.report("Read Standards - symbols:") {
    20.times do |i|
      standards_data = {}
      standards_files.sort.each do |standards_file|
        temp = ''
        File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
          temp = f.read
        end

        file_hash = JSON.parse(temp, :symbolize_names=>true)
        standards_data = standards_data.merge(file_hash)
      end
    end
 }
  bm.report("Read Standards - GoogleHashDenseRubyToRuby:") {
    20.times do |i|
      standards_data = {}
      standards_files.sort.each do |standards_file|
        temp = ''
        File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
          temp = f.read
        end

        file_hash = JSON.parse(temp, :symbolize_names=>true)
        standards_data = standards_data.merge(file_hash)
      end
      s = GoogleHashDenseRubyToRuby.new
      standards_data.each do |k, v|
        s[k] = v
      end
      standards_data = s
    end

  }
end



###############################################################################
#         S E A R C H I N G     O N L Y     -     1 0 0 0     T I M E S
###############################################################################
display_break("seaching only - 1000 times")

puts "\nLoading standards as string"
# Read as regular
standards_data = {}
standards_files.sort.each do |standards_file|
  temp = ''
  File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
    temp = f.read
  end

  file_hash = JSON.parse(temp)
  standards_data = standards_data.merge(file_hash)
end
puts "Searching strings hash 1000 times (benchmarked)\n"
Benchmark.bmbm do |bm|
  bm.report("Search Standards - strings:") {
    1000.times do |i|
      # populate search hash
      search_criteria = {
        'template' => '90.1-2013',
        'building_type' => 'Office',
        'space_type' => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data['space_types'], search_criteria)
    end
  }
end

# Read standards as symbols
puts "\nLoading standards as symbols"

standards_data = {}
standards_files.sort.each do |standards_file|
  temp = ''
  File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
    temp = f.read
  end

  file_hash = JSON.parse(temp, :symbolize_names=>true)
  standards_data = standards_data.merge(file_hash)
end

puts "Searching symbols hash 1000 times (benchmarked)\n"

Benchmark.bmbm do |bm|

  bm.report("Search Standards - symbols:") {
    1000.times do |i|

      # populate search hash
      search_criteria = {
        :template => '90.1-2013',
        :building_type => 'Office',
        :space_type => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data[:space_types], search_criteria)
    end
  }
end


# Read standards as Google hash
puts "\nLoading standards as GoogleHashDenseRubyToRuby"


# Read standards as symbols
standards_data = {}
standards_files.sort.each do |standards_file|
  temp = ''
  File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
    temp = f.read
  end

  file_hash = JSON.parse(temp, :symbolize_names=>true)
  standards_data = standards_data.merge(file_hash)
end
# Popuplate a google hash
s = GoogleHashDenseRubyToRuby.new
standards_data.each do |k, v|
  s[k] = v
end
standards_data = s

puts "Searching GoogleHashDenseRubyToRuby hash 1000 times (benchmarked)\n"

Benchmark.bmbm do |bm|

  bm.report("Search Standards - GoogleHashDenseRubyToRuby:") {
    1000.times do |i|

      # populate search hash
      search_criteria = {
        :template => '90.1-2013',
        :building_type => 'Office',
        :space_type => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data[:space_types], search_criteria)
    end
  }
end



###############################################################################
# L O A D I N G     O N C E   +   S E A R C H I N G     1 0 0 0     T I M E S
###############################################################################
display_break("Loading once + searching 1000 times")


Benchmark.bmbm do |bm|

  bm.report("Search Standards - strings:") {

    # Read as strings
    standards_data = {}
    standards_files.sort.each do |standards_file|
      temp = ''
      File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
        temp = f.read
      end

      file_hash = JSON.parse(temp)
      standards_data = standards_data.merge(file_hash)
    end

    # Search 1000 times
    1000.times do |i|
      # populate search hash
      search_criteria = {
        'template' => '90.1-2013',
        'building_type' => 'Office',
        'space_type' => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data['space_types'], search_criteria)
    end
  }


  bm.report("Search Standards - symbols:") {
    # Read standards as symbols
    standards_data = {}
    standards_files.sort.each do |standards_file|
      temp = ''
      File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
        temp = f.read
      end

      file_hash = JSON.parse(temp, :symbolize_names=>true)
      standards_data = standards_data.merge(file_hash)
    end

    # Search 1000 times
    1000.times do |i|

      # populate search hash
      search_criteria = {
        :template => '90.1-2013',
        :building_type => 'Office',
        :space_type => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data[:space_types], search_criteria)
    end
  }

  bm.report("Search Standards - GoogleHashDenseRubyToRuby:") {
    # Read standards as symbols
    standards_data = {}
    standards_files.sort.each do |standards_file|
      temp = ''
      File.open("#{standards_data_dir}/#{standards_file}", 'r:UTF-8') do |f|
        temp = f.read
      end

      file_hash = JSON.parse(temp, :symbolize_names=>true)
      standards_data = standards_data.merge(file_hash)
    end
    s = GoogleHashDenseRubyToRuby.new
    standards_data.each do |k, v|
      s[k] = v
    end
    standards_data = s

    # Search 1000 times
    1000.times do |i|

      # populate search hash
      search_criteria = {
        :template => '90.1-2013',
        :building_type => 'Office',
        :space_type => 'ClosedOffice'
      }
      # Lookup
      space_type_properties = model_find_object(standards_data[:space_types], search_criteria)
    end
  }

end
