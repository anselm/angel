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
		string.gsub(/([^a-zA-Z0-9_-]+)/n) do
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
		ActionController::Base.logger.info "geolocator at work: #{text} set to #{lat} #{lon} #{rad}"
		return lat,lon,rad
	end

	def self.geolocate_all
		all = Note.find_by_sql("select * from notes where !(statebits & #{Note::STATEBITS_GEOLOCATED})")
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
			ActionController::Base.logger.info "rate limit is at #{hits}"
			return hits.to_i
		rescue
		end
		return 0
	end

	##########################################################################################################
	# get the most recent post uuid identifier so that we only fetch newer posts (for a given provenance)
	##########################################################################################################

	def self.get_last_post(party,provenance)
		last = Note.find(:last, :order => 'created_at',
								:conditions => {	:kind => Note::KIND_POST,
													:owner_id => party.id,
													:provenance => provenance
												}
							)
		ActionController::Base.logger.info "the last posted post of this party #{party.title} is #{last.uuid}" if last
		return last.uuid if last
		return 0
	end

	##########################################################################################################
	# befriend a party on twitter - supply an object
	# it's possible we can get out of sync so best to try refriend periodically
	# note that the handler throws an error so we have to test first
	# TODO this may need a transaction block due to statebits
	# TODO also test bits
	##########################################################################################################

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
		query = "select * from party where id = #{terms.join(' or ')}"
		fragment = "#{schema}#{query}"
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
		ActionController::Base.logger.info "Collecting fresh state of a party #{names_or_ids}"
		names_or_ids.each do |name_or_id|
			limit -= 1
			ActionController::Base.logger.info "rate limit is at #{limit}"
			ActionController::Base.logger.debug "oh oh rate limit exceeded" if limit < 1
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
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		old = 4.hours.ago
		parties.each do |party|
			if party.updated_at > old  # if updated at time is bigger(newer) than 4 hours agos bigness then skip
				ActionController::Base.logger.info "Skip getting friends of #{party.title} - updated recently #{party.updated_at}"
				next
			end
			ActionController::Base.logger.info "decided to update this user because #{party.updated_at} is not > #{old}"
			limit -= 1
			ActionController::Base.logger.debug "oh oh rate limit exceeded" if limit < 1
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
				ActionController::Base.logger.info "saved a friend of #{party.title} named #{party2.title}"
			end
			# TODO for some reason this has to be done explicity - note that we rely on this behavior - and it is implicit
			party.update_attributes(:updated_at => Time.now );
		end
		return results
	end

	##########################################################################################################
	# collect results from twitter search that might interest us; location,rad,topic.
	# TODO can we only get results newer than x (no)
	# TODO can we do without a specific term?
	# TODO slightly worried that a bad rad might be passed in
	##########################################################################################################

	def self.twitter_search(terms,lat,lon,rad)

		ActionController::Base.logger.info "Searching for #{terms.join(' ')} near #{lat} #{lon} #{rad}"

		if self.twitter_get_remaining_hits < 1
			# TODO what should we do?
			ActionController::Base.logger.debug("hit twitter rate limit")
			return []
		end

		provenance = "twitter"

		results = []
		if lat || lon
			blob = Twitter::Search.new(terms.join(' '))
		else
			blob = Twitter::Search.new(terms.join(' ')).geocode(lat,lon,rad)  # TODO try conflating this verbosity
		end
		blob.each do |twit|
			# build a model of the participants...
			party = self.save_party(
						:provenance => twitter,
						:uuid => twit.from_user_id,
						:title => twit.from_user,
						:location => twit["location"]
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)
			# and the posts
			results << self.save_post(party,
						:provenance => twitter,
						:uuid => twit.id,
						:title => twit.text,
						:location => twit["location"],
						:begins => Time.parse(twit.created_at)
						)
		end
		return results
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

		results = []
		list = twitter.user_timeline(:user_id=>partyid,:count=>200,:since_id=>since_uuid)  # other options: max_id, #page, #since
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
		fragment = "#{schema}#{query}"
		url = "#{yql}#{url_escape(fragment)}" # is ignored why? ;&format=json"
		response = Hpricot.XML(open(url))
		response_name = response.innerHTML.strip
	end
