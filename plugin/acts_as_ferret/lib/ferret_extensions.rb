module Ferret
  class Index::Index
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
  class Index::MultiReader
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
  class Search::SortField
    def _dump(depth)
      to_s
    end

    def self._load(string)
      case string
        when /<DOC(_ID)?>!/         : Ferret::Search::SortField::DOC_ID_REV
        when /<DOC(_ID)?>/          : Ferret::Search::SortField::DOC_ID
        when '<SCORE>!'             : Ferret::Search::SortField::SCORE_REV
        when '<SCORE>'              : Ferret::Search::SortField::SCORE
        when /^(\w+):<(\w+)>(\!)?$/ : new($1.to_sym, :type => $2.to_sym, :reverse => !$3.nil?)
        else raise "invalid value: #{string}"
      end
    end
  end

  # add marshalling support to Sort
  class Search::Sort
    def _dump(depth)
      to_s
    end

    def self._load(string)
      if string =~ /^Sort\[(.+?)(, <DOC>(\!)?)?\]$/
        sort_fields = $1.split(',').map do |value| 
          value.strip!
          Ferret::Search::SortField._load value
        end
      new sort_fields.compact
      else
        raise "invalid value: #{string}"
      end
    end
  end
end
