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
require 'lib/twitter_support/twitter_reap.rb'

class TwitterSupport

	#
	# Aggregate
	#
	# in general the engine keeps track of the last time it polled twitter and yql and will not hammer on them if not needed
	#
	#

	def self.aggregate_memoize(q,synchronous=false,restrict=true)

		ActionController::Base.logger.info "Query: aggregation starting #{Time.now}"

		map_s = q[:s]
		map_w = q[:w]
		map_n = q[:n]
		map_e = q[:e]

		# get parties
		if true && q[:partynames] && q[:partynames].length > 0
			ActionController::Base.logger.info "Query: Collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
			q[:parties] = self.twitter_get_parties(q[:partynames])
			ActionController::Base.logger.info "Query: Done collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
		end

		# get parties timelines
		if synchronous && q[:parties] && q[:parties].length > 0
			# self.twitter_get_timelines(q[:parties])
                        self.yql_twitter_get_timelines(q[:parties])
		end

		# get parties friends
		if !restrict && synchronous && q[:parties] && q[:parties].length > 0
			ActionController::Base.logger.info "Query: Collecting friends of parties now #{Time.now}"
			q[:friends] = self.twitter_get_friends(q[:parties]) 
			# q[:acquaintances] = self.twitter_get_friends(q[:friends])  # too expensive 
			ActionController::Base.logger.info "Query: Done collecting friends of parties now #{Time.now}"
		end

		# get parties friends timelines
		if !restrict && synchronous && q[:friends] && q[:friends].length > 0
			self.yql_twitter_get_timelines(q[:friends])
		end

		# get friends of friends timelines - very expensive so disabled
		if false && !restrict && synchronous && q[:acquaintances] && q[:acquaintances].length > 0
			self.yql_twitter_get_timelines(q[:acquaintances])
		end

		# do a brute force twitter search if no parties
		if synchronous && (!q[:partynames] || q[:partynames].length < 1) && q[:words] && q[:words].length > 0 
			ActionController::Base.logger.info "query: using a general search strategy looking for #{q[:words].join(' ')} near #{map_s} #{map_w} #{map_n} #{map_e}"
			self.twitter_search(q[:words],map_s,map_n,map_w,map_e) 
		end

		# for new people found during above searches - go ahead and collect their timelines and their friends - not done
		if false
		end

		ActionController::Base.logger.info "Query: aggregation of a set has finished updating external data sources at time #{Time.now}"

		return q
	end

	def self.aggregate_all
		# visit all queries
		# perform them
		# kill them after a week or so
	end

end

