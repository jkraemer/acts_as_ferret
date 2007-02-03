module ActsAsFerret

  # base class for local and remote indexes
  class AbstractIndex

    attr_reader :aaf_configuration
    attr_reader :logger
    def initialize(aaf_configuration)
      @aaf_configuration = aaf_configuration
      @logger = Logger.new("#{RAILS_ROOT}/log/ferret_index.log")
    end
    
  end
end
