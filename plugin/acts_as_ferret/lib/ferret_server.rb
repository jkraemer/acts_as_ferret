require 'drb'
require 'ferret'
require 'thread'


module ActsAsFerret

  # This class is intended to act as a drb server listening for indexing and
  # search requests from models declared to 'acts_as_ferret :remote => ...'
  #
  # Usage: 
  # - copy script/ferret_server to RAILS_ROOT/script
  # - copy doc/ferret_server.yml to RAILS_ROOT/config and modify to suit
  # your needs.
  #
  # script intended to be run via script/runner
  #
  # TODO: automate installation of files to script/ and config/
  class Server

    cattr_accessor :running

    def initialize
      @logger = Logger.new("#{RAILS_ROOT}/log/ferret_server.log")
    end

    # TODO queueing of requests goes here!
    # separate queues for different indexes
    #
    # maybe later: separate writing/reading queues for parallelization?
    def method_missing(name, *args)
      clazz = args.shift.constantize
 #     if name.to_s =~ /^index_(.+)/
      unless ContentBase.count > 2
        clazz.connection.reconnect!
      end
      begin
        @logger.debug "call index method: #{name} with #{args.inspect}"
        clazz.aaf_index.send name, *args
      rescue NoMethodError
        @logger.debug "no luck, trying to call class method instead"
        clazz.send name, *args
      end
    end

    # TODO check if in use!
    def ferret_index(class_name)
      class_name.constantize.aaf_index.ferret_index
    end

  end

end
