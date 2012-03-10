require 'bacon'
require 'rack/test'
require File.expand_path('../../', __FILE__) unless defined?(Innate)

Bacon.summary_on_exit

ENV['RACK_ENV'] = 'TEST'

module Innate
  # skip starting adapter
  options.started = true
  options.mode = :spec
end

shared :rack_test do
  Innate.setup_dependencies
  extend Rack::Test::Methods

  def app; Innate; end
end
