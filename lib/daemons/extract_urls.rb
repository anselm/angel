#!/usr/local/bin/ruby

ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

require 'rubygems'
require File.dirname(__FILE__) + "/../../config/environment"
require 'json'
require 'open-uri'
require 'twitter_support/twitter_base.rb'
require 'twitter_support/twitter_collect.rb'
require 'twitter_support/twitter_aggregate.rb'
require 'query_support.rb'

TwitterSupport::attach_all_notes_to_all_urls

