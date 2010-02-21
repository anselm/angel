require 'net/http'
require 'uri'
require 'open-uri'
require 'hpricot'
require 'json'
require 'lib/dynamapper/geolocate.rb'
require 'twitter'
require 'app/models/note.rb'

class TwitterSupport

  ###########################################################################################
  # expand urls... decompress bit.ly and tr.im and the like - helper utility
  ###########################################################################################

  def self.expand_url(url)
    begin
      timeout(60) do
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host)
        http.open_timeout = 30
        http.read_timeout = 60
        return nil if uri.host != 'bit.ly' && uri.host != 'tinyurl.com' && uri.host != 'tr.im'
        ActionController::Base.logger.info "expand_url considering #{url} #{uri.host}"
        if uri.host == "ping.fm" || uri.host == "www.ping.fm"
          ActionController::Base.logger.info "ping.fm requires us to fetch the body"
          response = http.get(uri.path)
          return nil
        else
          response = http.head(uri.path) # get2(uri.path,{ 'Range' => 'bytes=0-1' })
          if response.class == Net::HTTPRedirection || response.class == Net::HTTPMovedPermanently
                ActionController::Base.logger.info "expand_url revision #{response} #{url} -> #{response['location']}"
                return response['location']
          # phishing block
          #else if response['location'].include?("bit.ly/app/warning")
	  #	return response['location']
          end
        end
      end
    rescue Timeout::Error => errormsg
      ActionController::Base.logger.info "expand_url timeout on #{url} #{errormsg}"
    rescue => exception
      ActionController::Base.logger.info "expand_url inner rescue error #{exception} while fetching #{url}"
      return nil
    end
    return nil
  end

  def self.expand_all_urls
    # fix the broken links
    Relation.find(:all, :conditions => { :kind => Note::RELATION_URL } ).each do |r|
      ActionController::Base.logger.info "expand_all_urls: looking at relationship #{r.value}"
      fixed = expand_url(r.value)
      if fixed
        r.value = fixed
        r.save
      end
    end
  end

  ###########################################################################################
  # attach relation objects to notes for each unique url in the note - helper utility
  ###########################################################################################

  def self.attach_note_to_urls(note)
      ammended = false
      begin 
            parts = note.title.split
            newparts = []
            parts.each do |part|
               segments = part.grep(/http[s]?:\/\/\w/)
               if segments.length < 1
                  newparts << part
               else
                  segments.each do |uri_str|
                      ActionController::Base.logger.info "attach_note_to_urls: pondering #{uri_str}"
                      expanded = expand_url(uri_str)
                      if expanded != nil
                          ammended = true
                          uri_str = expanded
                          newparts << uri_str
                      end
                      note.relation_add(Note::RELATION_URL,uri_str)
                  end
               end
            end
            if ammended == true && newparts.length > 0 
              title = newparts.join(' ')
              note.update_attribute(:title, title )
              ActionController::Base.logger.info "attach_note_to_urls: saved note revision #{title}"
            end
      rescue Timeout::Error => errormsg
        ActionController::Base.logger.info "attach_note_to_urls: timeout failed on #{note.title} #{errormsg}"
      rescue => errormsg
        ActionController::Base.logger.info "attach_note_to_urls: failed on #{note.title} #{errormsg}"
      end
      return ammended
  end

	def self.attach_all_notes_to_all_urls
		Note.find(:all, :conditions => { :kind => Note::KIND_POST } ).each do |note|
			self.attach_note_to_urls(note)
		end
	end

	def self.attach_note_to_tags(note)

			begin
				tags = {}
				note.title.gsub(/ ?(#\w+)/) { |tag| tag = tag.strip[1..-1].downcase; tags[tag] = tag }
				tags.each do |key,tag|
					note.relation_add(Note::RELATION_TAG,tag)
				end
			rescue
			end

                        #note.title.scan(/#[a-zA-Z]+/).each do |tag|
                        #       note.relation_add(Note::RELATION_TAG,tag[1..-1])
                        #end
	end

	###########################################################################################
	# encode url for http
	###########################################################################################

	def self.url_escape(string)
		string.gsub(/([^a-zA-Z0-9_-]+)/n) do
			'%' + $1.unpack('H2' * $1.size).join('%').upcase
		end.tr(' ', '%20')
	end

	###########################################################################################
	# geolocate all existing content - convenience utility
	###########################################################################################

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
	# clean up text of twitter posts - convenience utility
	###########################################################################################

	def self.twitter_sanitize(text)
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
	# twitter handle - start twitter
	###########################################################################################

	def self.twitter_start()
		ourname = SETTINGS[:site_twitter_username]
		password = SETTINGS[:site_twitter_password]
		httpauth = Twitter::HTTPAuth.new(ourname,password)
		@@twitter_handle = Twitter::Base.new(httpauth)
		return @@twitter_handle
	end

	##########################################################################################################
	# twitter get at the rate limiter - CACHE THIS TODO
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
		last = Note.find(:last, :order => 'uuid',
					:conditions => {
						:kind => Note::KIND_POST,
						:owner_id => party.id,
						:provenance => provenance
						}
				)
		ActionController::Base.logger.info "the last posted post of this party #{party.title} is #{last.uuid}" if last
		return last.uuid if last
		return 0
	end

	##########################################################################################################
	# befriend a party on twitter - this is tricky to get right - supply an object
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
	# save a party from twitter to our database
	##########################################################################################################

	def self.save_party(args)

		# pull out arguments that caller should supply
		kind = Note::KIND_USER
		provenance = args[:provenance]
		uuid = args[:uuid]
		title = args[:title]
		location = args[:location]
		description = args[:description]
		last_login_at = args[:begins]
		begins = args[:begins]
		fallback_lat = args[:fallback_lat]
		fallback_lon = args[:fallback_lon]
		fallback_rad = args[:fallback_rad]
		score = args[:score] || 99 # a lower score means it is more important to users of the site

		# do we have a party like this already?
		party = args[:party] if args[:party]
		if !party
			party = Note.find(:first, :conditions => { :provenance => provenance, :uuid => uuid.to_s, :kind => kind })
		end

		# locate the party once
		# TODO improve this later to periodically check since the party may move.
		lat = lon = rad = 0
		if !party
			lat,lon,rad = Dynamapper.geolocate(location)
			if !lat && !lon
				lat = fallback_lat if fallback_lat
				lon = fallback_lon if fallback_lon
				ActionController::Base.logger.info "Geolocated a party using fallback *********** #{lat} #{lon}"
			end
			ActionController::Base.logger.info "Geolocated a party #{title} to #{lat},#{lon},#{rad} ... #{location}"
		end

		# add the party if new or just update features
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
				:score => score,
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED )
				)
			party.save
			ActionController::Base.logger.info "Saved a new party with title #{title}"
		else
			# TODO note that for some reason :updated_at is not set as it should be
			party.update_attributes(:title => title, :description => description );
			if lat && lon && lat < 0.0 || lat > 0.0 || lon < 0.0 || lon > 0.0
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

		# pull out properties caller should supply
		kind = Note::KIND_POST
		provenance = args[:provenance]	
		uuid = args[:uuid]
		title = args[:title]
		location = args[:location]
		description = args[:description]
		#last_login_at = args[:begins]
		begins = args[:begins]
		fallback_lat = args[:fallback_lat]
		fallback_lon = args[:fallback_lon]
		fallback_rad = args[:fallback_rad]
		score = 0
		score = args[:score] if args[:score]
		score = party.score if party

		# Do we have this post already?
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		# geolocate - once only for now
		lat = lon = rad = 0
		if !note
			lat,lon,rad = Dynamapper.geolocate(title)
			if !lat && !lon 
				lat = party.lat
				lon = party.lon
				rad = party.rad
				ActionController::Base.logger.info "Geolocated a post using user data *********** #{lat} #{lon}"
			end
			if lat == 0 && lon == 0
				lat = fallback_lat if fallback_lat
				lon = fallback_lon if fallback_lon
				ActionController::Base.logger.info "Geolocated a post using fallback data *********** #{lat} #{lon}"
			else
				ActionController::Base.logger.info "Lat and lon are not zero #{lat} #{lon}"
				ActionController::Base.logger.info "Lat and lon are not zero #{fallback_lat} #{fallback_lon}"
			end
			ActionController::Base.logger.info "Geolocated a post #{uuid} to #{lat},#{lon},#{rad} ... #{title}"
		end

		# update note?
		if note

			if lat > 0.0 || lat < 0.0 || lon > 0.0 || lon < 0.0
				note.update_attributes( :lat => lat, :lon => lon, :rad => rad )
			end

			ActionController::Base.logger.info "Note already found #{uuid} #{title}"
			return "Note already found #{uuid} #{title}"
		end

		# new note?

		# for now test turn of assertion catching because there's no point to silently failing ( but leave the transaction block on )
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
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED ),
				:score => score
				)
			note.save

			# build a relationship to the owner - not really needed except for CNG traversals ( off for now )
			# note.relation_add(Note::RELATION_OWNER,party.id)

			self.attach_note_to_tags(note)

		 	self.attach_note_to_urls(note)

			ActionController::Base.logger.info "Saved a new post from #{party.title} ... #{title}"

		end
		#rescue
		#	ActionController::Base.logger.debug "badness - failed to save the post"
		#end
		return note
	end

	##########################################################################################################
	# twitter get a set of people objects from their names
	##########################################################################################################

