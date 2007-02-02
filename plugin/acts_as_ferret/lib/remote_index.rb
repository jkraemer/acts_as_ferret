require 'drb'
module ActsAsFerret #:nodoc:

      # Proof of concept for a client connecting to a remote ferret server
      # (ferret_server.rb). Still very basic.
      class RemoteIndex
        def initialize(config)
          @config = config
          @ferret_config = config[:ferret]
          @server = DRbObject.new(nil, config[:remote])
        end

        def find_id_by_contents(q, options = {}, &block)
          results = @server.find_id_by_contents(@config[:name], q, options)
          total_hits = results[0]
          results[1].each do |hit|
            model = hit[:class_name] || @config[:class_name]
            if block_given?
              yield model, hit[:id], hit[:score]
            else
              hit[:class_name] = model
            end
          end
          return block_given? ? total_hits : results[1]
        end

        def add_to_index(*docs)
          @server.add_to_index(@config[:name], docs)
        end
        alias :<< :add_to_index

        def query_delete(query)
          @server.query_delete(@config[:name], query.to_s)
        end

        def create_index
          @server.create_index(@config[:name])
        end

        def flush

        end

        def optimize

        end

        def close

        end
      end
end
