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

require 'lib/aggregator/twitter_base.rb'
require 'lib/aggregator/twitter_reap.rb'

class TwitterSupport

	#
	# Aggregate content from twitter via YQL if content is old. Synchronous mode will do more work ( thus take more time )
	#

	def self.aggregate_memoize(q,synchronous=false)

		ActionController::Base.logger.info "Query: aggregation starting #{Time.now}"

		# Get explicitly named parties in full right now
		# Since these calls may be batched later it is best to pass bundles to them now
		# There is no freshness checking here - the caller should check for freshness themselves
		# TODO Getting a party timeline ( below ) also effectively updates a party profile so it is not needed here?

		if true && q[:partynames] && q[:partynames].length > 0
			begin
				ActionController::Base.logger.info "Query: Collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
				q[:parties] = self.twitter_update_parties_by_name_or_uuid(q[:partynames])
			rescue Exception => e
				ActionController::Base.logger.info "Query: Exception 1 raised! #{e.class} #{e} #{Time.now}"
				return
			end
			ActionController::Base.logger.info "Query: Done collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
		elsif q[:parties] && q[:parties].length > 0
			ActionController::Base.logger.info "Query: Collecting explicitly stated parties now #{q[:parties]} #{Time.now}"
			begin
				self.twitter_update_parties(q[:parties])
			rescue Exception => e
				ActionController::Base.logger.info "Query: Exception 2 raised! #{e.class} #{e} #{Time.now}"
				return
			end
			ActionController::Base.logger.info "Query: Done collecting explicitly stated parties #{Time.now}"
		end

		#
		# for all explicitly marked parties promote them to be 'watched' so that successive aggregator iterations will fetch them
		#
		if q[:parties]
			q[:parties].each do |party|
				ActionController::Base.logger.info "Query: promoting user #{party.title} to be watched more at #{Time.now}"
				party.update_attributes(:score => 0)
			end
		end

		#
		# Get parties timelines immediately
		# This is different from the above because we are capturing their full history - but it is not critical
		# TODO we could get parties by name and then remove the above
		#

		if q[:parties] && q[:parties].length > 0
			# self.yql_twitter_get_timelines(q[:parties])  # TODO improve GEO support here
			begin
				self.twitter_get_profiles_and_timelines(q[:parties])
			rescue Exception => e
				ActionController::Base.logger.info "Query: Exception 3 raised! #{e.class} #{e} #{Time.now}"
				return
			end
		end

		# get parties friends
		# It is the callers responsibility to make sure these are in need of updating

		if synchronous && q[:parties] && q[:parties].length > 0
			begin
				ActionController::Base.logger.info "Query: Collecting friends of parties now #{Time.now}"
				q[:friends] = self.twitter_get_friends_most_recent_activity(q[:parties],1)
				# q[:friends] = self.twitter_get_friends_ids(q[:parties],1)
				# q[:acquaintances] = self.twitter_get_friends_most_recent_activity(q[:friends],2)
				ActionController::Base.logger.info "Query: Done collecting friends of parties now #{Time.now}"
			rescue Exception => e
				ActionController::Base.logger.info "Query: Exception 4 raised! #{e.class} #{e} #{Time.now}"
				return
			end
		end

		# get parties friends timelines - no real reason to do this since aggregation will catch it on successive pass
		#if !restrict && synchronous && q[:friends] && q[:friends].length > 0
		#	self.yql_twitter_get_timelines(q[:friends])
		#end

		# get friends of friends timelines - very expensive so disabled
		#if false && !restrict && synchronous && q[:acquaintances] && q[:acquaintances].length > 0
		#	self.yql_twitter_get_timelines(q[:acquaintances])
		#end

		# do a brute force twitter search if no parties
		if synchronous && (!q[:partynames] || q[:partynames].length < 1) && q[:words] && q[:words].length > 0 
			map_s = q[:s]
			map_w = q[:w]
			map_n = q[:n]
			map_e = q[:e]
			ActionController::Base.logger.info "query: using a general search strategy looking for #{q[:words].join(' ')} near #{map_s} #{map_w} #{map_n} #{map_e}"
			self.twitter_search(q[:words],map_s,map_n,map_w,map_e) 
		end

		# mark any new persons that we found - we're interested in tracing out their social graph too
		#if false
		#end

		ActionController::Base.logger.info "Query: aggregation of a set has finished updating external data sources at time #{Time.now}"

		return q
	end

	#
	# Background Aggregation Strategy May 10 2010
	#
	# The current aggregation strategy is to
	#	1) Aggregate persons with low scores
	#	2) Aggregate persons with low scores if they are old
	#	3) Aggregate persons with low scores if they are old and from oldest to youngest - guaranteeing a round robin of all
	#
	# Aggregation means
	#	1) Collect their timeline
	#	2) Collect their friends
	#	2) Collect their friends by collecting their friends with their friends most recent tweet and location
	#
	# In the future we could
	#	1) Weigh the social graph outwards from the anchors
	#	2) Provide subjective weighting of the social graph depending on who you asked for as a root
	#	3) Do these kinds of weighting operations as background tasks
	#	4) Do location lookups as background tasks
	#	5) Parallelize queries in general - I think the background aggregation would be faster if parallelized
	#	6) Further work to block interactive queries out to twitter if we know that our local content is fairly recent
	#	7) Should weight people by the number of anchors they are connected to!


	# Aggregate a handful more people ( the core aggregation algorithms request groups at a time so this is best )
	# Call this from a cron or long lived thread
	#
	def self.aggregate


		ActionController::Base.logger.info "************* AGGREGATION: STARTING AT TIME #{Time.now} ************************* "

		score = 1
		old = 1.minutes.ago
		parties = Note.find(:all,:conditions => [ "kind = ? AND score <= ? AND updated_at < ?", Note::KIND_USER, score, old ],
							:order => "updated_at ASC",
							:limit => 100,
							:offset => 0
							)
		self.aggregate_memoize({ :parties => parties } ,true)

		ActionController::Base.logger.info "************ AGGREGATION: DONE AT TIME #{Time.now} ***************************** "

	end

end

