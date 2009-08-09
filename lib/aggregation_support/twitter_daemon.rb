#
# Background aggregation strategy
# Aug 5 2009
#
# The database has a user indicated understanding of parties that it should be watching
#
#
#

# june 1 2009
# how search works
#
# there are two kinds of searches that are conflated here
#	i want to show sentiment and issues in an area, with velocity, filtered by people.
#	ed wants to show popular urls and he wants to find related people to a person he searches for
#
# corpus = []
#
# 1) anchors
#
# use named persons as anchors
# or use good persons in that geography as anchors where good is a function of distance from me or other golden members
#
# 2) raw data
#
# if we have people as anchors - try one of these strategies to get their activity:
#   2a) find their friends. pick some of their friends by magic. collect all this traffic
#   2b) can i just do a search on traffic from these people and their friends and possibly the search phrase and location?
#   2c) get core peoples timelines and use timeline to indicate friends, adding their friends and their posts
#			unclear if this will reveal clusters by the way.... but it might.
#
# if we do not have people as anchors
#   2d) just do a search (in that area) (including a search term if any)
#
# 3) mark each new entry
#		break sentences apart and geolocate
#		break out hash tags
#		break out urls ( as tags ) [ this is for ed because he really wants to find popular urls ]
#		geolocate
#		find dupes? [ this is also for ed because it may impact scoring... um maybe... ]
#
# 4) update score of all posts in the database
#		objective people score is a function of distance from golden members
#		objective post score is a function of distance from golden members
#		objective post score is increased if replied to
#		objective post score is increased if new
#		objective post score is increased for magic keywords
#       subjective post score is a sum of distances from anchors
#
# 5) pick data
#		select by anchors and friends
#		select by term
#		select by geography
#       select by popularity?
#		we may use solr for this
#		order by time
#		truncate at some cap
#		can yql do this? can solr do this?
#


class poo

	def self.query(phrase)

		# for debugging lets flush everything - makes solr go crazy - have to delete solr index
		# Note.delete_all
		# Relation.delete_all


xxx

		# reap old data
		self.reaper

		ActionController::Base.logger.info "Query: has now collected people and friends to anchor search at time #{Time.now}"

		# this query itself should be saved and published to everybody TODO

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
				# self.yql_twitter_get_timelines(q[:friends])
				# self.yql_twitter_get_timelines(q[:acquiantances])
			when "recent"
				# in this strategy we look at the core members only and get their friends recent timelines.
			end
		else
			# if there are no people to anchor the search then just let twitter do the search
			ActionController::Base.logger.info "query: using a general search strategy looking for #{q[:words].join(' ')} near #{lat} #{lon} #{rad}"
			self.twitter_search(q[:words],lat,lon,rad)

# after an ordinary twitter search i would like to take the persons that were related to these posts and get them in more detail
# something like this:
# and get their friends too...
# this would help anchor a search quite a bit showing more context
# later i could even ask yql for those timelines in turn...
#		q[:parties] = self.twitter_get_parties(q[:partynames])
#		q[:friends] = self.twitter_get_friends(q[:parties])

		end

		ActionController::Base.logger.info "Query: has finished updating external data sources at time #{Time.now}"

	end

end

