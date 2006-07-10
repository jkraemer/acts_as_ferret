module FerretMixin
  module Acts #:nodoc:
    module ARFerret #:nodoc:
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
        end
        
        def search(query, options={})
          #puts "querystring: #{query.to_s}"
          query = process_query(query)
          #puts "parsed query: #{query.to_s}"
          searcher.search(query, options)
        end

        # checks if all our sub-searchers still are up to date
        def latest?
          return false unless @searcher
          @sub_searchers.each do |s| 
            return false unless s.reader.latest? 
          end
          true
        end

        def ensure_searcher
          unless latest?
            field_names = Set.new
            @sub_searchers = @model_classes.map { |clazz| 
              begin
                searcher = Ferret::Search::IndexSearcher.new(clazz.class_index_dir)
              rescue Exception
                puts "error opening #{clazz.class_index_dir}: #{$!}"
              end
              if searcher.reader.respond_to?(:get_field_names)
                field_names << searcher.reader.send(:get_field_names).to_set
              elsif clazz.fields_for_ferret
                field_names << clazz.fields_for_ferret.to_set
              else
                puts <<-END
  unable to retrieve field names for class #{clazz.name}, please 
  consider naming all indexed fields in your call to acts_as_ferret!
                END
                clazz.content_columns.each { |col| field_names << col.name }
              end
              searcher
            }
            @searcher = Ferret::Search::MultiSearcher.new(@sub_searchers)
            @field_names = field_names.flatten.to_a
            @query_parser = nil # trigger re-creation from new field_name array
          end
        end
         
        def searcher
          ensure_searcher
          @searcher
        end
        
        def doc(i)
          searcher.doc(i)
        end
        
        def query_parser
          unless @query_parser
            ensure_searcher # we dont need the searcher, but the @field_names array is built by this function, too
            @query_parser ||= Ferret::QueryParser.new(
                                @options[:default_search_field],
                                { :fields => @field_names }.merge(@options)
                              )
          end
          @query_parser
        end
        
        def process_query(query)
          query = query_parser.parse(query) if query.is_a?(String)
          return query
        end

      end # of class MultiIndex

    end
  end
end
