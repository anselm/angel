ENV["RAILS_ENV"] ||= defined?(Daemons) ? 'production' : 'development'

# FIXME: pull in the platform.yml for the tag(s)
# FEED = "http://twittervision.com/inaugreport.json"
EXTRACTOR = Regexp.new(/^(\w+?):\s(.*)$/m)

require 'rubygems'
require File.dirname(__FILE__) + "/../../config/environment"
#require "../../config/environment"
require 'json'
require 'open-uri'
# require 'twitterchive'
require 'twitter_support/twitter_base.rb'
require 'twitter_support/twitter_collect.rb'

platform = YAML.load(open(File.dirname(__FILE__) + "/../../config/platform.yml"))

$running = true
Signal.trap("TERM") do
  $running = false
end

while($running) do
  q = {}
  q[:partynames] = "anselm" # test for now
  q[:parties] = TwitterSupport::twitter_get_parties(q[:partynames])
  q[:friends] = TwitterSupport::twitter_get_friends(q[:parties])
  sleep 10

  # the above is good as a test however
  #   - i should walk the users or other anchors
  #   - i should update them if i need to
  #   - this should be done as a collection of say 10 at a time ideally
  #   - i should at least use yql
  #   - i should have an interactive diagnostic that shows the same

end

