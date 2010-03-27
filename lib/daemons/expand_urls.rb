#!/usr/local/bin/ruby

ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

require 'rubygems'
require File.dirname(__FILE__) + "/../../config/environment"
require 'json'
require 'open-uri'
require 'aggregator/twitter_base.rb'
require 'aggregator/twitter_collect.rb'
require 'aggregator/twitter_aggregate.rb'
require 'query_support.rb'

TwitterSupport::expand_all_urls

