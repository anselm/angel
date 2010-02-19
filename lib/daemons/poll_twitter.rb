#!/usr/local/bin/ruby

ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

require 'rubygems'
require File.dirname(__FILE__) + "/../../config/environment"
require 'json'
require 'open-uri'
require 'twitter_support/twitter_base.rb'
require 'twitter_support/twitter_aggregate.rb'
require 'query_support.rb'

platform = YAML.load(open(File.dirname(__FILE__) + "/../../config/platform.yml"))

$running = true
Signal.trap("TERM") do
  $running = false
end

while($running) do

  #
  # TODO; have a number of memoized queries that can be edited from an admin panel
  # for now lets just start with querying off of one root as a test
  #
  question = "@meedan"
  synchronous = true

  #
  # go ahead and fetch any new content related to query string 
  #
  QuerySupport::query(question,0,0,0,0,synchronous)
 
  #
  # sleep for 60 minutes
  # 
  sleep 3600

end

