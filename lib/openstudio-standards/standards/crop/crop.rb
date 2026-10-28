# Entry file for the CROP standards. The BEM repo copies these files into one flat folder
# and loads them in file-name order; this file loads the rest in dependency order.
require_relative 'crop_common'
require_relative 'crop_proposed'
require_relative 'crop_baseline'
require_relative 'crop_building_type_map'
require_relative 'crop_winter_solar_design_day'
require_relative 'crop_ashrae_90_1_2019'
require_relative 'crop_ashrae_90_1_prm_2019'
require_relative 'crop_openstudio_standards_patches'
