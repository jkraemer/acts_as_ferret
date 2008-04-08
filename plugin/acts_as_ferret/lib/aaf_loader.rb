# Helper to avoid class reloading issues when using shared index declarations
# outside of model classes (RAILS_ROOT/config/aaf.rb).
#
# Include this module in your ApplicationController to make sure your
# config/aaf.rb gets reloaded on every request in development mode.
#
module AafLoader
  def self.included(target)
    ActsAsFerret::load_config
  end
end
