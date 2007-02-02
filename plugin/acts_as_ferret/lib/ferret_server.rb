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
      @indexes = Hash.new
      @index_config = config[:indexes]
      config[:indexes].each_pair do |name, config|
        @indexes[name] = init_index(name)
        puts "initialized index #{config[:path]}"
      end
    end

    def init_index(name)
      config = {
        :or_default => false,
      }
      config.update(@index_config[name])
      config.update(:auto_flush => true, :key => :id)
      create_index(name) unless File.file?("#{config[:path]}/segments")
      Ferret::I.new(config)
    end

    def create_index(name)
      configuration = @index_config[name]
      fi = Ferret::Index::FieldInfos.new(:store => :no, 
                                         :index => :yes, 
                                         :term_vector => :no,
                                         :boost => 1.0)
      fi.add_field(:id, :store => :yes, :index => :untokenized) 
      if configuration[:store_class_name]
        fi.add_field(:class_name, :store => :yes, :index => :untokenized) 
      end
      if configuration[:fields].is_a?(Hash)
        configuration[:fields].each_pair do |field, config|
          fi.add_field(field.to_sym, { :store => :no, :index => :yes }.update(config))
        end
      else
        configuration[:fields].each do |field|
          fi.add_field(field.to_sym, { :store => :no, :index => :yes })
        end
      end
      fi.create_index(configuration[:path])
    end

    def rebuild_index(name)
      
    end

    def add_to_index(index_name, *documents)
      i = @indexes[index_name]
      documents.flatten.each { |doc|
        log index_name, "add doc: #{doc.inspect}"
        i << doc
      }
    end

    def find_id_by_contents(index_name, query, options = {})
      i = @indexes[index_name]
      result = []
      total_hits = i.search_each(query, options) do |hit, score|
        # only collect result data if we intend to return it
        doc = i[hit]
        model = @index_config[index_name][:store_class_name] ? doc[:class_name] : nil
        result << { :model => model, :id => doc[:id], :score => score }
      end
      log(index_name, "#{total_hits} results for <#{query}>")
      [ total_hits, result ]
    end

    def query_delete(name, query)
      i = @indexes[index_name]
      i.query_delete(query)
    end

    protected 
    def log(index_name, msg)
      puts "[#{index_name.to_s}] #{msg}"
    end
  end

end
