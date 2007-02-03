class SharedIndex1 < ActiveRecord::Base
  acts_as_ferret :single_index => true, :remote => ENV['AAF_REMOTE']
end