=end

	##########################################################################################################
	# yql get the timelines of a pile of people - this is a crude way of seeing somebodys own view of reality
	# TODO could also maybe do searches and geographic bounds
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as party;select * from party where id = 'anselm' and title like '%humanist%';
	# TODO use more recent than ( cannot do this )
	# TODO yahoo api rate limits
	##########################################################################################################

	def self.yql_twitter_get_timelines(parties)
		terms = parties.collect { |n| "id='#{n.title}'" }
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as party;"
		query = "select * from party where #{terms.join(' or ')}"
		fragment = "#{schema}#{query}"
		url = "#{yql}#{url_escape(fragment)};&format=json"
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

		lat,lon,rad = self.geolocate(location)
		ActionController::Base.logger.info "Geolocated a party #{title} to #{lat},#{lon},#{rad} ... #{location}"

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
				:rad => rad,
				:begins => begins,
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED )
				)
			party.save
			ActionController::Base.logger.info "Saved a new party with title #{title}"
		else
			# TODO note that for some reason :updated_at is not set here - and we rely on this behavior but it is implicit.
			party.update_attributes(:title => title, :description => description );
			if lat < 0 || lat > 0 || lon < 0 || lon > 0
				party.update_attributes(:lat => lat, :lon => lon )
			end
			ActionController::Base.logger.info "Updated a party with title #{title}"
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
		#last_login_at = args[:begins]
		begins = args[:begins]

		# We build a model of accumulated posts but don't store posts twice
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		if note
			ActionController::Base.logger.info "Note already found #{uuid} #{title}"
			return "Note already found #{uuid} #{title}"
		end

		# try geolocate on content or party - TODO the post itself also includes party information for that moment in time - try?
		lat,lon,rad = self.geolocate(title)
		# WHY? TODO
		if lat > -1 && lat < 1 && lon > -1 && lon < 1
			lat = party.lat
			lon = party.lon
			rad = party.rad
			ActionController::Base.logger.info "Geolocated a post using user data ***********"
		end
		ActionController::Base.logger.info "Geolocated a post #{uuid} to #{lat},#{lon},#{rad} ... #{title}"

		# turn of assertion catching because there's no point to silently failing ( but leave the transaction block on )
		#begin
		  Note.transaction do
			note = Note.new(
				:kind => kind,
				:uuid => uuid,
				:provenance => provenance,
				:title => title,
				:description => description,
				:location => location,
				:lat => lat,
				:lon => lon,
				:rad => rad,
				:owner_id => party.id,
				:created_at => DateTime::now,
				:updated_at => DateTime::now,
				:begins => begins,
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED )
				)
			note.save

			# build a relationship to the owner - not really needed except for CNG traversals
			note.relation_add(Relation::RELATION_OWNER,party.id)

			# build a relationship to hash tags
			args[:title].scan(/#[a-zA-Z]+/).each do |tag|
				note.relation_add(Relation::RELATION_TAG,tag[1..-1])
			end

			ActionController::Base.logger.info "Saved a new post from #{party.title} ... #{title}"

		  end
		#rescue
		#	ActionController::Base.logger.debug "badness - failed to save the post"
		#end
		return note
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
	# query construction
	# TODO deal with time
	# TODO rad support
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

		# for debugging lets flush everything - makes solr go crazy - have to delete solr index
		# Note.delete_all
		# Relation.delete_all

		ActionController::Base.logger.info "Query: beginning at time #{Time.now}"

		# tear apart query
		q = self.query_parse(phrase)

		# get time
		# TODO implement
		begins = nil
		ends = nil

		# get bounds if any
		lat,lon,rad = 0,0,0
		lat,lon,rad = self.geolocate(q[:placenames].join(' ')) if q[:placenames].length
		ActionController::Base.logger.info "query: geolocated the query #{q[:placenames].join(' ')} to #{lat} #{lon} #{rad}"

		# did the user supply some people as the anchor of a search? refresh them and get their friends ( this is cheap )
		q[:parties] = self.twitter_get_parties(q[:partynames])
		q[:friends] = self.twitter_get_friends(q[:parties])

		# get the extended first level network of aquaintances ... this is expensive
		# q[:acquaintances] = self.twitter_get_friends(q[:friends])

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
		end

		ActionController::Base.logger.info "Query: has finished updating external data sources at time #{Time.now}"

		# uh weird.
		Note.rebuild_solr_index

		# ask solr
		phrase = q[:words].join(" ")
		results = []
		search_phrase = "#{phrase} AND lat:[0 to 4]"
		ActionController::Base.logger.info "Query: solr now looking for: #{search_phrase}"
		if q[:words].length
			results = Note.find_by_solr(search_phrase)
			results = results.docs if results
			results = [] if !results
		end

		# debug show results
		ActionController::Base.logger.info "Query: results " if results.length > 0
		results.each do |r|
			ActionController::Base.logger.info "Got #{r.uuid} #{r.title}"
		end

		# return and print results
		return results

#@results = Camera.find_by_solr("powershot"+" AND resolution:[0 TO 4]",

#
# to do now ... build a query so that i can actually query my own database...
# maybe we can do it for everything except term searches without using solr
#
# simple visualization
#	show the people
#	show their relationships
#	show their content
#	show geographic region
#	show filtered searches
#	let members bookmark things
#
# find  pizza in the geographic boundaries from these people
#
# i would have to build a reverse lookup term database
# and there are lots of other implications to search...
# or i can try use solr ... which can surely do it....
#
# or i can also try do it myself...
#

		# rescore entries by objective metrics for now
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

		results = Note.find_by_solr(str,
					:offset => 0,
					:limit => 50,
					#:scores => true,
					:order => "id desc",
					:operator => "and"
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
