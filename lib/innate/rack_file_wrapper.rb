module Innate
  class RackFileWrapper
    def initialize(root, cache_control = nil)
      @file = Rack::File.new(root, cache_control)
    end

    def call(env)
      status, header, body = @file.call(env)

      if status == 403
        unless Rack::File::ALLOWED_VERBS.include?(env['REQUEST_METHOD'])
          body = "File not Found: #{Rack::Utils.unescape(env['PATH_INFO'])}\n"
          return 404, {
            'Content-Type' => 'text/plain',
            'Content-Length' => body.size,
            'X-Cascade' => 'pass',
          }, [body]
        end
      end

      return status, header, body
    end
  end
end
