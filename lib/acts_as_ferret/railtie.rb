require 'acts_as_ferret'
require 'rails'

module ActsAsFerret
  
  class Railtie < Rails::Railtie
        
    config.to_prepare { ActsAsFerret::load_config }
    
  end
  
end