=begin
	# get parties via yql - the idea is it would scale more but is the same as below
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
	# note that the twitter assigned id is not always the same as the screen name and the screen name can change
	# TODO should not bang on twitter so much
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
					:begins => Time.parse(blob.created_at),
					:score => 0
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
	# TODO only gets one page full ( 100 only! )
	# TODO manual updated_at? for some reason this has to be done explicity - note that we rely on this behavior - and it is implicit
	##########################################################################################################

	def self.twitter_get_friends(parties)
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		old = 4.hours.ago
		parties.each do |party|
			# TODO always reget this for now because i was concerned about missing updates - re-enable later and test
			if false && party.updated_at > old  # if updated at time is bigger(newer) than 4 hours agos bigness then skip
				ActionController::Base.logger.info "Skip getting friends of #{party.title} - updated recently #{party.updated_at}"
				party.relation_all_siblings_as_notes(Note::RELATION_FRIEND,nil).each do |party2|
					results << party2  # TODO sloppy - just use an array concatenation
				end
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
					:begins => Time.parse(blob.created_at),
					:score => 1
					)
				party.relation_add(Note::RELATION_FRIEND,1,party2.id)  # party1 has chosen to follow party2
				results << party2
				ActionController::Base.logger.info "saved a friend of #{party.title} named #{party2.title}"
			end
			party.update_attributes(:updated_at => Time.now )
		end
		return results
	end

	##########################################################################################################
	# collect results from twitter search that might interest us; location,rad,topic.
	# geolocate posts here if they don't have any better details
    # TODO can we only get results newer than x (no)
	# TODO can we do without a specific term?
	# TODO slightly worried that a bad rad might be passed in
	##########################################################################################################

	def self.twitter_search(terms,map_s,map_w,map_n,map_e)

		ActionController::Base.logger.info "Searching for #{terms.join(' ')} near #{map_s} #{map_w} #{map_n} #{map_e}"

		if self.twitter_get_remaining_hits < 1
			# TODO what should we do?
			ActionController::Base.logger.debug("hit twitter rate limit")
			return [],[]
		end

		provenance = "twitter"

		posts = []
		parties = []
		blob = []
		# turn into ordinary center and radius
		# TODO radius is wrong
		lat = map_n - map_s / 2 + map_s
		lon = map_w - map_e / 2 + map_e
		rad = 5
		twitter_rad = "25mi"

		# do a general purpose search with location if any else just do a search
		begin
			if map_s < 0.0 || map_s > 0.0 || map_n < 0.0 || map_n > 0.0 || map_e < 0.0 || map_e > 0.0 || map_w < 0.0 || map_w > 0.0
				blob = Twitter::Search.new(terms.join(' ')).geocode(lat,lon,twitter_rad)  # TODO try conflating this verbosity
				ActionController::Base.logger.debug("twitter_search with #{terms} and lat lon #{lat} #{lon}")
			else
				blob = Twitter::Search.new(terms.join(' '))
				ActionController::Base.logger.debug("twitter_search with #{terms} without lat or lon")
			end
		rescue
		end

		if !blob || blob.length < 1
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
						:fallback_rad => rad,
						:score => 0
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
						:begins => Time.parse(twit.created_at),
						:score => 1
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
		provenance = "twitter"

		if self.twitter_get_remaining_hits < 1
			# TODO what should we do?
			ActionController::Base.logger.debug("hit twitter rate limit")
			return []
		end

		# other options: max_id, #page, #since
		results = []
		since_id = self.get_last_post(party,provenance)
		list = twitter.user_timeline(:user_id=>party.uuid,:count=>20,:since_id=>since_id)

		list.each do |twit|
			ActionController::Base.logger.info "timeline - got a message #{twit.text}"
			results << self.save_post(party,
					:provenance => provenance,
					:uuid => twit.id,
					:title => twit.text,
					:location => twit.user.location,
					:begins => Time.parse(twit.created_at),
					:score => 0
					)
		end

		return results
	end

	def self.twitter_get_timelines(parties)
		parties.each do |party|
			self.twitter_refresh_timeline(party)
		end
	end

	##########################################################################################################
	# collect direct messages to us
	# turn off because we don't need it yet
	# TODO - can we only get results newer than x please?
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
						:location => twit["location"],
						:score => 0
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)
			# and the posts
			results << self.save_post(party,
						:provenance => "twitter",
						:uuid => twit.id,
						:title => twit.text,
						:location => twit.user.location,
						:begins => Time.parse(twit.created_at),
						:score => 0
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
						:begins => Time.parse(v.created_at),
						:score => 1
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
					:begins => begins,
					:score => 0
					})

		end

	end

end
