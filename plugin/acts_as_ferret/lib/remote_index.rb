require 'drb'
module ActsAsFerret

  class RemoteIndex < AbstractIndex

    def initialize(config)
      @config = config
      @ferret_config = config[:ferret]
      @server = DRbObject.new(nil, config[:remote])
    end

    def method_missing(name, *args)
      args.unshift @config[:class_name]
      @server.send(name, args)
    end

    def find_id_by_contents(q, options = {}, &block)
      # first get all the results, then do the yielding
      # TODO: check out if/how the yielding works out if done directly via drb
      results = @server.find_id_by_contents(@config[:class_name], q, options)
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

    # add record to index
    def add(record)
      @server.add @config[:class_name], record.id  # dont serialize the whole record via drb
    end
    alias << add

    # delete record from index
    def remove(record)
      @server.remove @config[:class_name], record.id  # dont serialize the whole record via drb
    end

  end

end
