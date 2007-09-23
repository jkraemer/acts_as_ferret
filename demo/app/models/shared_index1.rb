class SharedIndex1 < ActiveRecord::Base
  # default field list for all classes sharing the index
  DEFAULT_FIELDS = [ :name ]
  acts_as_ferret( :fields       => { :name => { :store => :yes } }, 
                  :single_index => true, 
                  :remote       => ENV['AAF_REMOTE'] == 'true',
                  :ferret       => { :default_field => DEFAULT_FIELDS } 
                )
end
