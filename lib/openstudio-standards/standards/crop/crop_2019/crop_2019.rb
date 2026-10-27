# CROP standard on the 90.1-PRM-2019 basis. It owns the baseline and proposed rules
# and the PRM hooks, and it loads no standards data. The ACM overlay is a subclass.
class CROP2019 < Standard
  register_standard 'CROP 2019'

  def initialize
    super()
    @template = 'CROP 2019'
    @standards_data = {}
  end
end
