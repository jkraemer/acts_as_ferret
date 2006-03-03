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
          include Ferret         

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
            define_method ("#{field}_to_ferret".to_sym) do                              
                val = self[field] || self.instance_variable_get("@#{field.to_s}".to_sym)
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

          @@index_searchers = Hash.new
          def index_searchers; @@index_searchers end

          # declares a class as ferret-searchable. 
          #
          # options are:
          # The mandatory :fields property names all fields to include in the index.
          # :index_dir declares the directory where to put the index for this class.
          # The default is RAILS_ROOT/index/RAILS_ENV/CLASSNAME. 
          # The index directory will be created if it doesn't exist.
          #
          # parser_options:
          # occur_default - declares whether query terms are required by
          #   default (the default), or not. Specify one of 
          #   Ferret::Search::BooleanClause::Occur::MUST or 
          #   Ferret::Search::BooleanClause::Occur::SHOULD 
          # analyzer - the analyzer to use for query parsing (default: nil,
          # wihch means the ferret default Analyzer gets used)
          def acts_as_ferret(options={}, parser_options={})
            configuration = { :index_dir => "#{FerretMixin::Acts::ARFerret::index_dir}/#{self.name}" }
            configuration.update(options) if options.is_a?(Hash)

            parser_configuration = {
              :occur_default => Search::BooleanClause::Occur::MUST,
              :analyzer => nil
            }
            parser_configuration.update(parser_options) if parser_options.is_a? Hash

            class_eval <<-EOV
              include FerretMixin::Acts::ARFerret::InstanceMethods

              after_create :ferret_create
              after_update :ferret_update
              after_destroy :ferret_destroy      
              
              cattr_accessor :fields_for_ferret   
              cattr_accessor :class_index_dir
              cattr_accessor :parser_configuration
              
              @@fields_for_ferret = Array.new
              @@class_index_dir = configuration[:index_dir]
              @@parser_configuration = parser_configuration

              # TODO: make occur_default configurable 
              def self.query_parser
                @@query_parser ||= 
                  QueryParser.new( fields_for_ferret, 
                                   parser_configuration )
              end

              # private
              if configuration[:fields].respond_to?(:each_pair)
                configuration[:fields].each_pair do |key,val|
                  define_to_field_method(key,val)                  
                end
              elsif configuration[:fields].respond_to?(:each)
                configuration[:fields].each do |field| 
                        define_to_field_method(field)
                end                
              else
                #need to handle :all case
              end
            EOV
            FerretMixin::Acts::ARFerret::ensure_directory configuration[:index_dir]
            rebuild_index unless File.file? "#{configuration[:index_dir]}/segments"
          end

          def rebuild_index
            index = Ferret::Index::Index.new(:path => class_index_dir, :create => true)
            self.find_all.each { |content| index << content.to_doc }
            logger.debug("Created Ferret index in: #{class_index_dir}")
            index.flush
            index.optimize
            index.close
          end                                                            

          # Index instances are stored in a hash, using the index directory
          # as the key.
          def ferret_index
            ferret_indexes[class_index_dir] ||= 
              Index::Index.new(:key               => :id,
                               :path              => class_index_dir,
                               :auto_flush        => true,
                               :create_if_missing => true)
          end 

          # returns the searcher for the index that is used for this class. A
          # new searcher will be opened if the segments file is newer than
          # the existing searcher instance. That way modifications of the index
          # will always be reflected by the searcher.
          # Searcher instances are stored in a hash, where the index directory
          # a searcher is working on is the key.
          def index_searcher
            if searcher = index_searchers[class_index_dir]
              last_index_modification = File.mtime "#{class_index_dir}/segments"
              if last_index_modification > searcher.creation_time
                searcher.close
                index_searchers.delete class_index_dir 
              end
            end
            index_searchers[class_index_dir] ||= new_index_searcher
          end

          def new_index_searcher
            searcher = Search::IndexSearcher.new(class_index_dir)
            searcher.creation_time = Time.now
            searcher
          end
  
          # Finds instances by contents. Terms are ANDed by default, can be circumvented 
          # by using OR between terms. 
          # options:
          # :first_doc - first hit to retrieve (useful for paging)
          # :num_docs - number of hits to retrieve
          def find_by_contents(q, options = {})
            if q.is_a? Search::Query
              query = q
            else  
              query = query_parser.parse(q)
            end
            logger.debug "parsed query for <#{q}> : <#{query}>" 
            result = []
            hits = index_searcher.search(query, options)
            hits.each do |hit, score|
              id = index_searcher.reader.get_document(hit)[:id]
              begin
                res = self.find(id)
                result << res if res
                logger.debug "result id: #{id}, result: #{res}"
              rescue
                logger.debug "no data for id #{id}"
              end
            end
            return result
          end 

        end


        module InstanceMethods
          include Ferret         

          # add to index
          def ferret_create
            logger.debug "ferret_create/update: #{self.class.name} : #{self.id}"
            self.class.ferret_index << self.to_doc
          end
          alias :ferret_update :ferret_create
          
          # remove from index
          def ferret_destroy
            begin
              self.class.ferret_index.query_delete("+id:#{self.id}")
            rescue
              logger.warn("Could not find indexed value for this object")
            end
          end
          
          # convert instance to ferret document
          def to_doc
            logger.debug "creating doc for class: #{self.class.name}"
            # Churn through the complete Active Record and add it to the Ferret document
            doc = Document::Document.new
            # store the id of each item
            doc << Document::Field.new( "id", self.id, 
                                        Document::Field::Store::YES, 
                                        Document::Field::Index::UNTOKENIZED )
            # iterate through the fields and add them to the document
            fields_for_ferret.each do |field|
                doc << self.send("#{field}_to_ferret")
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

# add creation time attribute to the IndexSearcher class
Ferret::Search::IndexSearcher.class_eval do
  attr_accessor :creation_time
end

# END acts_as_ferret.rb

