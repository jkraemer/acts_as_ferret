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
require 'ferret'

# Yet another Ferret Mixin.
#
# This mixin adds full text search capabilities to any Rails model.
#
# It is heavily based on the original acts_as_ferret plugin done by
# Kasper Weibel and a modified version done by Thomas Lockney, which 
# both can be found on 
# http://ferret.davebalmain.com/trac/wiki/FerretOnRails
#
# Changes I did to the original version include:
#
# - automatic creation of missing index directories
# - I took out the storage of class names in the index, as I prefer 
#   the 'one model, one index'-approach. If needed, multiple models 
#   can share one index by using a common superclass for these.
# - separate index directories for different Rails environments, so
#   unit tests don't mess up the production/development indexes.
# - default to AND queries, as this is the behaviour most users expect
# - index searcher instances are kept as class variables and will be re-used
#   until an index change is detected, as opening a searcher is quite expensive
#   this should improve search performance
# - query parser is kept as a class variable
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
      
      def self.ensure_directory(dir)
        Dir.mkdir dir unless File.directory? dir
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
          default_opts = { :store => Ferret::Document::Field::Store::NO, 
            :index => Ferret::Document::Field::Index::TOKENIZED, 
            :term_vector => Ferret::Document::Field::TermVector::NO,
            :binary => false,
            :boost => 1.0
          }
          default_opts.update(options) if options.is_a?(Hash) 
          fields_for_ferret << field 
          define_method("#{field}_to_ferret".to_sym) do                              
            begin
              val = self[field] || self.instance_variable_get("@#{field.to_s}".to_sym) || self.method(field).call
            rescue
              logger.debug("Error retrieving value for field #{field}: #{$!}")
              val = ''
            end
            logger.debug("Adding field #{field} with value '#{val}' to index")
            Ferret::Document::Field.new(field.to_s, val, 
                                        default_opts[:store], 
                                        default_opts[:index], 
                                        default_opts[:term_vector], 
                                        default_opts[:binary], 
                                        default_opts[:boost]) 
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
        # index_dir:: declares the directory where to put the index for this class.
        #   The default is RAILS_ROOT/index/RAILS_ENV/CLASSNAME. 
        #   The index directory will be created if it doesn't exist.
        #
        # store_class_name:: to make search across multiple models useful, set
        # this to true. the model class name will be stored in a keyword field 
        # named class_name
        #
        # ferret_options may be:
        # occur_default:: - whether query terms are required by
        #   default (the default), or not. Specify one of 
        #   Ferret::Search::BooleanClause::Occur::MUST or 
        #   Ferret::Search::BooleanClause::Occur::SHOULD
        # 
        # analyzer:: the analyzer to use for query parsing (default: nil,
        #   wihch means the ferret default Analyzer gets used)
        #
        def acts_as_ferret(options={}, ferret_options={})
          configuration = { 
            :fields => nil,
            :index_dir => "#{FerretMixin::Acts::ARFerret::index_dir}/#{self.name}",
            :store_class_name => false
          }
          ferret_configuration = {
            :occur_default => Ferret::Search::BooleanClause::Occur::MUST,
            :handle_parse_errors => true,
            :default_search_field => '*',
            # :analyzer => Analysis::StandardAnalyzer.new,
            # :wild_lower => true
          }
          configuration.update(options) if options.is_a?(Hash)
          ferret_configuration.update(ferret_options) if ferret_options.is_a?(Hash)
          # these properties are somewhat vital to the plugin and shouldn't
          # be overwritten by the user:
          ferret_configuration.update(
                                      :key               => 'id',
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
              
              @@fields_for_ferret = Array.new
              @@configuration = configuration
              @@ferret_configuration = ferret_configuration
              
              if configuration[:fields].respond_to?(:each_pair)
                configuration[:fields].each_pair do |key,val|
                  define_to_field_method(key,val)                  
                end
              elsif configuration[:fields].respond_to?(:each)
                configuration[:fields].each do |field| 
                  define_to_field_method(field)
                end                
              else
                @@fields_for_ferret = nil
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
        def rebuild_index
          index = Ferret::Index::Index.new(ferret_configuration.merge(:create => true))
          self.find_all.each { |content| index << content.to_doc }
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
        # :num_docs - number of hits to retrieve
        def find_by_contents(q, options = {})
          id_array = []
          scores_by_id = {}
          find_id_by_contents(q, options) do |element|
            id_array << id = element[:id].to_i
            scores_by_id[id] = element[:score] 
          end
          begin
            if self.superclass == ActiveRecord::Base
              result = self.find(id_array)
            else
              # no direct subclass of Base --> STI
              # TODO: AR will filter out hits from other classes for us, but this
              # will lead to less results retrieved --> scoping of ferret query
              # to self.class is still needed.
              result = self.find(:all, :conditions => ["id in (?)",id_array])
            end 
          rescue
            logger.debug "REBUILD YOUR INDEX! One of the id's didn't have an associated record: #{id_array}"
          end

          # sort results by score (descending)
          result.sort! { |b, a| scores_by_id[a.id] <=> scores_by_id[b.id] }
          
          logger.debug "Query: #{q}\nResult id_array: #{id_array.inspect},\nresult: #{result},\nscores: #{scores_by_id.inspect}"
          return result
        end 
        
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
        # :num_docs - number of hits to retrieve      
        #
        # a block can be given too, it will be executed with every result hash:
        # find_id_by_contents(q, options) do |element|
        #    id_array << id = element[:id].to_i
        #    scores_by_id[id] = element[:score] 
        # end
        # 
        def find_id_by_contents(q, options = {})
          result = []
          hits = ferret_index.search(q, options)
          hits.each do |hit, score|
            result << {:model => self.name, :id => ferret_index[hit][:id], :score => score}
            yield result.last if block_given?
          end
          logger.debug "id_score_model array: #{result.inspect}"
          result
        end
        
        # requires the store_class_name option of acts_as_ferret to be true
        # for all models queried this way.
        #
        # TODO: not optimal as each instance is fetched in a db call for it's
        # own.
        def multi_search(query, additional_models = [], options = {})
          result = []
          id_multi_search(query, additional_models, options).each { |hit|
            result << Object.const_get(hit[:model]).find(hit[:id].to_i)
          }
          result
        end
        
        # returns an array of hashes, each containing :class_name,
        # :id and :score for a hit.
        #
        def id_multi_search(query, additional_models = [], options = {})
          additional_models << self
          searcher = multi_index(additional_models)
          result = []
          hits = searcher.search(query, options)
          hits.each { |hit, score|
            doc = searcher.doc(hit)
            result << { :model => doc[:class_name], :id => doc[:id], :score => score }
          }
          result
        end
        
        # returns a MultiIndex instance operating on a MultiReader
        def multi_index(model_classes)
          model_classes.sort! { |a, b| a.name <=> b.name }
          key = model_classes.inject("") { |s, clazz| s << clazz.name }
          @@multi_indexes[key] ||= MultiIndex.new(model_classes, ferret_configuration)
        end
        
      end
      
      
      # not threadsafe
      class MultiIndex
        
        attr_reader :reader
        
        # todo: check for necessary index rebuilds in this place, too
        # idea - each class gets a create_reader method that does this
        def initialize(model_classes, options = {})
          @model_classes = model_classes
          @options = { 
            :default_search_field => '*',
            :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new
          }.update(options)
          ensure_reader
        end
        
        def search(query, options={})
          query = process_query(query)
          searcher.search(query, options)
        end
        
        def ensure_reader
          create_new_multi_reader unless @reader
          unless @reader.latest?
            if @searcher
              @searcher.close # will close the multi_reader and all sub_readers as well
            else
              @reader.close # just close the reader
            end
            create_new_multi_reader
            @searcher = nil
          end
        end
        
        def searcher
          ensure_reader
          @searcher ||= Ferret::Search::IndexSearcher.new(@reader)
        end
        
        def doc(i)
          searcher.doc(i)
        end
        
        def query_parser
          @query_parser ||= Ferret::QueryParser.new(@options[:default_search_field], @options)
        end
        
        def process_query(query)
          query = query_parser.parse(query) if query.is_a?(String)
          return query
        end
        
        # creates a new MultiReader to search the given Models
        def create_new_multi_reader
          sub_readers = @model_classes.map { |clazz| 
            Ferret::Index::IndexReader.open(clazz.class_index_dir) 
          }
          @reader = Ferret::Index::MultiReader.new(sub_readers)
          query_parser.fields = @reader.get_field_names.to_a
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
          self.class.ferret_index << self.to_doc if @ferret_reindex
          @ferret_reindex = true
          true
        end
        alias :ferret_update :ferret_create
        
        # remove from index
        def ferret_destroy
          begin
            self.class.ferret_index.query_delete("+id:#{self.id}")
          rescue
            logger.warn("Could not find indexed value for this object")
          end
          true
        end
        
        # convert instance to ferret document
        def to_doc
          logger.debug "creating doc for class: #{self.class.name}"
          # Churn through the complete Active Record and add it to the Ferret document
          doc = Ferret::Document::Document.new
          # store the id of each item
          doc << Ferret::Document::Field.new( "id", self.id, 
          Ferret::Document::Field::Store::YES, 
          Ferret::Document::Field::Index::UNTOKENIZED )
          # store the class name if configured to do so
          if configuration[:store_class_name]
            doc << Ferret::Document::Field.new( "class_name", self.class.name, 
            Ferret::Document::Field::Store::YES, 
            Ferret::Document::Field::Index::UNTOKENIZED )
          end
          # iterate through the fields and add them to the document
          if fields_for_ferret
            # have user defined fields
            fields_for_ferret.each do |field|
              doc << self.send("#{field}_to_ferret")
            end
          else
            # take all fields
            self.attributes.each_pair do |key,val|
              unless key == :id
                logger.debug "add field #{key} with value #{val}"
                doc << Ferret::Document::Field.new(
                                           key, 
                                           val.to_s, 
                                           Ferret::Document::Field::Store::NO, 
                                           Ferret::Document::Field::Index::TOKENIZED)
              end
            end
          end
          return doc
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
