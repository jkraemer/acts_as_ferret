begin
  require 'rdig'
rescue LoadError
end
module ActsAsFerret

  # The RdigAdapter is automatically included into your model if you specify
  # the +:rdig+ options hash in your call to acts_as_ferret. It overrides
  # several methods declared by aaf to retrieve documents with the help of
  # RDig's http crawler when you call rebuild_index.
  module RdigAdapter

    if defined?(RDig)

      def self.included(target)
        target.extend ClassMethods
        target.send :include, InstanceMethods
      end

      # Indexer class to replace RDig's original indexer
      class Indexer
        include MonitorMixin
        def initialize(batch_size, model_class, &block)
          @batch_size = batch_size
          @model_class = model_class
          @documents = []
          @offset = 0
          @block = block
          super()
        end

        def add(doc)
          synchronize do
            @documents << @model_class.new(doc.uri.to_s, doc)
            process_batch if @documents.size >= @batch_size
          end
        end
        alias << add

        def close
          synchronize do
            process_batch
          end
        end

        protected
        def process_batch
          RAILS_DEFAULT_LOGGER.info "RdigAdapter::Indexer#process_batch: #{@documents.size} docs in queue, offset #{@offset}"
          @block.call @documents, @offset
          @offset += @documents.size
          @documents = []
        end
      end
      
      module ClassMethods
        # overriding aaf to return the documents fetched via RDig
        def records_for_rebuild(batch_size = 1000, &block)
          crawler = RDig::Crawler.new rdig_config, logger
          indexer = Indexer.new(batch_size, self, &block)
          crawler.instance_variable_set '@indexer', indexer
          crawler.crawl
        ensure
          indexer.close
        end

        # overriding aaf to skip reindexing records changed during the rebuild
        # when rebuilding with the rake task
        def records_modified_since(time)
          []
        end

        def rdig_config
          cfg = RDig.configuration.dup
          cfg.index = nil
          aaf_configuration[:rdig][:crawler].each { |k,v| cfg.crawler.send :"#{k}=", v } if aaf_configuration[:rdig][:crawler]
          if aaf_configuration[:rdig][:content_extraction]
            cfg.content_extraction = OpenStruct.new( :hpricot => OpenStruct.new( aaf_configuration[:rdig][:content_extraction] ) )
          end
          cfg
        end

        # overriding aaf to enforce loading page title and content from the
        # ferret index
        def find_with_ferret(q, options = {}, find_options = {})
          options[:lazy] = true
          super
        end

        def find_for_id(id)
          new id
        end
      end

      module InstanceMethods
        def initialize(uri, rdig_document = nil)
          @id = uri
          @rdig_document = rdig_document
        end

        # Title of the document.
        # Use the +:title_tag_selector+ option to declare the hpricot expression
        # that should be used for selecting the content for this field.
        def title
          @rdig_document.title
        end

        # Content of the document.
        # Use the +:content_tag_selector+ option to declare the hpricot expression
        # that should be used for selecting the content for this field.
        def content
          @rdig_document.body
        end

        # Url of this document.
        def id
          @id
        end

        def to_s
          "Page at #{id}, title: #{title}"
        end
      end
    end
  end
  
end
