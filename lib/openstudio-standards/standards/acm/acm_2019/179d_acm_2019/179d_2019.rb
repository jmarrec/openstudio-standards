# 179D standard on the 90.1-2019 and 90.1-PRM-2019 basis. It owns the 179D rules
# and the PRM hooks, and it loads no standards data. The ACM overlay is a subclass.
class Standard179d2019 < Standard
  register_standard '179D 2019'

  def initialize
    super()
    @template = '179D 2019'
    @standards_data = {}
  end
end
