require 'net/http'
require 'uri'
require 'open-uri'
require 'hpricot'
require 'json'
require 'lib/geolocate.rb'
require 'twitter'

#
# A utility class that is actually tightly coupled to the specific datamodel used here
# Didn't want to burden model with this because I want to abstract and reuse it somehow
#
class TwitterSupport

	###########################################################################################
	# encode url
	###########################################################################################

	def self.url_escape(string)
		string.gsub(/([^ a-zA-Z0-9_-]+)/n) do
			'%' + $1.unpack('H2' * $1.size).join('%').upcase
		end.tr(' ', '%20')
	end

	###########################################################################################
	# geolocate
	###########################################################################################

	def self.geolocate(text)
		name = SETTINGS[:site_metacarta_userid]
		password = SETTINGS[:site_metacarta_pass]
		key = SETTINGS[:site_metacarta_key]
		lat,lon,rad = Geolocate.geolocate_via_metacarta(text,name,password,key)
		return lat,lon,rad
	end

	def self.geolocate_all
		all = Note.find_by_sql("select * from notes where !(statebits & #{Note::STATEBITS_GEOLOCATED)}")
		all.each do |note|
			lat,lon,rad = self.geolocate(note.location)
			if lat < 0 || lat > 0 || lon < 0 || lon > 0
				statebits = note.statebits | Note::STATEBITS_GEOLOCATED
				note.update_attributes(:lat => lat, :lon => lon, statebits => statebits )
			end
		end
	end

	###########################################################################################
	# clean up text
	###########################################################################################

	def self.sanitize(text)
		# TODO other sanitization as well
		# The preference here is to sanitize on input - rather than on output
		# remove the target party (ourselves) at the very least if present
		ourname = SETTINGS[:site_twitter_username]
		length = username.length
		text = text[(length+2)..-1] if text[0..10] == "@#{ourname}" 
		text = text[(length+3)..-1] if text[0..11] == "d #{ourname}"
		return text
	end

	###########################################################################################
	# twitter handle
	###########################################################################################

	def self.twitter_start()
		ourname = SETTINGS[:site_twitter_username]
		password = SETTINGS[:site_twitter_password]
		httpauth = Twitter::HTTPAuth.new(ourname,password)
		@@twitter_handle = Twitter::Base.new(httpauth)
		return @@twitter_handle
	end

	##########################################################################################################
	# twitter get at the rate limiter
	# TODO cache
	##########################################################################################################

	def self.twitter_get_remaining_hits
		begin
			response = open("http://twitter.com/account/rate_limit_status.json"
				#, :http_basic_authentication => [Config[:username], Config[:password]]).read
				)
			blob = JSON.parse(response.read)
			hits = blob['remaining_hits']
			return hits.to_i
		rescue
		end
		return 0
	end

	##########################################################################################################
	# twitter get a set of people objects from their names
	##########################################################################################################

=begin
	# get parties via yql - the idea is it would scale more
	# TODO this is unfinished - it relies on YQL and I need bake up a better open table schema 
	def self.unused_twitter_get_parties(names)
		terms = names.collect { |n| "id='#{n}'" }
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://angel.makerlab.org/yql/twitter.user.profile.xml' as party;"
		query = "select * from party where id = \"#{terms.join(' or ')}\""
		fragment = "#{schema};#{query}"
		url = "#{yql}#{url_escape(fragment)};&format=json"
		#response = Hpricot.XML(open(url))
		#response_name = response.innerHTML.strip
		response = open(url).read
	end
=end

	# get parties directly from twitter - later will switch to yql but this is good enough
	def self.twitter_get_parties(names_or_ids)
		results = []
		twitter = twitter_start
		limit = self.twitter_get_remaining_hits
		names_or_ids.each do |name_or_id|
			limit -= 1
			puts "rate limit is at #{limit}"
			puts "oh oh rate limit exceeded" if limit < 1
			break if limit < 1
			blob = twitter.user(name_or_id)
			next if !blob
			party = self.save_party(
					:provenance => "twitter",
					:uuid => blob.id,
					:title => blob.screen_name,
					:location => blob["location"],
					:description => blob.description,
					:begins => Time.parse(blob.created_at)
					)
			results << party if party
		end
		return results
	end

	##########################################################################################################
	# twitter get friends of a set of party objects
	# TODO there are serious concerns here about the load of re-querying friend lists over and over.
	# TODO i could just get all friend via yql more efficiently in a more scalable way...
	#    SELECT * FROM social.profile WHERE guid IN (SELECT guid FROM social.connections WHERE owner_guid=me)
	# TODO should i return something nice to the caller if we fail due to rate limits or the like?
	##########################################################################################################

	def self.twitter_get_friends(parties)
		old = 24.hours.ago
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		parties.each do |party|
			next if party.updated_at > old
			puts "rate limit is at #{limit}"
			puts "decided to update this user because #{party.updated_at}"
			limit -= 1
			puts "oh oh rate limit exceeded" if limit < 1
			break if limit < 1
			twitter.friends({:user_id => party.uuid, :page=>1}).each do |blob|
				party2 = self.save_party(
						:provenance => "twitter",
						:uuid => blob.id,
						:title => blob.screen_name,
						:location => blob["location"],
						:description => blob.description,
						:begins => Time.parse(blob.created_at)
						)
				results << party2 if party2
				puts "saved a friend of #{party.title} named #{party2.title}"
			end
		end
		return results
	end

	##########################################################################################################
	# twitter update a set of party profiles by tracing out friends given twitter ids
	# TODO switch to yql later?
	# use 'http://angel.makerlab.org/yql/twitter.user.profile.xml' as party;
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
	# befriend a party on twitter - supply an object
	# it's possible we can get out of sync so best to try refriend periodically
	# note that the handler throws an error so we have to test first
	# TODO this may need a transaction block due to statebits
	##########################################################################################################

