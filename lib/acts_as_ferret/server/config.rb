require 'yaml'
require 'erb'

module ActsAsFerret
  module Server
    
    class Config

      ################################################################################
      DEFAULTS = {
        'host'      => 'localhost',
        'port'      => '9009',
        'cf'        => "config/ferret_server.yml",
        'pid_file'  => "log/ferret_server.pid",
        'log_file'  => "log/ferret_server.log",
        'log_level' => 'debug',
        'socket'    => nil,
        'script'    => nil
      }

      ################################################################################
      # load the configuration file and apply default settings
      def initialize(file = DEFAULTS['cf'])
        @everything = YAML.load(ERB.new(IO.read(abs_config_file_path(file))).result)
        raise "malformed ferret server config" unless @everything.is_a?(Hash)
        @config = DEFAULTS.merge(@everything[Rails.env] || {})
        if @everything[Rails.env]
          @config['uri'] = socket.nil? ? "druby://#{host}:#{port}" : "drbunix:#{socket}"
        end
      end
      
      def abs_config_file_path(path)
        if path =~ /^\//
          path
        else
          Rails.root.join(path).to_s
        end
      end

      ################################################################################
      # treat the keys of the config data as methods
      def method_missing (name, *args)
        @config.has_key?(name.to_s) ? @config[name.to_s] : super
      end

    end
    
    
  end
end