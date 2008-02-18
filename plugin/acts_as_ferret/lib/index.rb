module ActsAsFerret

  class IndexLogger
    def initialize(logger, name)
      @logger = logger
      @index_name = name
    end
    %w(debug info warn error).each do |m|
      define_method(m) do |message|
        @logger.send m, "[#{@index_name}] #{message}"
      end
      question = :"#{m}?"
      define_method(question) do
        @logger.send question
      end
    end
  end

  # base class for local and remote indexes
  class AbstractIndex

    attr_reader :aaf_configuration
    attr_accessor :logger, :index_name, :index_definition
    def initialize(index_definition)
      @index_definition = index_definition
      @index_name = index_definition[:name]
      @logger = IndexLogger.new(ActsAsFerret::logger, @index_name)
    end

    #def index_definition
    #  @index_definition ||= ActsAsFerret::index_definition(@index_name)
    #end

    # TODO allow for per-class field configuration (i.e. different via, boosts
    # for the same field among different models)
    def register_class(clazz, options = {})
      logger.info "register class #{clazz} with index #{index_name}"
      index_definition[:registered_models] << clazz
      index_definition[:store_class_name] = true if shared?

      # merge fields from this acts_as_ferret call with predefined fields
      already_defined_fields = index_definition[:ferret_fields]
      field_config = ActsAsFerret::build_field_config options[:fields]
      field_config.update ActsAsFerret::build_field_config( options[:additional_fields] )
      field_config.each do |field, config|
        if already_defined_fields.has_key?(field)
          logger.info "ignoring redefinition of ferret field #{field}" if shared? 
        else
          already_defined_fields[field] = config
          logger.info "adding new field #{field} from class #{clazz.name} to index #{index_name}"
        end
      end
      
      # update default field list to be used by the query parser, unless it 
      # was explicitly given by user.
      #
      # It will include all content fields *not* marked as :untokenized.
      # This fixes the otherwise failing CommentTest#test_stopwords. Basically
      # this means that by default only tokenized fields (which all fields are
      # by default) will be searched. If you want to search inside the contents 
      # of an untokenized field, you'll have to explicitly specify it in your 
      # query.
      unless index_definition[:user_default_field]
        # grab all tokenized fields
        ferret_fields = index_definition[:ferret_fields]
        index_definition[:ferret][:default_field] = ferret_fields.keys.select do |field|
          ferret_fields[field][:index] != :untokenized
        end
        logger.info "default field list for index #{index_name}: #{index_definition[:ferret][:default_field].inspect}"
      end

      index_definition
    end

    # true if this index is used by more than one model class
    def shared?
      index_definition[:registered_models].size > 1
    end

    # Switches the index to a new index directory.
    # Used by the DRb server when switching to a new index version.
    def change_index_dir(new_dir)
      logger.debug "[#{index_name}] changing index dir to #{new_dir}"
      index_definition[:index_dir] = index_definition[:ferret][:path] = new_dir
      reopen!
      logger.debug "[#{index_name}] index dir is now #{new_dir}"
    end

    protected

  end

end