=begin
	def self.twitter_befriend(twitter,party)
		ourname = SETTINGS[:site_twitter_username]
		if( !(party.statebits & Note::STATEBITS_FRIENDED) ) 
			begin
				twitter.create_friendship(party.title) if !twitter.friendship_exists?(ourname,party.title)
				party.statebits = Note::STATEBITS_FRIENDED | party.statebits
				party.save
			rescue
			end
		else
		end
	end
=end

	##########################################################################################################
	# collect results from twitter search that might interest us; location,radius,topic.
	# TODO can we only get results newer than x
	# TODO can we do without a specific term?
	# TODO rate limit
	##########################################################################################################

	def self.twitter_search(terms,lat,lon,rad)
		results = []
		Twitter::Search.new(terms.join(' ')).geocode(lat,lon,rad).each do |twit|
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
						:location => twit["location"],
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
	# collect messages from a single person more recent than last collection only - also add them to system
	# TODO switch to YQL
	##########################################################################################################

	def self.twitter_refresh_timeline(party)

		twitter = self.twitter_start
		limit = self.twitter_get_remaining_hits
		return [] if limit < 2

		provenance = "twitter"
		kind = Note::KIND_USER
		uuid = partyid
		since_id = 0

		# only fetch since last time
		last = Note.find(:last, :order => 'created_at',
								:conditions => {	:kind => Note::KIND_POST,
													:owner_id => party.id,
													:provenance => "twitter"
												}
							)
		puts "the last id of this party #{party.title} is #{last.id}" if last
		since_id = last.id if last

		results = []
		list = twitter.user_timeline(:user_id=>partyid,:count=>200,:since_id=>since_id)

		Options: since_id, max_id, count, page, since 
		list.each do |twit|
			puts "timeline - got a message #{twit.text}"
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

	##########################################################################################################
	# twitter get an updated timeline using yql and in this case friendfeed
	# i decided this was a bad idea because what if person x is not on friendfeed? does this read through?
	# TODO FINISH
	# TODO we have to find a way to do this asynchronously or cap the returns
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as ff;
	# select * from ff where id='anselm';
	##########################################################################################################

=begin
	def self.yql_twitter_update_timeline(partyname)
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://www.javarants.com/friendfeed/friendfeed.feeds.xml' as ff;"
		query = "select * from ff where nickname='#{partyname}' and service='twitter';"
		fragment = "#{schema};#{query}"
		url = "#{yql}#{url_escape(fragment)}" # is ignored why? ;&format=json"
		response = Hpricot.XML(open(url))
		response_name = response.innerHTML.strip
	end
