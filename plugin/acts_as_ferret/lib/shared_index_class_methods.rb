module ActsAsFerret
  
  module SharedIndexClassMethods

    # override the standard find_by_contents for searching a shared index
    #
    # please note that records from different models will be fetched in
    # separate sql calls, so any sql order_by clause given with 
    # find_options[:order] will get ignored.
    #
    # TODO: slow on large result sets - fetches result set objects one-by-one
    def find_by_contents(q, options = {}, find_options = {})
      if order = find_options.delete(:order)
        logger.warn "dropping unused order_by clause #{order}"
      end
      id_arrays = {}
      result = []

      unless options[:models] == :all # search needs to be restricted by one or more class names
        options[:models] ||= [] 
        # add this class to the list of given models
        options[:models] << self unless options[:models].include?(self)
        # keep original query 
        original_query = q
        
        if original_query.is_a? String
          model_query = options[:models].map(&:name).join '|'
          q << %{ +class_name:"#{model_query}"}
        else
          q = Ferret::Search::BooleanQuery.new
          q.add_query(original_query, :must)
          model_query = Ferret::Search::BooleanQuery.new
          options[:models].each do |model|
            model_query.add_query(Ferret::Search::TermQuery.new(:class_name, model.name), :should)
          end
          q.add_query(model_query, :must)
        end
      end
      options.delete :models

      # get object ids for index hits
      rank = 0
      total_hits = aaf_index.find_id_by_contents(q, options) do |model, id, score|
        id_arrays[model] ||= {}
        # store result rank and score
        id_arrays[model][id] = [ rank += 1, score ]
      end

      # get objects for each model
      id_arrays.each do |model, id_array|
        model = model.constantize
        # merge conditions
        conditions = combine_conditions([ "#{model.table_name}.#{primary_key} in (?)", id_array.keys ], 
                                        find_options[:conditions])
        # fetch
        tmp_result = model.find(:all, find_options.merge(:conditions => conditions))
        # set scores
        tmp_result.each { |obj| obj.ferret_score = id_array[obj.id.to_s].last }
        # merge with result array
        result.concat tmp_result
      end

      # sort so results have the same order they had when originally retrieved
      # from ferret
      result.sort! { |a, b| id_arrays[a.class.name][a.id.to_s].first <=> id_arrays[b.class.name][b.id.to_s].first }

      return SearchResults.new(result, total_hits)
    end
    
    # determine all field names in the shared index
    # TODO unused
#    def single_index_field_names(models)
#      @single_index_field_names ||= (
#          searcher = Ferret::Search::Searcher.new(class_index_dir)
#          if searcher.reader.respond_to?(:get_field_names)
#            (searcher.reader.send(:get_field_names) - ['id', 'class_name']).to_a
#          else
#            puts <<-END
#unable to retrieve field names for class #{self.name}, please 
#consider naming all indexed fields in your call to acts_as_ferret!
#            END
#            models.map { |m| m.content_columns.map { |col| col.name } }.flatten
#          end
#      )
#
#    end
 
  end
end

