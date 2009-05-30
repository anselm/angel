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
		lat,lon = Geolocate.geolocate_via_metacarta(text,name,password,key)
		return lat,lon
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
	# twitter update a timeline using yql
	# TODO FINISH
	# TODO we have to find a way to do this asynchronously or cap the returns
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as ff;
	# select * from ff where id='anselm';
	##########################################################################################################

	def self.yql_twitter_update_timeline(partyname)
		yql = "http://query.yahooapis.com/v1/public/yql?q="
		schema = "use 'http://www.javarants.com/friendfeed/friendfeed.feeds.xml' as ff;"
		query = "select * from ff where nickname='#{partyname}' and service='twitter';"
		fragment = "#{schema};#{query}"
		url = "#{yql}#{url_escape(fragment)}" # is ignored why? ;&format=json"
		response = Hpricot.XML(open(url))
		response_name = response.innerHTML.strip
	end

	##########################################################################################################
	# twitter get at the rate limiter
	# TODO cache
	##########################################################################################################

	def self.twitter_get_remaining_hits
		response = open("http://twitter.com/account/rate_limit_status.json"
						#, :http_basic_authentication => [Config[:username], Config[:password]]).read
						)
		return JSON.parse(response,)['remaining_hits']
	end

	##########################################################################################################
	# twitter get a set of people objects from their names
	# TODO finish
	##########################################################################################################

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

	def self.twitter_get_parties(names_or_ids)
		results = []
		twitter = twitter_start
		limit = self.twitter_get_remaining_hits
		names_or_ids.each do |name_or_id|
			limit--
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
	##########################################################################################################

	def self.twitter_get_friends(parties)
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		parties.each do |party|
			next if party.updated_at < 24.hours.ago
			limit--
			break if limit < 1
puts "decided to update this user because #{1.hours.ago} is #{party.updated_at}"
			twitter.friends({:user_id => party.uuid, :page=>1}).each do |blob|
				party = self.save_party(
						:provenance => "twitter",
						:uuid => blob.id,
						:title => blob.screen_name,
						:location => blob["location"],
						:description => blob.description,
						:begins => Time.parse(blob.created_at)
						)
				results << party if party
puts "saved a friend named #{party.title}"
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

	##########################################################################################################
	# befriend a party on twitter - supply an object
	# it's possible we can get out of sync so best to try refriend periodically
	# note that the handler throws an error so we have to test first
	##########################################################################################################

	def self.twitter_befriend(twitter,party)
		ourname = SETTINGS[:site_twitter_username]
		if( party.statebits & STATEBITS_FRIENDED == 0 ) 
			begin
				twitter.create_friendship(party.title) if !twitter.friendship_exists?(ourname,party.title)
				party.statebits = Note::STATEBITS_FRIENDED
				party.save
			rescue
			end
		else
		end
	end

	##########################################################################################################
	# collect results from twitter search that might interest us; location,radius,topic.
	# TODO can we only get results newer than x
	# TODO can we do without a specific term?
	##########################################################################################################

	def self.twitter_search(lat,lon,rad)
		results = []
		Twitter::Search.new(' ').geocode(lat,lon,rad).each do |twit|

			# build a model of the participants...
			party = self.save_party(
						:provenance => "twitter",
						:uuid => twit.from_user_id,
						:title => twit.from_user,
						:location => twit["location"]
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)

			# and the post
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
	# TODO - can we only get results newer than x
	##########################################################################################################

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

	##########################################################################################################
	# collect messages from a single person more recent than last collection only - also add them to system
	# TODO switch to YQL
	##########################################################################################################

	def self.twitter_get_timeline(partyid)

		provenance = "twitter"
		kind = Note::KIND_USER
		uuid = partyid
		since_id = 0

		twitter = self.twitter_start

		# build a model of the participant...
		twit = twitter.user(partyid)
		party = self.save_party(
					:provenance => "twitter",
					:uuid => twit.id,
					:title => twit.screen_name,
					:location => twit["location"],
					:description => twit.description,
					:begins => Time.parse(twit.created_at)
					)
		if party
			last = Note.find(:last, :order => 'created_at',
									:conditions => {	:kind => Note::KIND_POST,
														:owner_id => party.id,
														:provenance => "twitter"
													}
							)
	puts "the last id of this party #{party.title} is #{last.id}" if last
			since_id = last.id if last
		end

		# collect and store their recent activity... bizarrely this also encapsulates their full description.
		results = []
		twitter.user_timeline(:user_id=>partyid,:count=>200,:since_id=>since_id).each do |twit|
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

		lat,lon = self.geolocate(location)  # TODO we could consider using the users description as a fallback.

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
				#:begins => begins, we want this TODO
				:statebits => 0
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
	# TODO reaper
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

		# And we're interested in the location of the post
		lat,lon = self.geolocate(text)
	
		# Save the note, tags, and relationships between everything
		begin
		  Note.transaction do
puts "saving #{text}"
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
				:statebits => Note::STATEBITS_UNRESPONDED
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

	# Response handling is kept separate from consuming inputs; they are asynchronous for stability and speed
	# TODO respond more intelligently
	def self.respond_all_this_is_currently_unused
		twitter = self.twitter_start
		results = []
		Note.all(:statebits => Note::STATEBITS_UNRESPONDED).each do |note|
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

	def self.merge_dupes
		# i think we could do this on the database itself...
		# for example if something is a reply then it is a kind of cluster
		# and if something is talking about the same url then it is a kind of cluster
		# and if it has the same words then its the same topic too...
		# - i could totally delete the dupe
		# - ...
	end

#
# ed really wants to find urls ... so if we are seeing duplicate or similar text blocks...
# if we see duplicate or similar urls...
# we want to build an index of these - of urls and pointers back to notes
# 

# i really want to show sentiment in an area and let people see issues and crisis more clearly
# and i really want to find a way to merge together duplicates
# and filter by social networks
# and do ordinary searches
#
# so most parts of the query are conventional; select by persons, select by geographic area
# the full text search part requires solr
#
#

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

	###########################################################################################
	# perform a query that may cause traffic to twitter and the like
	###########################################################################################

	def self.query(phrase)
		# tear apart the query
		q = self.query_parse(phrase)
		# let's go ahead and find the friends of the friends to extend the search range
		q[:parties] = self.twitter_get_parties(q[:partynames])
		q[:friends] = self.twitter_get_friends(q[:parties])

return []

		# permit the parties to have their timelines updated; this may be asynchronous if slow
		q[:parties].each { |party| self.twitter_refresh_timeline(party) }
		q[:friends].each { |party| self.twitter_refresh_timeline(party) }
		# get time TODO
		q[:begins] = nil
		q[:ends] = nil
		# geocode boundary - allow only one boundary for now ( if any )
		q[:location] = Geolocate.geolocate_via_metacarta(q[:places].join(' ')) if q[:places].length
		# perform the query

		# now we have the parts of a query
		# select * from notes where owner_id = { any party }"
		# and lon > minimum and lon < maximum and lat > minimum and lat < maximum
		# and title ilike "%term%" or title ilike "%term%" or title ilike "%term%"
	end

end
