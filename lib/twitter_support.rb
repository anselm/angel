
xxx

	##########################################################################################################
	# collect results from twitter search that might interest us; location,rad,topic.
	# geolocate posts here if they don't have any better details
        # TODO can we only get results newer than x (no)
	# TODO can we do without a specific term?
	# TODO slightly worried that a bad rad might be passed in
	##########################################################################################################

	def self.twitter_search(terms,lat,lon,rad)

		ActionController::Base.logger.info "Searching for #{terms.join(' ')} near #{lat} #{lon} #{rad}"

		if self.twitter_get_remaining_hits < 1
			# TODO what should we do?
			ActionController::Base.logger.debug("hit twitter rate limit")
			return [],[]
		end

		provenance = "twitter"

		posts = []
		parties = []
		blob = []
		if lat < 0 || lat > 0 || lon < 0 || lon > 0
			rad = "25mi"
			blob = Twitter::Search.new(terms.join(' ')).geocode(lat,lon,rad)  # TODO try conflating this verbosity
			ActionController::Base.logger.debug("twitter_search with #{terms} and lat lon #{lat} #{lon}")
		else
			blob = Twitter::Search.new(terms.join(' '))
			ActionController::Base.logger.debug("twitter_search with #{terms} without lat or lon")
		end

		if !blob 
			ActionController::Base.logger.debug("did not find any twitter search results?")
			return [],[]
		end

		blob.each do |twit|

			# build a model of the participants...
			party = self.save_party(
						:provenance => provenance,
						:uuid => twit.from_user_id,
						:title => twit.from_user,
						:location => twit["location"],
						:fallback_lat => lat,
						:fallback_lon => lon,
						:fallback_rad => rad
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)
			# and the posts
			post = self.save_post(party,
						:provenance => provenance,
						:uuid => twit.id,
						:title => twit.text,
						:location => twit["location"],
						:fallback_lat => lat,
						:fallback_lon => lon,
						:fallback_rad => rad,
						:begins => Time.parse(twit.created_at)
						)
			parties << party
			posts << post
		end
		return posts,parties
	end

	##########################################################################################################
	# collect messages from a single person more recent than last collection only - also add them to system
	# TODO switch to YQL
	##########################################################################################################

	def self.twitter_refresh_timeline(party)

		twitter = self.twitter_start

		if self.twitter_get_remaining_hits < 1
			# TODO what should we do?
			ActionController::Base.logger.debug("hit twitter rate limit")
			return []
		end

		provenance = "twitter"

		since_uuid = self.get_last_post(party,provenance)

		# other options: max_id, #page, #since
		results = []
		list = twitter.user_timeline(:user_id=>partyid,:count=>200,:since_id=>since_uuid) 
		list.each do |twit|
			ActionController::Base.logger.info "timeline - got a message #{twit.text}"
			results << self.save_post(party,
					:provenance => provenance,
					:uuid => twit.id,
					:title => twit.text,
					:location => twit.user.location,
					:begins => Time.parse(twit.created_at)
					)
		end
		return results
	end

	##########################################################################################################
	# collect direct messages to us
	# turn off because we don't need it yet
	# TODO - can we only get results newer than x
	##########################################################################################################

=begin
	def self.twitter_get_replies
		results = []
		twitter = self.twitter_start
		twitter.replies().each do |twit|
			# build a model of the participants...
			party = self.save_party(
						:provenance => "twitter",
						:uuid => twit.from_user_id,
						:title => twit.from_user,
						:location => twit["location"]
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)
			# and the posts
			results << self.save_post(party,
						:provenance => "twitter",
						:uuid => twit.id,
						:title => twit.text,
						:location => twit.user.location,
						:begins => Time.parse(twit.created_at)
						)
		end
		return results
	end
=end

	##########################################################################################################
	# twitter update a set of party profiles by tracing out friends given twitter ids
	# TODO switch to yql later?
	# use 'http://xangel.makerlab.org/yql/twitter.user.profile.xml' as party;
	# select * from party where id='anselm';
	##########################################################################################################

=begin
	def self.twitter_update_friends_of_set(partyids)
		twitter = self.twitter_start
		partyids.each { |partyid| self.twitter_update_friends_of_party(twitter,partyid) }
	end

	def self.twitter_update_friends_of_party(twitter,partyid)
		twitter.friends({:user_id=>partyid,:page=>0}).each do |v|
			party = self.save_party(
						:provenance => "twitter",
						:uuid => v.id,
						:title => v.screenname,
						:location => v["location"],
						:description => v.description,
						:begins => Time.parse(v.created_at)
						)
		end
	end
=end

	##########################################################################################################
	# twitter get an updated timeline using yql and in this case friendfeed
	# i decided this was a bad idea because what if person x is not on friendfeed? does this read through?
	# TODO FINISH
	# TODO we have to find a way to do this asynchronously or cap the returns
	# use 'http://xangel.makerlab.org/yql/twitter.user.timeline.xml' as ff;
	# select * from ff where id='anselm';
	##########################################################################################################

=begin
	def self.yql_twitter_update_timeline(partyname)
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://www.javarants.com/friendfeed/friendfeed.feeds.xml' as ff;"
		query = "select * from ff where nickname='#{partyname}' and service='twitter';"
		fragment = "#{schema}#{query}"
		url = "#{yql}#{url_escape(fragment)}" # is ignored why? ;&format=json"
		response = Hpricot.XML(open(url))
		response_name = response.innerHTML.strip
	end
