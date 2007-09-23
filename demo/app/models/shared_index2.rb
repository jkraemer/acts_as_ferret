class SharedIndex2 < ActiveRecord::Base
  acts_as_ferret( { :fields       => { :name => { :store => :yes } }, 
                    :single_index => true, 
                    :remote       => ENV['AAF_REMOTE'] == 'true' }, 
                  { :default_field => SharedIndex1::DEFAULT_FIELDS } )
end
