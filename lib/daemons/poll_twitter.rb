#!/usr/local/bin/ruby

ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

require 'rubygems'
require File.dirname(__FILE__) + "/../../config/environment"
require 'json'
require 'open-uri'
require 'aggregator/twitter_base.rb'
require 'aggregator/twitter_aggregate.rb'
require 'query_support.rb'
# require 'lib/settings.rb'

platform = YAML.load(open(File.dirname(__FILE__) + "/../../config/platform.yml"))

$running = true
Signal.trap("TERM") do
  $running = false
end

while($running) do

  # update some not recently updated people
  TwitterSupport::aggregate

  # sleep for a spell
  sleep 600

end

