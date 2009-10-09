module Rack
  class Request
    # didn't want to go fishing for this in the plugin code
    # this implementation detail would hopefull come from Rack
    def async_callback(*args) 
      EM.next_tick { env["async.callback"].call *args }
    end
  end
  
  class Router
    %w(get post put delete).each do |type|
      send(:eval, <<RUBY                                      
        def #{type}(path, options)                        # def get(path, options)
          map path {:method => '#{type}'}.merge(options)  #   map path{:method => 'get'}.merge(options)
        end                                               # end
      RUBY)
    end
  end
end