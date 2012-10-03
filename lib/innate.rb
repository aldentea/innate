# What can be done with fewer assumptions is done in vain with more.
# -- William of Ockham (ca. 1285-1349)
#
# Name-space of Innate, just about everything goes in here.
#
# The only exception is Logger::ColorFormatter.
#
module Innate
  ROOT = File.expand_path(File.dirname(__FILE__))

  unless $LOAD_PATH.any?{|lp| File.expand_path(lp) == ROOT }
    $LOAD_PATH.unshift(ROOT)
  end

  # stdlib
  require 'digest/md5'
  require 'digest/sha1'
  require 'digest/sha2'
  require 'find'
  require 'ipaddr'
  require 'logger'
  require 'pathname'
  require 'pp'
  require 'set'
  require 'thread'
  require 'uri'

  # 3rd party
  require 'rack'

  # innate core
  require 'innate/version'
  require 'innate/traited'
  require 'innate/trinity'
  require 'innate/options/dsl'
  require 'innate/options/stub'
  require 'innate/dynamap'

  # innate full
  require 'innate/lru_hash'
  require 'innate/cache'
  require 'innate/node'
  require 'innate/options'
  require 'innate/log'
  require 'innate/state'
  require 'innate/current'
  require 'innate/mock'
  require 'innate/adapter'
  require 'innate/action'
  require 'innate/helper'
  require 'innate/view'
  require 'innate/session'
  require 'innate/session/flash'
  require 'innate/route'

  extend Trinity

  # Contains all the module functions for Innate, we keep them in a module so
  # Ramaze can simply use them as well.
  module SingletonMethods
    PROXY_OPTIONS = { :port => 'adapter.port', :host => 'adapter.host',
                      :adapter => 'adapter.handler' }
    # The method that starts the whole business.
    #
    # Call Innate.start after you defined your application.
    #
    # Usually, this is a blocking call and will not return until the adapter
    # has finished, which usually happens when you kill the application or hit
    # ^C.
    #
    # We do return if options.started is true, which indicates that all you
    # wanted to do is setup the environment and update options.
    #
    # @example usage
    #
    #   # passing options
    #   Innate.start :adapter => :mongrel, :mode => :live
    #
    # @return [nil] if options.started is true
    # @yield [MiddlewareCompiler]
    # @param [Proc] block will be passed to {middleware!}
    #
    # @option param :host    [String]  ('0.0.0.0')
    #   IP address or hostname that we respond to - 0.0.0.0 for all
    # @option param :port    [Fixnum]  (7000)
    #   Port for the server
    # @option param :started [boolean] (false)
    #   Indicate that calls Innate::start will be ignored
    # @option param :adapter [Symbol]  (:webrick)
    #   Web server to run on
    # @option param :setup   [Array]   ([Innate::Cache, Innate::Node])
    #   Will send ::setup to each element during Innate::start
    # @option param :header  [Hash]    ({'Content-Type' => 'text/html'})
    #   Headers that will be merged into the response before Node::call
    # @option param :trap    [String]  ('SIGINT')
    #   Trap this signal to issue shutdown, nil/false to disable trap
    # @option param :mode    [Symbol]  (:dev)
    #   Indicates which default middleware to use, (:dev|:live)
    def start(options = {})
      root, file = options.delete(:root), options.delete(:file)
      innate_options = Innate.options

      found_root = go_figure_root(caller, :root => root, :file => file)
      innate_options.roots = [*found_root] if found_root

      # Convert some top-level option keys to the internal ones that we use.
      PROXY_OPTIONS.each{|given, proxy| options[proxy] = options[given] }
      options.delete_if{|key, value| PROXY_OPTIONS[key] || value.nil? }

      # Merge the user's given options into our existing set, which contains defaults.
      innate_options.merge!(options)

      setup_dependencies

      return if innate_options.started
      innate_options.started = true

      signal = innate_options.trap
      trap(signal){ stop(10) } if signal

      start!
    end

    def start!(mode = options[:mode])
      recompile_middleware unless app

      Adapter.start(app)
    end

    def stop(wait = 3)
      Log.info("Shutdown within #{wait} seconds")
      Timeout.timeout(wait){ teardown_dependencies }
      Timeout.timeout(wait){ exit }
    ensure
      exit!
    end

    def setup_dependencies
      options[:setup].each{|obj| obj.setup if obj.respond_to?(:setup) }
    end

    def teardown_dependencies
      options[:setup].each{|obj| obj.teardown if obj.respond_to?(:teardown) }
    end

    def setup
      options.mode ||= (ENV['RACK_ENV'] || :dev)
    end

    # Treat Innate like a rack application, pass the rack +env+ and optionally
    # the +mode+ the application runs in.
    #
    # @param [Hash] env rack env
    # @param [Symbol] mode indicates the mode of the application
    # @default mode options.mode
    # @return [Array] with [body, header, status]
    # @author manveru
    def call(env)
      app.call(env)
    end

    attr_accessor :app

    def recompile_middleware(mode = options[:mode])
      Innate.app = send("middleware_#{mode}")
    end

    def middleware_core
      roots, publics = options[:roots], options[:publics]
      joined = roots.map{|root| publics.map{|public| ::File.join(root, public)}}

      Rack::Cascade.new(
        joined.flatten.map{|public_root| Rack::File.new(public_root) } <<
        Current.new(Route.new(DynaMap), Rewrite.new(DynaMap)), [404, 405])
    end

    def middleware_dev
      Rack::Builder.new do
        [ Rack::Lint, Rack::Head, Rack::ContentLength, Rack::CommonLogger,
          Rack::ShowExceptions, Rack::ShowStatus, Rack::ConditionalGet,
          [Rack::Reloader, 2],
        ].each{|m| use(*m) }
        run Innate.middleware_core
      end
    end

    def middleware_live
      Rack::Builder.new do
        [ Rack::Head, Rack::ContentLength, Rack::CommonLogger,
          Rack::ShowStatus, Rack::ConditionalGet,
        ].each{|*m| use(*m) }
        run Innate.middleware_core
      end
    end

    # @example Innate can be started by:
    #
    #   Innate.start :file => __FILE__
    #   Innate.start :root => File.dirname(__FILE__)
    #
    # Either setting will surpress the warning that might show up on startup
    # and tells you it couldn't find an explicit root.
    #
    # In case these options are not passed we will try to figure out a file named
    # `start.rb` in the process' working directory and assume it's a valid point.
    def go_figure_root(backtrace, options)
      if root = options[:root]
        root
      elsif file = options[:file]
        File.dirname(file)
      elsif File.file?('start.rb')
        Dir.pwd
      else
        root = File.dirname(backtrace[0][/^(.*?):\d+/, 1])
        Log.warn "No explicit root folder found, assuming it is #{root}"
        root
      end
    end
  end

  extend SingletonMethods
end
