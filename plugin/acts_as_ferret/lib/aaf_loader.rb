# Helper to avoid class reloading issues when using shared index declarations
# outside of model classes (RAILS_ROOT/config/aaf.rb).
#
# Include this module in your ApplicationController to make sure your
# config/aaf.rb gets reloaded on every request in development mode.
#
module ActsAsFerret
  module AafLoader
    def self.included(target)
      target.before_filter :load_aaf_config
    end

    def load_aaf_config
      ActsAsFerret::load_config
    end
  end
end
