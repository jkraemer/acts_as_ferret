require 'acts_as_ferret'
require 'rails'

module ActsAsFerret
  
  class Railtie < Rails::Railtie
        
    rake_tasks do
      load File.join(File.dirname(__FILE__), '../../tasks/ferret.rake')
    end
      
    config.to_prepare { ActsAsFerret::load_config }
    
  end
  
end