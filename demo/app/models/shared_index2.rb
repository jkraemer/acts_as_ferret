class SharedIndex2 < ActiveRecord::Base
  acts_as_ferret :single_index => true
end
