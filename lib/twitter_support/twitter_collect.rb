
require 'lib/twitter_support/twitter_base.rb'

class TwitterSupport

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

end
