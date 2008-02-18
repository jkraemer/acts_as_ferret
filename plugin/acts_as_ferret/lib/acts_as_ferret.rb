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
require 'enumerator'
require 'ferret'

require 'blank_slate'
require 'bulk_indexer'
require 'ferret_extensions'
require 'act_methods'
require 'search_results'
require 'class_methods'
require 'shared_index_class_methods'
require 'ferret_result'
require 'instance_methods'
require 'without_ar'

require 'multi_index'
require 'more_like_this'

require 'index'
require 'local_index'
require 'shared_index'
require 'remote_index'

require 'ferret_server'

require 'rdig_adapter'

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

  class ActsAsFerretError < StandardError; end
  class IndexNotDefined < ActsAsFerretError; end
  class IndexAlreadyDefined < ActsAsFerretError; end

  # default field list for use with a shared index. Set it globally to
  # avoid having to specify the same :default_field value in every class using
  # the shared index.
  @@shared_index_default_fields = nil
  mattr_accessor :shared_index_default_fields

  @@logger = nil
  mattr_accessor :logger

  # global Hash containing all multi indexes created by all classes using the plugin
  # key is the concatenation of alphabetically sorted names of the classes the
  # searcher searches.
  @@multi_indexes = Hash.new
  def self.multi_indexes; @@multi_indexes end

  # global Hash containing the ferret indexes of all classes using the plugin
  # key is the index directory.
  @@ferret_indexes = Hash.new
  def self.ferret_indexes; @@ferret_indexes end

  # holds per-index configuration, key is the index name
  @@index_definitions = {}
  # mapping from class name to index name
  @@index_using_classes = {}
  def self.index_definitions; @@index_definitions end

  DEFAULT_FIELD_OPTIONS = {
    :store       => :no, 
    :highlight   => :yes, 
    :index       => :yes, 
    :term_vector => :with_positions_offsets,
    :boost       => 1.0
  }

  def self.field_config_for(fieldname, options = {})
    config = DEFAULT_FIELD_OPTIONS.merge options
    config[:term_vector] = :no if config[:index] == :no
    config.delete :via
    config.delete :boost if config[:boost].is_a?(Symbol) # dynamic boosts aren't handled here
    return config
  end

  def self.build_field_config(fields)
    field_config = {}
    case fields
    when Array
      fields.each { |name| field_config[name] = field_config_for name }
    when Hash
      fields.each { |name, options| field_config[name] = field_config_for name, options }
    else raise InvalidArgumentError.new(":fields option must be Hash or Array")
    end if fields
    return field_config
  end

  # Globally declares an index.
  #
  # Use the index in your model classes with
  #    acts_as_ferret :index => :index_name
  #
  # This method is also used to implicitly declare an index when you use the
  # acts_as_ferret call without the :index option as usual.
  def self.define_index(name, options = {})
    name = name.to_sym
    raise IndexAlreadyDefined.new(name) if index_definitions.has_key?(name)
    index_definition = {
      :index_dir => "#{ActsAsFerret::index_dir}/#{name}",
      :store_class_name => false,
      :name => name,
      :single_index => false,
      :reindex_batch_size => 1000,
      :ferret => {},
      :ferret_fields => {},             # list of indexed fields that will be filled later
      :enabled => true,                 # used for class-wide disabling of Ferret
      :mysql_fast_batches => true,      # turn off to disable the faster, id based batching mechanism for MySQL
      :raise_drb_errors => false        # handle DRb connection errors by default
    }.update( options )

    index_definition[:registered_models] = []
    
    # build ferret configuration
    index_definition[:ferret] = {
      :or_default          => false, 
      :handle_parse_errors => true,
      :default_field       => nil,              # will be set later on
      #:max_clauses => 512,
      #:analyzer => Ferret::Analysis::StandardAnalyzer.new,
      # :wild_card_downcase => true
    }.update( options[:ferret] || {} )

    index_definition[:user_default_field] = index_definition[:ferret][:default_field]

    # these properties are somewhat vital to the plugin and shouldn't
    # be overwritten by the user:
    index_definition[:ferret].update(
      :key               => (index_definition[:store_class_name] ? [:id, :class_name] : :id),
      :path              => index_definition[:index_dir],
      :auto_flush        => true, # slower but more secure in terms of locking problems TODO disable when running in drb mode?
      :create_if_missing => true
    )


    unless index_definition[:remote]
      ActsAsFerret::ensure_directory index_definition[:index_dir] 
      index_definition[:index_base_dir] = index_definition[:index_dir]
      index_definition[:index_dir] = find_last_index_version(index_definition[:index_dir])
      logger.debug "using index in #{index_definition[:index_dir]}"
    end

    # field config
    index_definition[:ferret_fields] = build_field_config( options[:fields] )
    index_definition[:ferret_fields].update build_field_config( options[:additional_fields] )

    index_definitions[name] = index_definition
    return index_definition
  end
 
  # called internally by the acts_as_ferret method
  #
  # TODO part of the given options which might influence the indexing of
  # records of a special class (such as analyzer, field configuration(i.e.
  # dynamic boosts) need to be copied to the returned per-class config so they
  # are taken into account properly even when multiple classes use conflicting
  # settings)
  def self.register_class_with_index(clazz, index_name, options = {})
    index_name = index_name.to_sym
    @@index_using_classes[clazz.name] = index_name
    if definition = index_definitions[index_name]
      definition[:shared_index] = true
      # TODO: add class-declared options to the index definition? which?
      # merge fields from this acts_as_ferret call with predefined fields
      already_defined_fields = definition[:ferret_fields]
      field_config = build_field_config options[:fields]
      field_config.update build_field_config( options[:additional_fields] )
      field_config.each do |field, config|
        if already_defined_fields.has_key?(field)
          logger.info "ignoring redefinition of ferret field #{field}"
        else
          already_defined_fields[field] = config
          logger.info "adding new field #{field} from class #{clazz.name} to index #{index_name}"
        end
      end
    else
      # index definition on the fly
      # default to all attributes of this class
      options[:fields] ||= clazz.new.attributes.keys.map { |k| k.to_sym }
      define_index index_name, options
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
    definition = index_definitions[index_name]
    unless definition[:user_default_field]
      # grab all tokenized fields
      definition[:ferret][:default_field] = definition[:ferret_fields].keys.select do |field|
        definition[:ferret_fields][field][:index] != :untokenized
      end
      logger.info "default field list for index #{index_name}: #{definition[:ferret][:default_field].inspect}"
    end

    # TODO: duped definition more or less worthless...
    definition[:registered_models] << clazz
    return definition.dup
  end

  # returns the index with the given name.
  def self.get_index(name)
    definition = index_definitions[name]
    path = definition[:index_dir]
    ferret_indexes[path] ||= create_index_instance(definition)
  end

  # creates a new Index instance.
  def self.create_index_instance(definition)
    if definition[:remote]
      RemoteIndex
    elsif definition[:shared_index]
      SharedIndex
    else
      LocalIndex
    end.new(definition)
  end

  def self.rebuild_index(name)
    idx = get_index(name)
    idx.rebuild_index
  end

  # Switches the named index to a new index directory.
  # Used by the DRb server when switching to a new index version.
  def self.change_index_dir(name, new_dir)
    logger.debug "[#{name}] changing index dir to #{new_dir}"
    definition = @@index_definitions[name]
    idx = get_index(name)

    # store index with the new dir as key. This prevents the aaf_index method
    # from opening another index instance later on.
    ferret_indexes[new_dir] = idx

    old_dir = definition[:index_dir]
    definition[:index_dir] = definition[:ferret][:path] = new_dir

    # clean old reference to index
    ActsAsFerret::ferret_indexes.delete old_dir
    idx.reopen!
    logger.debug "[#{name}] index dir is now #{new_dir}"
  end

  # returns the index definition for the index used by the given class or
  # index_name
  def self.index_definition(clazz_or_index_name)
    logger.debug "index_definition for #{clazz_or_index_name}"
    # TODO: inheritance hochhangeln (Content, ContentBase)
    index_name = clazz_or_index_name.is_a?(Class) ? 
      @@index_using_classes[clazz_or_index_name.name] : clazz_or_index_name
    logger.debug "index_definition for #{index_name}"
    index_definitions[index_name]
  end

  # find the most recent version of an index
  def self.find_last_index_version(basedir)
    # check for versioned index
    versions = Dir.entries(basedir).select do |f| 
      dir = File.join(basedir, f)
      File.directory?(dir) && File.file?(File.join(dir, 'segments')) && f =~ /^\d+(_\d+)?$/
    end
    if versions.any?
      # select latest version
      versions.sort!
      File.join basedir, versions.last
    else
      basedir
    end
  end

  def self.ensure_directory(dir)
    FileUtils.mkdir_p dir unless (File.directory?(dir) || File.symlink?(dir))
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
      options = options.dup
      options.delete(:boost) if options[:boost].is_a?(Symbol)
      options.delete(:via)
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


