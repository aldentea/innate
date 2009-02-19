require 'spec/helper'

Innate.options.app.root = File.dirname(__FILE__)
class SpecHelperPartial
  Innate.node '/'

  def index
    '<html><head><title><%= render_partial("/title") %></title></head></html>'
  end

  def title
    "Title"
  end

  def with_params
    '<html><head><title><%= render_partial("/message", :msg => "hello") %></title></head></html>'
  end

  def message
    "Message: #{request[:msg]}"
  end

  def composed
    @here = 'there'
    'From Action | ' << render_template("partial.erb")
  end

  def recursive
    @n = 1
  end

  def without_ext
    render_template('partial')
  end
end

class SpecHelperPartialWithLayout < SpecHelperPartial
  Innate.node '/with_layout'
  layout('layout')
  view_root '/'

  def layout 
    '<h1>with layout</h1><%= @content %>'
  end
end

describe Innate::Helper::Partial do
  behaves_like :mock

  should 'render partials' do
    get('/').body.should == '<html><head><title>Title</title></head></html>'
  end

  should 'render partials with params' do
    get('/with_params').body.should == '<html><head><title>Message: hello</title></head></html>'
  end

  should 'be able to render a template in the current scope' do
    get('/composed').body.strip.should == "From Action | From Partial there"
  end

  should 'render_template in a loop' do
    get('/loop').body.gsub(/\s/,'').should == '12345'
  end

  should 'work recursively' do
    get('/recursive').body.gsub(/\s/,'').should == '{1{2{3{44}4}3}2}'
  end

  should 'not require file extension' do
    get('/without_ext').body.should == "From Partial \n"
  end

  should 'render template with layout' do
    get('/with_layout/without_ext').body.should == "<h1>with layout</h1>From Partial \n"
  end
end