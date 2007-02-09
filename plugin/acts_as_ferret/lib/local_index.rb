module ActsAsFerret
  
  class LocalIndex < AbstractIndex
    include MoreLikeThis::IndexMethods

    # the 'real' Ferret Index instance
    attr_reader :ferret_index

    def initialize(aaf_configuration)
      super
      rebuild_index unless File.file? "#{aaf_configuration[:index_dir]}/segments"
      @ferret_index = Ferret::Index::Index.new(aaf_configuration[:ferret])
    end

    def rebuild_index(models = [])
      logger.debug "rebuild index: #{models.join ' '}"
      models = models.flatten.uniq.map(&:constantize)
      # default attributes for fields
      fi = Ferret::Index::FieldInfos.new(:store => :no, 
                                         :index => :yes, 
                                         :term_vector => :no,
                                         :boost => 1.0)
      # primary key
      fi.add_field(:id, :store => :yes, :index => :untokenized) 
      # class_name
      if aaf_configuration[:store_class_name]
        fi.add_field(:class_name, :store => :yes, :index => :untokenized) 
      end
      # collect field options from all models
      fields = {}
      models.each do |model|
        fields.update(model.aaf_configuration[:ferret_fields])
      end
      logger.debug("class #{aaf_configuration[:class_name]}: fields for index: #{fields.keys.join(',')}")
      fields.each_pair do |field, options|
        fi.add_field(field, { :store => :no, 
                              :index => :yes }.update(options)) 
      end
      index = Ferret::Index::Index.new(aaf_configuration[:ferret].dup.update(:auto_flush => false, 
                                                                             :field_infos => fi,
                                                                             :create => true))
      # TODO make configurable through options
      batch_size = 1000
      models.each do |model|
        # index in batches of 1000 to limit memory consumption (fixes #24)
        model.transaction do
          0.step(model.count, batch_size) do |i|
            model.find(:all, :limit => batch_size, :offset => i).each do |rec|
              index << rec.to_doc
            end
          end
        end
      end
      logger.debug("Created Ferret index in: #{aaf_configuration[:index_dir]}")
      index.flush
      index.optimize
      index.close
      # close combined index readers, just in case
      # this seems to fix a strange test failure that seems to relate to a
      # multi_index looking at an old version of the content_base index.
      ActsAsFerret::multi_indexes.each_pair do |key, index|
        # puts "#{key} -- #{self.name}"
        # TODO only close those where necessary (watch inheritance, where
        # self.name is base class of a class where key is made from)
        index.close #if key =~ /#{self.name}/
      end
      ActsAsFerret::multi_indexes.clear
    end

    # parses the given query string
    def process_query(query)
      # work around ferret bug in #process_query (doesn't ensure the
      # reader is open)
      ferret_index.synchronize do
        ferret_index.send(:ensure_reader_open)
        original_query = ferret_index.process_query(query)
      end
    end

    def total_hits(query, options = {})
      ferret_index.search(query, options).total_hits
    end

    def find_id_by_contents(query, options = {}, &block)
      result = []
      #logger.debug "query: #{ferret_index.process_query query}"
      total_hits = ferret_index.search_each(query, options) do |hit, score|
        doc = ferret_index[hit]
        model = aaf_configuration[:store_class_name] ? doc[:class_name] : aaf_configuration[:class_name]
        if block_given?
          yield model, doc[:id], score
        else
          result << { :model => model, :id => doc[:id], :score => score }
        end
      end
      #logger.debug "id_score_model array: #{result.inspect}"
      return block_given? ? total_hits : [total_hits, result]
    end

    def id_multi_search(query, models, options = {})
      models.map!(&:constantize)
      searcher = multi_index(models)
      result = []
      total_hits = searcher.search_each(query, options) do |hit, score|
        doc = searcher[hit]
        if block_given?
          yield doc[:class_name], doc[:id], score
        else
          result << { :model => doc[:class_name], :id => doc[:id], :score => score }
        end
      end
      return block_given? ? total_hits : [ total_hits, result ]
    end

    ######################################
    # methods working on a single record
    # called from instance_methods, here to simplify interfacing with the
    # remote ferret server
    # TODO having to pass id and class_name around like this isn't nice
    ######################################

    # add record to index
    # record may be the full AR object, a Ferret document instance or a Hash
    def add(record)
      record = record.to_doc unless Hash === record || Ferret::Document === record
      ferret_index << record
    end
    alias << add

    # delete record from index
    def remove(id, class_name)
      ferret_index.query_delete query_for_record(id, class_name)
    end

    # highlight search terms for the record with the given id.
    def highlight(id, class_name, query, options = {})
      options.reverse_merge! :num_excerpts => 2, :pre_tag => '<em>', :post_tag => '</em>'
      highlights = []
      ferret_index.synchronize do
        doc_num = document_number(id, class_name)
        if options[:field]
          highlights << ferret_index.highlight(query, doc_num, options)
        else
          query = process_query(query) # process only once
          aaf_configuration[:ferret_fields].each_pair do |field, config|
            next if config[:store] == :no || config[:highlight] == :no
            options[:field] = field
            highlights << ferret_index.highlight(query, doc_num, options)
          end
        end
      end
      return highlights.compact.flatten[0..options[:num_excerpts]-1]
    end

    # retrieves the ferret document number of the record with the given id.
    def document_number(id, class_name)
      hits = ferret_index.search(query_for_record(id, class_name))
      return hits.hits.first.doc if hits.total_hits == 1
      raise "cannot determine document number from primary key: #{id}"
    end

    # build a ferret query matching only the record with the given id
    # the class name only needs to be given in case of a shared index configuration
    def query_for_record(id, class_name = nil)
      Ferret::Search::TermQuery.new(:id, id.to_s)
    end


    protected

    # returns a MultiIndex instance operating on a MultiReader
    def multi_index(model_classes)
      model_classes.sort! { |a, b| a.name <=> b.name }
      key = model_classes.inject("") { |s, clazz| s + clazz.name }
      multi_config = aaf_configuration[:ferret].dup
      multi_config.delete :default_field  # we don't want the default field list of *this* class for multi_searching
      ActsAsFerret::multi_indexes[key] ||= MultiIndex.new(model_classes, multi_config)
    end
 
  end

end
