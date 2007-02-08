module ActsAsFerret
  
  module SharedIndexClassMethods

    # override the standard find_by_contents for searching a shared index
    #
    # TODO: slow on large result sets - fetches result set objects one-by-one
    def find_by_contents(q, options = {}, find_options = {})
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
      total_hits = aaf_index.find_id_by_contents(q, options) do |model, id, score|
        begin
          o = model_find(model, id, find_options.dup)
        rescue
          logger.error "unable to find #{model} record with id #{id}, you should rebuild your index"
        else
          o.ferret_score = score
          result << o
        end
      end
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

