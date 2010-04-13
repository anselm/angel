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

		map_s = q[:s]
		map_w = q[:w]
		map_n = q[:n]
		map_e = q[:e]

		# Get parties by name immediately
		# Since these calls may be batched later it is best to treat them as a batch request
		# There is no freshness checking here - the caller should check for freshness themselves
		# TODO Getting a party timeline ( below ) also effectively updates a party profile so it is not needed here.

		if true && q[:partynames] && q[:partynames].length > 0
			ActionController::Base.logger.info "Query: Collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
			q[:parties] = self.twitter_get_parties(q[:partynames])
			ActionController::Base.logger.info "Query: Done collecting explicitly stated parties now #{q[:partynames]} #{Time.now}"
		elsif q[:parties] && q[:parties].length > 0
			ActionController::Base.logger.info "Query: Collecting explicitly stated parties now #{q[:parties]} #{Time.now}"
			self.twitter_update_parties(q[:parties])
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
		# Since these calls may be batched later it is best to treat them as a batch request
		# TODO if this accepts parties by name? then the above would not be needed at all - could verify this.
		#

		if q[:parties] && q[:parties].length > 0
			# self.yql_twitter_get_timelines(q[:parties])  # TODO improve GEO support here
			self.twitter_get_profiles_and_timelines(q[:parties])
		end

		# get parties friends
		# It is the callers responsibility to make sure these are in need of updating

		if synchronous && q[:parties] && q[:parties].length > 0
			ActionController::Base.logger.info "Query: Collecting friends of parties now #{Time.now}"
			q[:friends] = self.twitter_get_friends_ids(q[:parties])
			# q[:friends] = self.twitter_get_friends(q[:parties]) # doesn't get enough friends
			# q[:acquaintances] = self.twitter_get_friends(q[:friends])  # too expensive 
			ActionController::Base.logger.info "Query: Done collecting friends of parties now #{Time.now}"
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
			ActionController::Base.logger.info "query: using a general search strategy looking for #{q[:words].join(' ')} near #{map_s} #{map_w} #{map_n} #{map_e}"
			self.twitter_search(q[:words],map_s,map_n,map_w,map_e) 
		end

		# for new people found during above searches - go ahead and collect their timelines and their friends - not done
		if false
		end

		ActionController::Base.logger.info "Query: aggregation of a set has finished updating external data sources at time #{Time.now}"

		return q
	end

	#
	# Aggregate a handful more people ( the core aggregation algorithms request groups at a time so this is best )
	# Call this from a cron or long lived thread
	#
	def self.aggregate

		# we're only interested in updating things that are older than an hour (for now)
		old = 1.hours.ago

		# select all persons and pick the ten least updated

		ActionController::Base.logger.info "************* AGGREGATION: STARTING AT TIME #{Time.now} ************************* "

		# select a handful of non-updated persons 
		score = 1
		parties = Note.find(:all,:conditions => [ "kind = ? AND score <= ? AND updated_at < ?", Note::KIND_USER, score, old ],
							:order => "updated_at ASC",
							:limit => 10,
							:offset => 0
							)
		# debugging
		parties.each do | party |
			ActionController::Base.logger.info "AGGREGATION: updating #{party.title} #{party.id} due to age #{party.updated_at}"
		end

		# get their profile AND timelines
		self.twitter_get_profiles_and_timelines(parties,0)

		# fetch their friends
		self.twitter_get_friends_ids(parties,1)

		# update these only
		self.aggregate_memoize({ :parties => parties } ,true)

		ActionController::Base.logger.info "************ AGGREGATION: DONE AT TIME #{Time.now} ***************************** "

	end

end

