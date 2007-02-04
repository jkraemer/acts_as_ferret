require 'drb'
require 'thread'
require 'yaml'
require 'erb'


module ActsAsFerret

module Remote

  module Config
    class << self
      DEFAULTS = {
        'host' => 'localhost',
        'port' => '9009'
      }
      # reads connection settings from config file
      def load(file)
        config = DEFAULTS.merge(YAML.load(ERB.new(IO.read(file)).result))
        "druby://#{config['host']}:#{config['port']}"
      end
    end
  end

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

    def self.start(uri = nil)
      uri ||= ActsAsFerret::Remote::Config.load("#{RAILS_ROOT}/config/ferret_server.yml")
      DRb.start_service(uri, ActsAsFerret::Remote::Server.new)
      self.running = true
    end

    def initialize
      @logger = Logger.new("#{RAILS_ROOT}/log/ferret_server.log")
    end

    # TODO queueing of requests goes here!
    #
    # maybe separate writing/reading requests for better parallelization?
    # otherwise a long-taking index rebuild would even hold searches on other
    # indexes...
    #
    # in theory, we would need no queueing at all (possible Rails-threading
    # problems set aside... - maybe just try to get away with that?)
    # ActiveRecord::Base.allow_concurrency ?
    def method_missing(name, *args)
      clazz = args.shift.constantize
      begin
        @logger.debug "call index method: #{name} with #{args.inspect}"
        clazz.aaf_index.send name, *args
      rescue NoMethodError
        @logger.debug "no luck, trying to call class method instead"
        clazz.send name, *args
      end
    rescue
      puts "####### #{$!}\n#{$!.backtrace.join '\n'}"
    end

    # TODO check if in use!
    def ferret_index(class_name)
      class_name.constantize.aaf_index.ferret_index
    end

    # the main loop taking stuff from the queue and running it...
    #def run
    #end

  end
end
end
