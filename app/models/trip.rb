class Trip < ActiveRecord::Base
  belongs_to :provider
  belongs_to :run

end
