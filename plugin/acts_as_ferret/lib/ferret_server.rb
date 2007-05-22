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
        # read connection settings from config file
        def load(file = "#{RAILS_ROOT}/config/ferret_server.yml")
          config = DEFAULTS.merge(YAML.load(ERB.new(IO.read(file)).result))
          if config = config[RAILS_ENV]
            config[:uri] = "druby://#{config['host']}:#{config['port']}"
            return config
          end
          {}
        end
      end
    end

    # This class acts as a drb server listening for indexing and
    # search requests from models declared to 'acts_as_ferret :remote => true'
    #
    # Usage: 
    # - copy doc/ferret_server.yml to RAILS_ROOT/config and modify to suit
    # your needs. environments for which no section in the config file exists
    # will use the index locally (good for unit tests/development mode)
    # - run script/ferret_server (in the plugin directory) via script/runner:
    # RAILS_ENV=production script/runner vendor/plugins/acts_as_ferret/script/ferret_server
    #
    class Server

      cattr_accessor :running

      def self.start(uri = nil)
        ActiveRecord::Base.allow_concurrency = true
        uri ||= ActsAsFerret::Remote::Config.load[:uri]
        DRb.start_service(uri, ActsAsFerret::Remote::Server.new)
        self.running = true
      end

      def initialize
        @logger = Logger.new("#{RAILS_ROOT}/log/ferret_server.log")
      end

      # handles all incoming method calls, and sends them on to the LocalIndex
      # instance of the correct model class.
      #
      # Calls are not queued atm, so this will block until the call returned.
      # Might throw the occasional LockError, too, which most probably means that you're 
      # a) rebuilding your index or 
      # b) have *really* high load. I wasn't able to reproduce this case until
      # now, if you do, please contact me.
      #
      def method_missing(name, *args)
        @logger.debug "\#method_missing(#{name.inspect}, #{args.inspect})"
        clazz = args.shift.constantize
        begin
          clazz.aaf_index.send name, *args
        rescue NoMethodError
          @logger.debug "no luck, trying to call class method instead"
          clazz.send name, *args
        end
      rescue
        @logger.error "ferret server error #{$!}\n#{$!.backtrace.join '\n'}"
        raise
      end

  #    def ferret_index(class_name)
  #      # TODO check if in use!
  #      class_name.constantize.aaf_index.ferret_index
  #    end

      def new_index_for(clazz, models)
        aaf_configuration = clazz.aaf_configuration
        ferret_cfg = aaf_configuration[:ferret].dup
        ferret_cfg.update :auto_flush  => false, 
                          :create      => true,
                          :field_infos => clazz.aaf_index.field_infos(models),
                          :path        => File.join(aaf_configuration[:index_base_dir], 'rebuild')
        Ferret::Index::Index.new ferret_cfg
      end

      def rebuild_index(class_name, *models)
        clazz = class_name.constantize
        models = models.flatten.uniq.map(&:constantize)
        @logger.debug "rebuild index: #{models.inspect}"
        index = new_index_for(clazz, models)
        clazz.aaf_index.do_rebuild_with_index(index, models)
        new_version = File.join clazz.aaf_configuration[:index_base_dir], Time.now.utc.strftime('%Y%m%d%H%M%S')
        # create a unique directory name (needed for unit tests where 
        # multiple rebuilds per second may occur)
        if File.exists?(new_version)
          i = 0
          i+=1 while File.exists?("#{new_version}_#{i}")
          new_version << "_#{i}"
        end
        
        File.rename index.options[:path], new_version
        clazz.index_dir = new_version 
      end

    end
  end
end