=end

	##########################################################################################################
	# yql get the timelines of a pile of people - this is a crude way of seeing somebodys own view of reality
	# could also do other stuff too like
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as party;select * from party where id = 'anselm' and title like '%humanist%';
	##########################################################################################################

	def self.yql_twitter_get_timelines(parties)
		terms = parties.collect { |n| "id='#{n.title}'" }
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as party;"
		query = "select * from party where \"#{terms.join(' or ')}\""
		fragment = "#{schema};#{query}"
		url = "#{yql}#{url_escape(fragment)};&format=json"
		#response = Hpricot.XML(open(url))
		#response_name = response.innerHTML.strip
		response = open(url).read
	end

	##########################################################################################################
	# save a party
	# TODO track contrails
	##########################################################################################################

	def self.save_party(args)

		kind = Note::KIND_USER
		provenance = args[:provenance]
		uuid = args[:uuid]
		title = args[:title]
		location = args[:location]
		description = args[:description]
		last_login_at = args[:begins]
		begins = args[:begins]

		party = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		# set this later
		lat,lon,rad = 0,0,0

		if !party
			party = Note.new(
				:kind => kind,
				:uuid => uuid,
				:provenance => provenance,
				:title => title,
				:description => description,
				:location => location,
				:begins => begins,
				:lat => lat,
				:lon => lon,
				:begins => begins,
				:statebits => Note::STATEBITS_DIRTY
				)
			party.save
		else
			party.update_attributes(:title => title, :description => description );
			if lat < 0 || lat > 0 || lon < 0 || lon > 0
				party.update_attributes(:lat => lat, :lon => lon )
			end
		end

		return party

	end

	##########################################################################################################
	# save a post
	##########################################################################################################

	def self.save_post(party,args = {})

		kind = Note::KIND_POST
		provenance = args[:provenance]	
		uuid = args[:uuid]
		title = args[:title]
		location = args[:location]
		description = args[:description]
		last_login_at = args[:begins]
		begins = args[:begins]

		# We build a model of accumulated posts but don't store posts twice
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		return "Note already found #{args[:id]} #{args[:text]}" if note

		# set this later
		lat,lon,rad = 0,0,0

		# Save the note, tags, and relationships between everything
		begin
		  Note.transaction do
puts "post saving #{text}"
			note = Note.new(
				:kind => kind,
				:uuid => uuid,
				:provenance => provenance,
				:title => title,
				:description => description,
				:location => location,
				:lat => lat,
				:lon => lon,
				:owner_id => party.id,
				:created_at => DateTime::now,
				:updated_at => DateTime::now,
				:begins => begins,
				:statebits => Note::STATEBITS_DIRTY
				)
			note.save

			# build a relationship to the owner - not really needed except for CNG traversals
			note.relation_add(Relation::RELATION_OWNER,party.id)

			# build a relationship to hash tags
			args[:text].scan(/#[a-zA-Z]+/).each do |tag|
				note.relation_add(Relation::RELATION_TAG,tag[1..-1])
			end

		  end
                rescue
                  puts "badness"
                end
		return "note added #{noteid} #{text}"

	end

	###########################################################################################
	# respond
	###########################################################################################

=begin
	# Response handling is kept separate from consuming inputs; they are asynchronous for stability and speed
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
	# query construction
	# TODO deal with time
	# TODO radius support
	# TODO longitudinal and latitudinal wraparound
	###########################################################################################

	# pull out persons, search terms and tags, location such as "@anselm pizza near portland oregon"
	def self.query_parse(phrase)
		words = []
		partynames = []
		placenames = []
		terms = phrase.to_s.split.collect { |w| Sanitize.clean(w.downcase) }
		near = false
		terms.each do |w|
			if w[0..0] == "@"
				partynames << w[1..-1]
				next
			end
			if w == "near"
				near = true
				next
			end
			if near
				placenames << w
				next
			end
			words << w
		end
		return { :words => words, :partynames => partynames, :placenames => placenames }
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
		# tear apart query
		q = self.query_parse(phrase)

		# get time TODO implement
		begins = nil
		ends = nil

		# get bounds if any
		lat,lon,rad = Geolocate.geolocate_via_metacarta(q[:places].join(' ')) if q[:places].length

		# did the user supply some people as the anchor of a search? refresh them if so ( this is not costly )
		q[:parties] = self.twitter_get_parties(q[:partynames])
		q[:friends] = self.twitter_get_friends(q[:parties])
		#q[:aquaintances] = ...

		# reap old data
		self.reaper

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
				self.yql_twitter_get_timelines(parties)
			when "recent"
				# in this strategy we look at the core members only and get their friends recent timelines.
			end
		else
			# if there are no people to anchor the search then just let twitter do the search
			self.twitter_search(q[:words],lat,lon,rad)
		end

# todo
#   test bitmasks
#   finish yql query
#		should we just query by terms and geography ALSO?
#   remember relationships between people
#   see if i can find things i search for
#   let users upscore things by bookmarking them
#   try to emphasize scored things
#   is there any point to using acts as solr at this point?
#

		# update geolocation of entries
		self.geolocate_all

		# tear apart sentences and pluck out urls and hashtags and the like
		# right now we already track most of this except urls
		# self.metadata_all

		# rescore entries - also considering what members have consciously scored up
		# we won't need to score until we get bigger
		# self.score_all

		# build a solr query with terms, location, score, filtered by friends, ordered by time
		if terms.length
			str = terms.join(" ")
		else
			str = "[ * ] "
		end

		#if lon && lat
		#	str = "lon:[0 TO 4] AND lat:[0 TO 4]"
		#end

		results = Note.find_by_solr(str,{
					:offset => 0,
					:limit => 50,
					#:scores => true,
					:order => "id desc",
					:operator => "and"
					}
					)
		products = results.docs
		total_hits = results.total_hits

		return products

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
