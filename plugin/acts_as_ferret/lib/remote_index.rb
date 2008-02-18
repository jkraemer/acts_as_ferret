require 'drb'
module ActsAsFerret

  # This index implementation connects to a remote ferret server instance. It
  # basically forwards all calls to the remote server.
  class RemoteIndex < AbstractIndex

    def initialize(config)
      super
      @server = DRbObject.new(nil, config[:remote])
    end

    def method_missing(method_name, *args)
      args.unshift model_class_name
      handle_drb_error { @server.send(method_name, *args) }
    end

    # Proxy any methods that require special return values in case of errors
    { 
      :highlight => [] 
    }.each do |method_name, default_result|
      define_method method_name do |*args|
        args.unshift model_class_name
        handle_drb_error(default_result) { @server.send method_name, *args }
      end
    end

    def find_id_by_contents(q, options = {}, &proc)
      total_hits, results = handle_drb_error([0, []]) { @server.find_id_by_contents(model_class_name, q, options) }
      block_given? ? yield_results(total_hits, results, &proc) : [ total_hits, results ]
    end

    def id_multi_search(query, models, options, &proc)
      total_hits, results = handle_drb_error([0, []]) { @server.id_multi_search(model_class_name, query, models, options) }
      block_given? ? yield_results(total_hits, results, &proc) : [ total_hits, results ]
    end

    # add record to index
    def add(record)
      handle_drb_error { @server.add record.class.name, record.to_doc }
    end
    alias << add

    private

    def handle_drb_error(return_value_in_case_of_error = false)
      yield
    rescue DRb::DRbConnError => e
      logger.error "DRb connection error: #{e}"
      logger.warn e.backtrace.join("\n")
      raise e if index_definition[:raise_drb_errors]
      return_value_in_case_of_error
    end

    def yield_results(total_hits, results)
      results.each do |result|
        yield result[:model], result[:id], result[:score], result[:data]
      end
      total_hits
    end

    def model_class_name
      index_definition[:class_name]
    end

  end

end
