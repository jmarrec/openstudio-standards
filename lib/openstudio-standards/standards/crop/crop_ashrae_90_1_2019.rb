require_relative 'crop_common'
require_relative 'crop_proposed'

# CROP standard for the proposed model on the 90.1-2019 basis: the stock class plus the CROP
# steps for both passes and for the proposed pass. It keeps the stock template and data.
class CropASHRAE9012019 < ASHRAE9012019
  register_standard 'CROP 90.1-2019'

  include CropCommon
  include CropProposed
end
