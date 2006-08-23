# Copyright (c) 2006 Kasper Weibel Nielsen-Refs, Thomas Lockney, Jens Krämer
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'active_record'
require 'set'

# 0.10 problems
# Ferret::Search::Similarity, Ferret::Search::Similarity.default missing
# IndexReader#latest? segfaults when used on multiple indexes
# :offset and :limit get ignored by search_each
# query_parser ignores or_default

# Yet another Ferret Mixin.
#
# This mixin adds full text search capabilities to any Rails model.
#
# It is heavily based on the original acts_as_ferret plugin done by
# Kasper Weibel and a modified version done by Thomas Lockney, which 
# both can be found on 
# http://ferret.davebalmain.com/trac/wiki/FerretOnRails
#
# usage:
# include the following in your model class (specifiying the fields you want to get indexed):
# acts_as_ferret :fields => [ 'title', 'description' ]
#
# now you can use ModelClass.find_by_contents(query) to find instances of your model
# whose indexed fields match a given query. All query terms are required by default, but 
# explicit OR queries are possible. This differs from the ferret default, but imho is the more
# often needed/expected behaviour (more query terms result in less results).
#
# Released under the MIT license.
#
# Authors: 
# Kasper Weibel Nielsen-Refs (original author)
# Jens Kraemer <jk@jkraemer.net>
#
module FerretMixin
  module Acts #:nodoc:
    module ARFerret #:nodoc:

      # decorator that adds a total_hits accessor to search result arrays
      class SearchResults
        attr_reader :total_hits
        def initialize(results, total_hits)
          @results = results
          @total_hits = total_hits
        end
        def method_missing(symbol, *args, &block)
          @results.send(symbol, *args, &block)
        end
        def respond_to?(name)
          self.methods.include?(name) || @results.respond_to?(name)
        end
      end
      
      def self.ensure_directory(dir)
        FileUtils.mkdir_p dir unless File.directory? dir
      end
      
      # make sure the default index base dir exists. by default, all indexes are created
      # under RAILS_ROOT/index/RAILS_ENV
      def self.init_index_basedir
        index_base = "#{RAILS_ROOT}/index"
        ensure_directory index_base
        @@index_dir = "#{index_base}/#{RAILS_ENV}"
        ensure_directory @@index_dir
      end
      
      mattr_accessor :index_dir
      init_index_basedir
      
      def self.append_features(base)
        super
        base.extend(ClassMethods)
      end

      # declare the class level helper methods
      # which will load the relevant instance methods defined below when invoked
      module ClassMethods
        
        # helper that defines a method that adds the given field to a lucene 
        # document instance
        def define_to_field_method(field, options = {})         
          options = { 
            :store => :no, 
            :index => :yes, 
            :term_vector => :with_positions_offsets,
            :boost => 1.0 }.update(options)
          fields_for_ferret[field] = options
          define_method("#{field}_to_ferret".to_sym) do                              
            begin
              #val = self[field] || self.instance_variable_get("@#{field.to_s}".to_sym) || self.method(field).call
              val = content_for_field_name(field)
            rescue
              logger.warn("Error retrieving value for field #{field}: #{$!}")
              val = ''
            end
            logger.debug("Adding field #{field} with value '#{val}' to index")
            val
            #Ferret::Field.new(val, default_opts[:boost])
          end
        end

        def add_fields(field_config)
          if field_config.respond_to?(:each_pair)
            field_config.each_pair do |key,val|
              define_to_field_method(key,val)                  
            end
          elsif field_config.respond_to?(:each)
            field_config.each do |field| 
              define_to_field_method(field)
            end                
          end
        end
        
        # TODO: do we need to define this at this level ? Maybe it's
        # sufficient to do this only in classes calling acts_as_ferret ?
        def reloadable?; false end
        
        @@ferret_indexes = Hash.new
        def ferret_indexes; @@ferret_indexes end
        
        @@multi_indexes = Hash.new
        def multi_indexes; @@multi_indexes end
        
        # declares a class as ferret-searchable. 
        #
        # options are:
        #
        # fields:: names all fields to include in the index. If not given,
        #   all attributes of the class will be indexed. You may also give
        #   symbols pointing to instance methods of your model here, i.e. 
        #   to retrieve and index data from a related model. 
        #
        # additional_fields:: names fields to include in the index, in addition 
        #   to those derived from the db scheme. use if you want to add
        #   custom fields derived from methods to the db fields (which will be picked 
        #   by aaf). This option will be ignored when the fields option is given, in 
        #   that case additional fields get specified there.
        #
        # index_dir:: declares the directory where to put the index for this class.
        #   The default is RAILS_ROOT/index/RAILS_ENV/CLASSNAME. 
        #   The index directory will be created if it doesn't exist.
        #
        # single_index:: set this to true to let this class use a Ferret
        # index that is shared by all classes having :single_index set to true.
        # :store_class_name is set to true implicitly, as well as index_dir, so 
        # don't bother setting these when using this option. the shared index
        # will be located in index/<RAILS_ENV>/shared .
        #
        # store_class_name:: to make search across multiple models useful, set
        # this to true. the model class name will be stored in a keyword field 
        # named class_name
        #
        # max_results:: number of results to retrieve for :num_docs => :all,
        # default value is 1000
        #
        # ferret_options may be:
        # or_default:: - whether query terms are required by
        #   default (the default, false), or not (true)
        # 
        # analyzer:: the analyzer to use for query parsing (default: nil,
        #   wihch means the ferret StandardAnalyzer gets used)
        #
        # TODO: handle additional_fields
        def acts_as_ferret(options={}, ferret_options={})
          configuration = { 
            :index_dir => "#{FerretMixin::Acts::ARFerret::index_dir}/#{self.name.underscore}",
            :store_class_name => false,
            :single_index => false,
            :max_results => 1000
          }
          ferret_configuration = {
            :or_default => false,
            :handle_parser_errors => true,
            #:max_clauses => 512,
            #:default_field => '*',
            #:analyzer => Ferret::Analysis::StandardAnalyzer.new,
            # :wild_card_downcase => true
          }
          configuration.update(options) if options.is_a?(Hash)

          # apply appropriate settings for shared index
          if configuration[:single_index] 
            configuration[:index_dir] = "#{FerretMixin::Acts::ARFerret::index_dir}/shared" 
            configuration[:store_class_name] = true 
          end
          ferret_configuration.update(ferret_options) if ferret_options.is_a?(Hash)
          # these properties are somewhat vital to the plugin and shouldn't
          # be overwritten by the user:
          ferret_configuration.update(

            :key               => (configuration[:single_index] ? [:id, :class_name] : :id),
            :path              => configuration[:index_dir],
            :auto_flush        => true,
            :create_if_missing => true
          )
          
          class_eval <<-EOV
              include FerretMixin::Acts::ARFerret::InstanceMethods

              before_create :ferret_before_create
              before_update :ferret_before_update
              after_create :ferret_create
              after_update :ferret_update
              after_destroy :ferret_destroy      
              
              cattr_accessor :fields_for_ferret   
              cattr_accessor :configuration
              cattr_accessor :ferret_configuration
              
              @@fields_for_ferret = Hash.new
              @@configuration = configuration
              @@ferret_configuration = ferret_configuration

              if configuration[:fields]
                add_fields(configuration[:fields])
              else
                add_fields(self.new.attributes.keys.map { |k| k.to_sym })
                add_fields(configuration[:additional_fields])
              end
            EOV
          FerretMixin::Acts::ARFerret::ensure_directory configuration[:index_dir]
        end
        
        def class_index_dir
          configuration[:index_dir]
        end
        
        # rebuild the index from all data stored for this model.
        # This is called automatically when no index exists yet.
        #
        # TODO: the automatic index initialization only works if 
        # every model class has it's 
        # own index, otherwise the index will get populated only
        # with instances from the first model loaded
        #
        # When calling this method manually, you can give any additional 
        # model classes that should also go into this index as parameters. 
        # Useful when using the :single_index option.
        # Note that attributes named the same in different models will share
        # the same field options in the shared index.
        def rebuild_index(*models)
          models << self
          # default attributes for fields
          fi = Ferret::Index::FieldInfos.new(:store => :no, 
                                             :index => :yes, 
                                             :term_vector => :no,
                                             :boost => 1.0)
          # primary key
          fi.add_field(:id, :store => :yes, :index => :untokenized) 
          # class_name
          if configuration[:store_class_name]
            fi.add_field(:class_name, :store => :yes, :index => :untokenized) 
          end
          # collect field options from all models
          fields = {}
          models.each do |model|
            fields.update(model.fields_for_ferret)
          end
          fields.each_pair do |field, options|
            fi.add_field(field, { :store => :no, 
                                  :index => :yes }.update(options)) 
          end
          fi.create_index(ferret_configuration[:path])

          index = Ferret::Index::Index.new(ferret_configuration.dup.update(:auto_flush => false))
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
          logger.debug("Created Ferret index in: #{class_index_dir}")
          index.flush
          index.optimize
          index.close
        end                                                            
        
        # Retrieve the Ferret::Index::Index instance for this model class.
        # 
        # Index instances are stored in a hash, using the index directory
        # as the key. So model classes sharing a single index will share their
        # Index object, too.
        def ferret_index
          ferret_indexes[class_index_dir] ||= create_index_instance
        end 
        
        # creates a new Index::Index instance. Before that, a check is done
        # to see if the index exists in the file system. If not, index rebuild
        # from all model data retrieved by find(:all) is triggered.
        def create_index_instance
          rebuild_index unless File.file? "#{class_index_dir}/segments"
          Ferret::Index::Index.new(ferret_configuration)
        end
        
        # Finds instances by contents. Terms are ANDed by default, can be circumvented 
        # by using OR between terms. 
        # options:
        # :first_doc - first hit to retrieve (useful for paging)
        # :num_docs - number of hits to retrieve, or :all to retrieve
        # max_results results, which by default is 1000 and can be changed in
        # the call to acts_as_ferret or on demand like this:
        # Model.configuration[:max_results] = 1000000
         #
        # find_options is a hash passed on to active_record's find when
        # retrieving the data from db, useful to i.e. prefetch relationships.
        #
        # this method returns a SearchResults instance, which really is an Array that has 
        # been decorated with a total_hits accessor that delivers the total
        # number of hits (including those not fetched because of a low num_docs
        # value).
        def find_by_contents(q, options = {}, find_options = {})
          # handle shared index
          return single_index_find_by_contents(q, options, find_options) if configuration[:single_index]
          id_array = []
          id_positions = {}
          total_hits = find_id_by_contents(q, options) do |model, id, score|
            id_array << id
            # store index of this id for later ordering of results
            id_positions[id] = id_array.size
          end
          begin
            # TODO: in case of STI AR will filter out hits from other 
            # classes for us, but this
            # will lead to less results retrieved --> scoping of ferret query
            # to self.class is still needed.
            if id_array.empty?
              result = []
            else
              conditions = [ "#{self.table_name}.id in (?)", id_array ]
              # combine our conditions with those given by user, if any
              if find_options[:conditions]
                cust_opts = find_options[:conditions].dup
                conditions.first << " and " << cust_opts.shift
                conditions.concat(cust_opts)
              end
              result = self.find(:all, 
                                 find_options.merge(:conditions => conditions))
            end
          rescue
            logger.debug "REBUILD YOUR INDEX! One of the id's didn't have an associated record: #{id_array}"
          end

          # order results as they were found by ferret, unless an AR :order
          # option was given
          unless find_options[:order]
            result.sort! { |a, b| id_positions[a.id] <=> id_positions[b.id] }
          end
          
          logger.debug "Query: #{q}\nResult id_array: #{id_array.inspect},\nresult: #{result}"
          return SearchResults.new(result, total_hits)
        end 

        # determine all field names in the shared index
        def single_index_field_names(models)
          @single_index_field_names ||= (
              searcher = Ferret::Search::Searcher.new(class_index_dir)
              if searcher.reader.respond_to?(:get_field_names)
                (searcher.reader.send(:get_field_names) - ['id', 'class_name']).to_a
              else
                puts <<-END
  unable to retrieve field names for class #{self.name}, please 
  consider naming all indexed fields in your call to acts_as_ferret!
                END
                models.map { |m| m.content_columns.map { |col| col.name } }.flatten
              end
          )

        end
        
        # weiter: checken ob ferret-bug, dass wir die queries so selber bauen
        # muessen - liegt am downcasen des qparsers ? - gucken ob jetzt mit
        # ferret geht (content_cols) und dave um zugriff auf qp bitten, oder
        # auf reader
        def single_index_find_by_contents(q, options = {}, find_options = {})
          result = []

          unless options[:models] == :all # search needs to be restricted by one or more class names
            options[:models] ||= [] 
            # add this class to the list of given models
            options[:models] << self unless options[:models].include?(self)
            # build query parser TODO: cache these somehow
            original_query = q
            if q.is_a? String
              #class_clauses = []
              #options[:models].each do |model|
              #  class_clauses << "class_name:#{model}"
              #end
              #q << " AND (#{class_clauses.join(' OR ')})"

              qp = Ferret::QueryParser.new (ferret_configuration)
              qp.fields = ferret_index.send(:reader).field_names
              original_query = qp.parse(q)
            end
            #else
            q = Ferret::Search::BooleanQuery.new
            q.add_query(original_query, :must)
            model_query = Ferret::Search::BooleanQuery.new
            options[:models].each do |model|
              model_query.add_query(Ferret::Search::TermQuery.new(:class_name, model.name), :should)
            end
            q.add_query(model_query, :must)
            #end
          end
          #puts q.to_s
          total_hits = find_id_by_contents(q, options) do |model, id, score|
            result << Object.const_get(model).find(id, find_options.dup)
          end
          return SearchResults.new(result, total_hits)
        end
        protected :single_index_find_by_contents

        # Finds instance model name, ids and scores by contents. 
        # Useful if you want to search across models
        # Terms are ANDed by default, can be circumvented by using OR between terms.
        #
        # Example controller code (not tested):
        # def multi_search(query)
        #   result = []
        #   result << (Model1.find_id_by_contents query)
        #   result << (Model2.find_id_by_contents query)
        #   result << (Model3.find_id_by_contents query)
        #   result.flatten!
        #   result.sort! {|element| element[:score]}
        #   # Figure out for yourself how to retreive and present the data from modelname and id 
        # end
        #
        # Note that the scores retrieved this way aren't normalized across
        # indexes, so that the order of results after sorting by score will
        # differ from the order you would get when running the same query
        # on a single index containing all the data from Model1, Model2 
        # and Model
        #
        # options:
        # :first_doc - first hit to retrieve (useful for paging)
        # :num_docs - number of hits to retrieve, or :all to retrieve
        # max_results results, which by default is 1000 and can be changed in
        # the call to acts_as_ferret or on demand like this:
        # Model.configuration[:max_results] = 1000000
        #
        # a block can be given too, it will be executed with every result:
        # find_id_by_contents(q, options) do |model, id, score|
        #    id_array << id
        #    scores_by_id[id] = score 
        # end
        # NOTE: in case a block is given, the total_hits value will be returned
        # instead of the result list!
        # 
        def find_id_by_contents(q, options = {})
          deprecated_options_support(options)
          options[:limit] = configuration[:max_results] if options[:limit] == :all

          result = []
          index = self.ferret_index
          #hits = index.search(q, options)
          #hits.each do |hit, score|
          total_hits = index.search_each(q, options) do |hit, score|
            # only collect result data if we intend to return it
            doc = index[hit]
            model = configuration[:store_class_name] ? doc[:class_name] : self.name
            if block_given?
              yield model, doc[:id].to_i, score
            else
              result << { :model => model, :id => doc[:id], :score => score }
            end
          end
          logger.debug "id_score_model array: #{result.inspect}"
          return block_given? ? total_hits : result
        end
        
        # requires the store_class_name option of acts_as_ferret to be true
        # for all models queried this way.
        #
        # TODO: not optimal as each instance is fetched in a db call for it's
        # own.
        def multi_search(query, additional_models = [], options = {})
          result = []
          total_hits = id_multi_search(query, additional_models, options) do |model, id, score|
            result << Object.const_get(model).find(id)
          end
          SearchResults.new(result, total_hits)
        end
        
        # returns an array of hashes, each containing :class_name,
        # :id and :score for a hit.
        #
        # if a block is given, class_name, id and score of each hit will 
        # be yielded, and the total number of hits is returned.
        #
        def id_multi_search(query, additional_models = [], options = {})
          deprecated_options_support(options)
          options[:limit] = configuration[:max_results] if options[:limit] == :all
          additional_models << self
          searcher = multi_index(additional_models)
          result = []
          total_hits = searcher.search_each (query, options) do |hit, score|
            doc = searcher[hit]
            if block_given?
              yield doc[:class_name], doc[:id].to_i, score
            else
              result << { :model => doc[:class_name], :id => doc[:id], :score => score }
            end
          end
          return block_given? ? total_hits : result
        end
        
        # returns a MultiIndex instance operating on a MultiReader
        def multi_index(model_classes)
          model_classes.sort! { |a, b| a.name <=> b.name }
          key = model_classes.inject("") { |s, clazz| s << clazz.name }
          @@multi_indexes[key] ||= MultiIndex.new(model_classes, ferret_configuration)
        end

        def deprecated_options_support(options)
          if options[:num_docs]
            logger.warn ":num_docs is deprecated, use :limit instead!"
            options[:limit] ||= options[:num_docs]
          end
          if options[:first_doc]
            logger.warn ":first_doc is deprecated, use :offset instead!"
            options[:offset] ||= options[:first_doc]
          end
        end
      end
      
      
      module InstanceMethods
        attr_reader :reindex
        @ferret_reindex = true
        
        def ferret_before_update
          @ferret_reindex = true
        end
        alias :ferret_before_create :ferret_before_update
        
        # add to index
        def ferret_create
          logger.debug "ferret_create/update: #{self.class.name} : #{self.id}"
          if @ferret_reindex
            self.class.ferret_index << self.to_doc
          end
          @ferret_reindex = true
          true
        end
        alias :ferret_update :ferret_create
        
        # remove from index
        def ferret_destroy
          logger.debug "ferret_destroy: #{self.class.name} : #{self.id}"
          begin
            query = Ferret::Search::TermQuery.new(:id, self.id.to_s)
            if self.class.configuration[:single_index]
              bq = Ferret::Search::BooleanQuery.new
              bq.add_query(query, :must)
              bq.add_query(Ferret::Search::TermQuery.new(:class_name, self.class.name), :must)
              query = bq
            end
            self.class.ferret_index.query_delete(query)
          rescue
            logger.warn("Could not find indexed value for this object: #{$!}")
          end
          true
        end
        
        # convert instance to ferret document
        def to_doc
          logger.debug "creating doc for class: #{self.class.name}, id: #{self.id}"
          # Churn through the complete Active Record and add it to the Ferret document
          doc = Ferret::Document.new
          # store the id of each item
          doc[:id] = self.id

          # store the class name if configured to do so
          if configuration[:store_class_name]
            doc[:class_name] = self.class.name
          end
          # iterate through the fields and add them to the document
          #if fields_for_ferret
            # have user defined fields
          fields_for_ferret.each_pair do |field, config|
            doc[field] = self.send("#{field}_to_ferret") unless config[:ignore]
          end
          #else
            # take all fields
            # TODO shouldn't be needed any more
          #  puts "remove me!"
          #  self.attributes.each_pair do |key,val|
          #    unless key == :id
          #      logger.debug "add field #{key} with value #{val}"
          #      doc[key] = val.to_s
          #    end
           # end
          #end
          return doc
        end

        # BIG TODO: this file really gets too big. need to refactor a bit...
        # maybe extract the more like this stuff, could be useful somewhere
        # else, too...


        # returns other instances of this class, which have similar contents
        # like this one. Basically works like this: find out n most interesting
        # (i.e. characteristic) terms from this document, and then build a
        # query from those which is run against the whole index. Which terms
        # are interesting is decided on variour criteria which can be
        # influenced by the given options. 
        #
        # The algorithm used here is a quite straight port of the MoreLikeThis class
        # from Apache Lucene.
        #
        # options are:
        # :field_names : Array of field names to use for similarity search (mandatory)
        # :min_term_freq => 2,  # Ignore terms with less than this frequency in the source doc.
        # :min_doc_freq => 5,   # Ignore words which do not occur in at least this many docs
        # :min_word_length => nil, # Ignore words if less than this len (longer
        # words tend to be more characteristic for the document they occur in).
        # :max_word_length => nil, # Ignore words if greater than this len.
        # :max_query_terms => 25,  # maximum number of terms in the query built
        # :max_num_tokens => 5000, # maximum number of tokens to examine in a
        # single field
        # :boost => false,         # when true, a boost according to the
        # relative score of a term is applied to this Term's TermQuery.
        # :similarity => Ferret::Search::Similarity.default, # the similarity
        # implementation to use
        # :analyzer => Ferret::Analysis::StandardAnalyzer.new # the analyzer to
        # use
        # :append_to_query => nil # proc taking a query object as argument, which will be called after generating the query. can be used to further manipulate the query used to find related documents, i.e. to constrain the search to a given class in single table inheritance scenarios
        # find_options : options handed over to find_by_contents
        def more_like_this(options = {}, find_options = {})
          options = {
            :field_names => nil,  # Default field names
            :min_term_freq => 2,  # Ignore terms with less than this frequency in the source doc.
            :min_doc_freq => 5,   # Ignore words which do not occur in at least this many docs
            :min_word_length => 0, # Ignore words if less than this len. Default is not to ignore any words.
            :max_word_length => 0, # Ignore words if greater than this len. Default is not to ignore any words.
            :max_query_terms => 25,  # maximum number of terms in the query built
            :max_num_tokens => 5000, # maximum number of tokens to analyze when analyzing contents
            :boost => false,      
            :similarity => Ferret::Search::Similarity.default,
            :analyzer => Ferret::Analysis::StandardAnalyzer.new,
            :append_to_query => nil,
            :base_class => self.class # base class to use for querying, useful in STI scenarios where BaseClass.find_by_contents can be used to retrieve results from other classes, too
          }.update(options)
          index = self.class.ferret_index
          begin
            reader = index.send(:reader)
          rescue
            # ferret >=0.9, C-Version doesn't allow access to Index#reader
            reader = Ferret::Index::IndexReader.open(Ferret::Store::FSDirectory.new(self.class.class_index_dir, false))
          end
          doc_number = self.document_number
          term_freq_map = retrieve_terms(document_number, reader, options)
          priority_queue = create_queue(term_freq_map, reader, options)
          query = create_query(priority_queue, options)
          options[:append_to_query].call(query) if options[:append_to_query]
          options[:base_class].find_by_contents(query, find_options)
        end

        
        def create_query(priority_queue, options={})
          query = Ferret::Search::BooleanQuery.new
          qterms = 0
          best_score = nil
          while(cur = priority_queue.pop)
            term_query = Ferret::Search::TermQuery.new(cur.to_term)
            
            if options[:boost]
              # boost term according to relative score
              # TODO untested
              best_score ||= cur.score
              term_query.boost = cur.score / best_score
            end
            begin
              query.add_query(term_query, :should) 
            rescue Ferret::Search::BooleanQuery::TooManyClauses
              break
            end
            qterms += 1
            break if options[:max_query_terms] > 0 && qterms >= options[:max_query_terms]
          end
          # exclude ourselves
          t = Ferret::Index::Term.new('id', self.id.to_s)
          query.add_query(Ferret::Search::TermQuery.new(t), :must_not)
          return query
        end

        
        def document_number
          hits = self.class.ferret_index.search("id:#{self.id}")
          hits.each { |hit, score| return hit }
        end

        # creates a term/term_frequency map for terms from the fields
        # given in options[:field_names]
        def retrieve_terms(doc_number, reader, options)
          field_names = options[:field_names]
          max_num_tokens = options[:max_num_tokens]
          term_freq_map = Hash.new(0)
          doc = nil
          field_names.each do |field|
            term_freq_vector = reader.get_term_vector(document_number, field)
            if term_freq_vector
              # use stored term vector
              # TODO untested
              term_freq_vector.terms.each_with_index do |term, i|
                term_freq_map[term] += term_freq_vector.freqs[i] unless noise_word?(term, options)
              end
            else
              # no term vector stored, but we have stored the contents in the index
              # -> extract terms from there
              doc ||= reader.get_document(doc_number)
              content = doc[field]
              unless content
                # no term vector, no stored content, so try content from this instance
                content = content_for_field_name(field)
              end
              token_count = 0
              
              # C-Ferret >=0.9 again, no #each in tokenstream :-(
              ts = options[:analyzer].token_stream(field, content)
              while token = ts.next
              #options[:analyzer].token_stream(field, doc[field]).each do |token|
                break if (token_count+=1) > max_num_tokens
                next if noise_word?(token_text(token), options)
                term_freq_map[token_text(token)] += 1
              end
            end
          end
          term_freq_map
        end

        # extract textual value of a token
        def token_text(token)
          # token.term_text is for ferret 0.3.2
          token.respond_to?(:text) ? token.text : token.term_text
        end

        # create an ordered(by score) list of word,fieldname,score 
        # structures
        def create_queue(term_freq_map, reader, options)
          pq = Array.new(term_freq_map.size)
          
          similarity = options[:similarity]
          num_docs = reader.num_docs
          term_freq_map.each_pair do |word, tf|
            # filter out words that don't occur enough times in the source
            next if options[:min_term_freq] && tf < options[:min_term_freq]
            
            # go through all the fields and find the largest document frequency
            top_field = options[:field_names].first
            doc_freq = 0
            options[:field_names].each do |field_name| 
              freq = reader.doc_freq(Ferret::Index::Term.new(field_name, word))
              if freq > doc_freq 
                top_field = field_name
                doc_freq = freq
              end
            end
            # filter out words that don't occur in enough docs
            next if options[:min_doc_freq] && doc_freq < options[:min_doc_freq]
            next if doc_freq == 0 # index update problem ?
            
            idf = similarity.idf(doc_freq, num_docs)
            score = tf * idf
            pq << FrequencyQueueItem.new(word, top_field, score)
          end
          pq.compact!
          pq.sort! { |a,b| a.score<=>b.score }
          return pq
        end
        
        def noise_word?(text, options)
          len = text.length
          (
            (options[:min_word_length] > 0 && len < options[:min_word_length]) ||
            (options[:max_word_length] > 0 && len > options[:max_word_length]) ||
            (options[:stop_words] && options.include?(text))
          )
        end

        def content_for_field_name(field)
          self[field] || self.instance_variable_get("@#{field.to_s}".to_sym) || self.send(field.to_sym)
        end

      end

      class FrequencyQueueItem
        attr_reader :word, :field, :score
        def initialize(word, field, score)
          @word = word; @field = field; @score = score
        end
        def to_term
          Ferret::Index::Term.new(self.field, self.word)
        end
      end
      
    end
  end
end

# reopen ActiveRecord and include all the above to make
# them available to all our models if they want it
ActiveRecord::Base.class_eval do
  include FerretMixin::Acts::ARFerret
end


class Ferret::Index::MultiReader
  def latest?
    # TODO: Exception handling added to resolve ticket #6. 
    # It should be clarified wether this is a bug in Ferret
    # in which case a bug report should be posted on the Ferret Trac. 
    begin
      @sub_readers.each { |r| return false unless r.latest? }
    rescue
      return false
    end
    true
  end
end

# END acts_as_ferret.rb
