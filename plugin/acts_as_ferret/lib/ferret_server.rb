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
    def initialize(config)
#      @indexes = Hash.new
#      @index_config = config[:indexes]
#      config[:indexes].each_pair do |name, config|
#        @indexes[name] = init_index(name)
#        puts "initialized index #{config[:path]}"
#      end
    end

    # TODO queueing of requests goes here!
    # Later: separate writing/reading requests for parallelization?
    def method_missing(name, *args)
      clazz = args.unshift.constantize
      clazz.send name, args
    end

    protected 
    def log(index_name, msg)
      puts "[#{index_name.to_s}] #{msg}"
    end
  end

end
