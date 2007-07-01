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

require 'active_support'
require 'active_record'
require 'set'
require 'ferret'

require 'act_methods'
require 'class_methods'
require 'shared_index_class_methods'
require 'ferret_result'
require 'instance_methods'

require 'multi_index'
require 'more_like_this'

require 'index'
require 'local_index'
require 'shared_index'
require 'remote_index'

require 'ferret_server'


# The Rails ActiveRecord Ferret Mixin.
#
# This mixin adds full text search capabilities to any Rails model.
#
# The current version emerged from on the original acts_as_ferret plugin done by
# Kasper Weibel and a modified version done by Thomas Lockney, which  both can be 
# found on the Ferret Wiki: http://ferret.davebalmain.com/trac/wiki/FerretOnRails.
#
# basic usage:
# include the following in your model class (specifiying the fields you want to get indexed):
# acts_as_ferret :fields => [ :title, :description ]
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
# Jens Kraemer <jk@jkraemer.net> (active maintainer)
#
module ActsAsFerret

    # global Hash containing all multi indexes created by all classes using the plugin
    # key is the concatenation of alphabetically sorted names of the classes the
    # searcher searches.
    @@multi_indexes = Hash.new
    def self.multi_indexes; @@multi_indexes end

    # global Hash containing the ferret indexes of all classes using the plugin
    # key is the index directory.
    @@ferret_indexes = Hash.new
    def self.ferret_indexes; @@ferret_indexes end

 
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
    @@index_dir = "#{index_base}/#{RAILS_ENV}"
  end
  
  mattr_accessor :index_dir
  init_index_basedir
  
  def self.append_features(base)
    super
    base.extend(ClassMethods)
  end
  
  # builds a FieldInfos instance for creation of an index containing fields
  # for the given model classes.
  def self.field_infos(models)
    # default attributes for fields
    fi = Ferret::Index::FieldInfos.new(:store => :no, 
                                        :index => :yes, 
                                        :term_vector => :no,
                                        :boost => 1.0)
    # primary key
    fi.add_field(:id, :store => :yes, :index => :untokenized) 
    fields = {}
    have_class_name = false
    models.each do |model|
      fields.update(model.aaf_configuration[:ferret_fields])
      # class_name
      if !have_class_name && model.aaf_configuration[:store_class_name]
        fi.add_field(:class_name, :store => :yes, :index => :untokenized) 
        have_class_name = true
      end
    end
    fields.each_pair do |field, options|
      fi.add_field(field, { :store => :no, 
                            :index => :yes }.update(options)) 
    end
    return fi
  end

  def self.close_multi_indexes
    # close combined index readers, just in case
    # this seems to fix a strange test failure that seems to relate to a
    # multi_index looking at an old version of the content_base index.
    multi_indexes.each_pair do |key, index|
      # puts "#{key} -- #{self.name}"
      # TODO only close those where necessary (watch inheritance, where
      # self.name is base class of a class where key is made from)
      index.close #if key =~ /#{self.name}/
    end
    multi_indexes.clear
  end

end

# include acts_as_ferret method into ActiveRecord::Base
ActiveRecord::Base.extend ActsAsFerret::ActMethods

class Ferret::Index::Index
  attr_accessor :batch_size
  attr_accessor :logger

  def index_models(models)
    models.each do |model|
      index_model model
    end
    flush
    optimize
    close
    ActsAsFerret::close_multi_indexes
  end

  def index_model(model)
    @batch_size ||= 0
    model_count = model.count.to_f
    work_done = 0
    batch_time = 0
    logger.info "reindexing model #{model.name}"
    order = "#{model.primary_key} ASC" # this works around a bug in sqlserver-adapter (where paging only works with an order applied)
    model.transaction do
      0.step(model.count, batch_size) do |i|
        batch_time = measure_time {
          model.find(:all, :limit => batch_size, :offset => i, :order => order).each do |rec|
            self << rec.to_doc if rec.ferret_enabled?(true)
          end
        }.to_f
        work_done = i.to_f / model_count * 100.0 if model_count > 0
        remaining_time = ( batch_time / batch_size ) * ( model_count - i + batch_size )
        logger.info "reindex model #{model.name} : #{'%.2f' % work_done}% complete : #{'%.2f' % remaining_time} secs to finish"
      end
    end
  end

  def measure_time
    t1 = Time.now
    yield
    Time.now - t1
  end

end

# small Ferret monkey patch
# TODO check if this is still necessary
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

# add marshalling support to SortFields
class Ferret::Search::SortField
  def _dump(depth)
    to_s
  end

  def self._load(string)
    case string
      when '<SCORE>!'              : Ferret::Search::SortField::SCORE_REV
      when '<SCORE>'              : Ferret::Search::SortField::SCORE
      when /^(\w+):<(\w+)>(\!)?$/ : new($1.to_sym, :type => $2.to_sym, :reverse => !$3.nil?)
      else raise "invalid value: #{string}"
    end
  end
end

