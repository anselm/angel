#!/usr/local/bin/ruby

ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

require 'rubygems'
require "config/environment"
require 'json'
require 'open-uri'
require 'lib/aggregator/twitter_base.rb'
require 'lib/aggregator/twitter_aggregate.rb'
require 'lib/query_support.rb'

platform = YAML.load(open("config/platform.yml"))

$running = true
Signal.trap("TERM") do
  $running = false
end

while($running) do
  TwitterSupport::aggregate
  sleep 600
end

