#
# Background aggregation strategy
# Aug 5 2009
#
# 1) Aggregate
#
# The aggregator can periodically aggregate parties
# The aggregator can periodically aggregate term searches
# The aggregator can periodically aggregate term searches in a geographic area
# The aggregator does not deal with tracing out friend networks but it will add new people it runs across.
# The aggregator avoid collecting dupes.
# The aggregator avoids rate limits
#

require 'lib/twitter_support/twitter_base.rb'
require 'lib/twitter_support/twitter_collect.rb'
require 'lib/twitter_support/twitter_reap.rb'

class TwitterSupport

	#
	# TODO migrate the controller query parse logic down here
	#
	def self.aggregate(q)

		# reap old data TODO

		ActionController::Base.logger.info "Query: aggregation of a query starting #{Time.now}"

		map_s = q[:s]
		map_w = q[:w]
		map_n = q[:n]
		map_e = q[:e]

		# did the user supply some people as the anchor of a search?
		# refresh them and get their friends ( this is cheap and can be done synchronously )
		q[:parties] = self.twitter_get_parties(q[:partynames])
		q[:friends] = self.twitter_get_friends(q[:parties])
		# q[:acquaintances] = self.twitter_get_friends(q[:friends])  # too expensive 

		# pull fresh data. use different strategies based on what we got from user
		if q[:parties].length > 0
			# if user supplied people then try one of these strategies
			strategy = "friends_yql"
			case strategy
			when "bruteforce"
				# in this strategy we collect all the traffic of all the friends one by one unfiltered. prohibitively expensive.
				q[:parties].each { |party| self.twitter_refresh_timeline(party) }
				q[:friends].each { |party| self.twitter_refresh_timeline(party) }
			when "friends_twitter"
				# in this strategy we look at the core participants only and collect their friends indirectly
				# TODO unfortunately twitter does not allow this.
				# q[:parties].each { |party| self.twitter_refresh_friends_timeline(party) }
			when "friends_yql"
				# in this strategy we talk to an intermediary like YQL and query on the set of friends for recent traffic.
				# in this way we CAN do the query that we hope to do with friends_twitter
				# we could also query on search terms if any and or apply a default search filter? like "help" and "i need"?
				ActionController::Base.logger.info "query: using a yql search for parties"
				self.yql_twitter_get_timelines(q[:parties])
				self.yql_twitter_get_timelines(q[:friends])
				# self.yql_twitter_get_timelines(q[:acquaintances])
			when "recent"
				# in this strategy we look at the core members only and get their friends recent timelines.
			end
		else
			# if there are no people to anchor the search then just let twitter do the search
			ActionController::Base.logger.info "query: using a general search strategy looking for #{q[:words].join(' ')} near #{map_s} #{map_w} #{map_n} #{map_e}"
			self.twitter_search(q[:words],map_s,map_n,map_w,map_e) if q[:words] && q[:words].length > 0
		end

		# TODO idea
		# after an ordinary twitter search i would like to take the persons that were related to these posts and get them in more detail
		# something like this:
		# and get their friends too...
		# this would help anchor a search quite a bit showing more context
		# later i could even ask yql for those timelines in turn...
		#		q[:parties] = self.twitter_get_parties(q[:partynames])
		#		q[:friends] = self.twitter_get_friends(q[:parties])

		ActionController::Base.logger.info "Query: aggregation of a set has finished updating external data sources at time #{Time.now}"

		return q
	end

	def self.aggregate_memoize(q,synchronous=false)
		# in some cases we want to cache user queries TODO
		if(synchronous == true)
			self.aggregate(q)
		end
	end

	def self.aggregate_all
		# visit all queries
		# perform them
		# kill them after a week or so
	end

end

