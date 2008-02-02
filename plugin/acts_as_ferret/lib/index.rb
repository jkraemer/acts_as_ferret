module ActsAsFerret

  # base class for local and remote indexes
  class AbstractIndex

    attr_reader :aaf_configuration
    attr_accessor :logger
    def initialize(aaf_configuration)
      @aaf_configuration = aaf_configuration
      @logger = Logger.new("#{RAILS_ROOT}/log/ferret_index.log")
      @logger.level = ActiveRecord::Base.logger.level
    end
    
  end

end
