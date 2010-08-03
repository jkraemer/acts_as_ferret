require 'acts_as_ferret'

# load config/aaf.rb
config.to_prepare { ActsAsFerret::load_config }
