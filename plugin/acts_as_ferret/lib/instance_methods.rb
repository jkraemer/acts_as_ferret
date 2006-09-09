module FerretMixin
  module Acts #:nodoc:
    module ARFerret #:nodoc:

      module InstanceMethods
        include MoreLikeThis
        
        # re-eneable ferret indexing after a call to #disable_ferret
        def ferret_enable; @ferret_disabled = nil end
       
        # returns true if ferret indexing is enabled
        def ferret_enabled?; @ferret_disabled.nil? end

        # Disable Ferret for a specified amount of time. ::once will disable
        # Ferret for the next call to #save (this is the default), ::always will 
        # do so for all subsequent calls.
        # To manually trigger reindexing of a record, you can call #ferret_update 
        # directly. 
        #
        # When given a block, this will be executed without any ferret indexing of 
        # this object taking place. The optional argument in this case can be used 
        # to indicate if the object should be indexed after executing the block
        # (::index_when_finished). Automatic Ferret indexing of this object will be 
        # turned on after the block has been executed.
        def disable_ferret(option = :once)
          if block_given?
            @ferret_disabled = :always
            yield
            ferret_enable
            ferret_update if option == :index_when_finished
          elsif [:once, :always].include?(option)
            @ferret_disabled = option
          else
            raise ArgumentError.new("Invalid Argument #{option}")
          end
        end

        # add to index
        def ferret_create
          if ferret_enabled?
            logger.debug "ferret_create/update: #{self.class.name} : #{self.id}"
            self.class.ferret_index << self.to_doc
          else
            ferret_enable if @ferret_disabled == :once
          end
          @ferret_enabled = true
          true # signal success to AR
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
          true # signal success to AR
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
          return doc
        end
      end

    end
  end
end
