module ActsAsFerret #:nodoc:
  
      # this class is not threadsafe
      class MultiIndex
        
        def initialize(indexes, options = {})
          # ensure all models indexes exist
          @indexes = indexes
          indexes.each { |i| i.ensure_index_exists }
          default_fields = indexes.inject([]) do |fields, idx| 
            fields + [ idx.index_definition[:ferret][:default_field] ]
          end.flatten.uniq
          @options = {
            :default_field => default_fields
          }.update(options)
          @logger = IndexLogger.new(ActsAsFerret::logger, "multi: #{indexes.map(&:index_name).join(',')}")
        end
        
        # Queries multiple Ferret indexes to retrieve model class, id and score for 
        # each hit. Use the models parameter to give the list of models to search.
        # If a block is given, model, id and score are yielded and the number of 
        # total hits is returned. Otherwise [total_hits, result_array] is returned.
        def find_ids(query, options = {})
          result = []
          lazy_fields = determine_stored_fields options
          total_hits = search_each(query, options) do |hit, score|
            doc = index[hit]
            # fetch stored fields if lazy loading
            data = extract_lazy_fields(doc, lazy_fields)
            raise "':store_class_name => true' required for multi_search to work" if doc[:class_name].blank?
            if block_given?
              yield doc[:class_name], doc[:id], score, doc, data
            else
              result << { :model => doc[:class_name], :id => doc[:id], :score => score, :data => data }
            end
          end
          return block_given? ? total_hits : [ total_hits, result ]
        end

        def total_hits(q, options = {})
          search(q, options).total_hits
        end
        
        def search(query, options={})
          query = process_query(query)
          @logger.debug "parsed query: #{query.to_s}"
          searcher.search(query, options)
        end

        def search_each(query, options = {}, &block)
          query = process_query(query)
          searcher.search_each(query, options, &block)
        end

        # checks if all our sub-searchers still are up to date
        def latest?
          #return false unless @reader
          # segfaults with 0.10.4 --> TODO report as bug @reader.latest?
          @reader and @reader.latest?
          #@sub_readers.each do |r| 
          #  return false unless r.latest? 
          #end
          #true
        end
         
        def searcher
          ensure_searcher
          @searcher
        end
        
        def doc(i)
          searcher[i]
        end
        alias :[] :doc
        
        def query_parser
          @query_parser ||= Ferret::QueryParser.new(@options)
        end
        
        def process_query(query)
          query = query_parser.parse(query) if query.is_a?(String)
          return query
        end

        def close
          @searcher.close if @searcher
          @reader.close if @reader
        end

        protected

          def ensure_searcher
            unless latest?
              @sub_readers = @indexes.map { |idx| 
                begin
                  reader = Ferret::Index::IndexReader.new(idx.index_definition[:index_dir])
                  @logger.debug "sub-reader opened: #{reader}"
                  reader
                rescue Exception
                  raise "error opening reader on index for class #{clazz.inspect}: #{$!}"
                end
              }
              close
              @reader = Ferret::Index::IndexReader.new(@sub_readers)
              @searcher = Ferret::Search::Searcher.new(@reader)
            end
          end

      end # of class MultiIndex

end