=end

	##########################################################################################################
	# yql get the timelines of a pile of people - this is a crude way of seeing somebodys own view of reality
	# TODO could also maybe do searches and geographic bounds
	# use 'http://xangel.makerlab.org/yql/twitter.user.timeline.xml' as party;select * from party where id = 'anselm' and title like '%humanist%';
	# TODO use more recent than ( cannot do this )
	# TODO yahoo api rate limits
	##########################################################################################################

	def self.yql_twitter_get_timelines(parties)
		terms = parties.collect { |n| "id='#{n.title}'" }
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://xangel.makerlab.org/yql/twitter.user.timeline.xml' as party;"
		query = "select * from party where #{terms.join(' or ')}"
		fragment = "#{schema}#{query}"
		url = "#{yql}#{url_escape(fragment)};&format=json"
		ActionController::Base.logger.debug "YQL Using a schema #{schema}"
		ActionController::Base.logger.debug "YQL Query is #{url}"
		#response = Hpricot.XML(open(url))
		response = open(url).read
		blob = JSON.parse(response)

		count = blob["query"]["count"].to_i
		blob["query"]["results"]["entry"].each do |goop|
			#uuid = goop["id"]  # such as "tag:twitter.com,2007:http://twitter.com/anselm/statuses/2012363905"
			title = goop["title"]  # such as "anselm: blah blah blah "
			begins = goop["published"] # such as "2009-06-03T03:31:11+00:00"
			link = goop["link"][0]["href"]  # the link to the post

			# tearing apart the url seems a reasonably stable way to get at info that should have been sent by itself
			fragments = link.split("/")
			uuid = fragments[5]
			partyname = fragments[3]

			# also clean up this mess from "anselm: blah blah blah" to just "blah blah blah"
			title = title[(partyname.length+2)..-1]

			# clean up time
			begins = Time.parse(begins)

			# find the party from OUR list
			party = nil
			parties.each do |temp|
				if temp.title == partyname
					party = temp
					break
				end
			end
			if party == nil
				ActionController::Base.logger.debug "argh cannot find name #{partyname}"
				return
			end

			# save the post
			self.save_post(party,{
					:provenance => "twitter",
					:uuid => uuid,
					:title => title,
					:location => party.location,
					:begins => begins
					})

		end

	end


	###########################################################################################
	# respond
	###########################################################################################

=begin
	# Response handling is kept separate from consuming; they are asynchronous for stability and speed
	# TODO respond more intelligently
	# TODO bitmasks are borked
	def self.respond_all_this_is_currently_unused
		twitter = self.twitter_start
		results = []
		bitmask = 0
		Note.all(:statebits => bitmask).each do |note|
			party = Note.first(:id => note.owner_id)
			next if !party
			self.befriend(twitter,party)
			result = nil
			if note[:provenance] == "twitter"
				result = "!@#{party.title} thanks for the post"
				twitter.update(result)
				twitter.update("rt #{result}") if false
			end
			if result
				note.statebits = Note::STATEBITS_RESPONDED
				note.save!
				results << result
			else
				results << "failed to save note #{note.id}"
			end
		end
		return results
	end
=end

	###########################################################################################
	# reaper
	# TODO
	###########################################################################################

	def self.reaper()
	end

	###########################################################################################
	# merge dupes
	# this may be very important to helping score items
	# TODO write it
	###########################################################################################

	def self.merge_dupes
		# i think we could do this on the database itself...
		# for example if something is a reply then it is a kind of cluster
		# and if something is talking about the same url then it is a kind of cluster
		# and if it has the same words then its the same topic too...
		# - i could totally delete the dupe
		# - ...
	end


	###########################################################################################
	# metadata extraction
	###########################################################################################

	# pull out useful metadata
	def self.metadata_all
	end

	###########################################################################################
	# scoring - both objective and subjective
	###########################################################################################

	def self.score
		#
		# if we can do scoring in the sql query then do that... otherwise...
		#
		# for each post
		#
		#	score = 0 to 1 based on newness ranging over say a month
		#	score = 0 to 1 based on graph distance
		#	score = 0 to 1 based on geographic distance
		#	score = 0 to 1 based on who is bookmarking this thing; its velocity?
		#
		#	TODO fold duplicates and increase their score...
	end 

	# score friends
	def self.score_friends
	end

	# score posts
	def self.score_posts
	end

	# score everything
	def self.score_all
	end

	###########################################################################################
	# perform a query that may cause traffic to twitter and the like
	# TODO pagination
	###########################################################################################

	def self.query(phrase)

		# for debugging lets flush everything - makes solr go crazy - have to delete solr index
		# Note.delete_all
		# Relation.delete_all

		ActionController::Base.logger.info "Query: beginning at time #{Time.now}"

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

		# TODO not certain if this sometimes helps with filtering
		# Note.rebuild_solr_index

		# go ask solr
		results = []
                search = []
		search << q[:words].join(" ") if q[:words].length > 0
		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			# TODO at some point we should use the range that the user indicates
			range = 1
			search << "lat:[#{lat-range} TO #{lat+range}]"
			search << "lon:[#{lon-range-range} TO #{lon+range+range}]"
		end
		search_phrase = search.join(" AND ")
		ActionController::Base.logger.info "Query: solr now looking for: #{search_phrase}"
		total_hits = 0
		if search.length
			results = Note.find_by_solr(search_phrase,
										:offset => 0,
										:limit => 50
										#:order => "id desc",
										#:operator => "and"
										)
			total_hits = 0
			total_hits = results.total_hits if results
			results = results.docs if results
			results = [] if !results
		end
		q[:search_phrase] = search_phrase 
		q[:results] = results
		q[:total_hits] = total_hits

# TODO if there were no people passed... should we do some kind of injection of people in the area?

		# debug show results
		ActionController::Base.logger.info "Query: results " if results.length > 0
		results.each do |r|
			ActionController::Base.logger.info "Got #{r.uuid} #{r.title}"
		end

		return q

	end

end


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
