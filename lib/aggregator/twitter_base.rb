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
		return last.uuid.to_i if last
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
		location = args[:location] || ""
		description = args[:description] || ""
		last_login_at = args[:begins]
		begins = args[:begins]
		fallback_lat = args[:fallback_lat] || 0
		fallback_lon = args[:fallback_lon] || 0
		fallback_rad = args[:fallback_rad] || 0
		lat = args[:lat] || 0
		lon = args[:lon] || 0
		rad = args[:rad] || 0
		score = args[:score]

		# do we have a party like this already?
		party = args[:party] if args[:party]
		if !party
			party = Note.find(:first, :conditions => { :provenance => provenance, :uuid => uuid.to_s, :kind => kind })
		end

		# locate the party once
		# TODO improve this later to periodically check since the party may move.
		if !party
			if lat == 0 && lon == 0
				lat,lon,rad = Dynamapper.geolocate(location)
			end
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
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED ),
				:created_at => Time.now, # TODO this was failing - verify?
				:updated_at => Time.now
				)
			party.save
			ActionController::Base.logger.info "Saved a new party with title #{title} and score #{score}"
		else
			if lat && lon && lat < 0.0 || lat > 0.0 || lon < 0.0 || lon > 0.0
				# party.update_attributes(:lat => lat, :lon => lon )
			else
				lat = party.lat || 0.0
				lon = party.lon || 0.0
			end

			# scores can only improve not get worse
			score = party.score if party.score < score

			# title can only improve TODO not goodly done 
			title = party.title if party.title != "unresolved"

			# descr can only improve
			description = party.description if party.description && party.description.length > 0

			# location ...
			location = party.location if party.location && party.location.length > 0

			# save changes
			party.update_attributes(
				:title => title,
				:description => description,
				:location => location,
				:score => score,
				:lat => lat,
				:lon => lon,
				:updated_at => Time.now	# IS THIS NEEDED? TODO this was failing verify
				)

			# TODO if a party had a geolocation and it changed we may want to post an empty note with that fact

			ActionController::Base.logger.info "Updated a party with title #{title} and score #{score}"
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
		description = args[:description]
		location = args[:location]
		lat = args[:lat] || 0
		lon = args[:lon] || 0
		rad = args[:rad] || 0
		#last_login_at = args[:begins]
		begins = args[:begins]
		score = 0
		score = party.score if party
		score = args[:score] if args[:score]

		# Do we have this post already?
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		# try geolocate based on content if new post only and only if no location supplied
		if !note && !lat && !lon
			lat,lon,rad = Dynamapper.geolocate(title)
			if !lat && !lon 
				lat = party.lat
				lon = party.lon
				rad = party.rad
				ActionController::Base.logger.info "Geolocated a post using user data *********** #{lat} #{lon}"
			end
			ActionController::Base.logger.info "Geolocated a post #{uuid} to #{lat},#{lon},#{rad} ... #{title}"
		end

		# update note?
		if note
			ActionController::Base.logger.info "Note already found #{uuid} #{title}"
			return note
		end

		# new note?
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
	def self.twitter_get_parties(names_or_ids,score=99)
		results = []
		twitter = twitter_start
		limit = self.twitter_get_remaining_hits
		ActionController::Base.logger.info "Collecting fresh state of a party set #{names_or_ids}"
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
					:score => score
					)
			results << party if party
		end
		return results
	end

	# update parties
	# gives us a blob like this
	#
	# contributors_enabled=false
	# created_at="Mon Mar 05 16:37:33 +0000 2007"
	# description="arts hiking eco env geo sims fog ardevcamp.org meedan.net makerlab.com"
	# favourites_count=8
	# followers_count=1612
	# following=false
	# friends_count=1999
	# geo_enabled=true
	# id=812567
	# lang="en"
	# location="San Francisco, California"
	# name="anselm hook"
	# notifications=false
	# profile_background_color="d8ea1f"
	# profile_background_image_url="http://a3.twimg.com/profile_background_images/13427505/3237764_ef48ae407d_o.jpg"
	# profile_background_tile=false profile_image_url="http://a3.twimg.com/profile_images/706711399/anselm_face_normal.jpg"
	# profile_link_color="1F98C7"
	# profile_sidebar_border_color="398bac"
	# profile_sidebar_fill_color="dd9869"
	# profile_text_color="211221"
	# protected=false
	# screen_name="anselm"
	# status= {
	#	created_at="Wed Feb 24 19:42:22 +0000 2010"
	#   favorited=false
	#   id=9589549592
	#   in_reply_to_screen_name=nil
	#   in_reply_to_status_id=nil
	#   in_reply_to_user_id=nil
	#   source="<a href=\"http://twitterrific.com\"
	#   rel=\"nofollow\">Twitterrific</a>"
	#   text="working out of @souk in portland oregon - very nice"
	#   truncated=false
	# }
	# statuses_count=6086
	# time_zone="Pacific Time (US & Canada)"
	# url="http://hook.org"
	# utc_offset=-28800
	# verified=false
	#

	def self.twitter_update_parties(parties,score = 99)
		results = []
		twitter = twitter_start
		limit = self.twitter_get_remaining_hits
		ActionController::Base.logger.info "Collecting fresh state of a party #{parties}"
		parties.each do |party|
			limit -= 1
			ActionController::Base.logger.info "rate limit is at #{limit}"
			ActionController::Base.logger.debug "oh oh rate limit exceeded" if limit < 1
			break if limit < 1
			blob = twitter.user(party.uuid)
			next if !blob
			party = self.save_party(
					:provenance => "twitter",
					:uuid => blob.id,
					:title => blob.screen_name,
					:location => blob["location"],
					:description => blob.description,
					:begins => Time.parse(blob.created_at),
					:score => score
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

	def self.twitter_get_friends_of_party(twitter,party,results,limit,score=99)
		old = 4.hours.ago
		# TODO always reget this for now because i was concerned about missing updates - re-enable later and test
		if false && party.updated_at > old  # if updated at time is bigger(newer) than 4 hours agos bigness then skip
			ActionController::Base.logger.info "Skip getting friends of #{party.title} - updated recently #{party.updated_at}"
			party.relation_all_siblings_as_notes(Note::RELATION_FRIEND,nil).each do |party2|
				results << party2  # TODO sloppy - just use an array concatenation
			end
			next
		end
		ActionController::Base.logger.info "decided to update this user #{party.title} because #{party.updated_at} is not > #{old}"
		limit = limit - 1
		ActionController::Base.logger.debug "oh oh rate limit exceeded" if limit < 1
		return limit if limit < 1
		twitter.friends({:user_id => party.uuid, :page=>1}).each do |blob|
			party2 = self.save_party(
				:provenance => "twitter",
				:uuid => blob.id,
				:title => blob.screen_name,
				:location => blob["location"],
				:description => blob.description,
				:begins => Time.parse(blob.created_at),
				:score => score
				)
			party.relation_add(Note::RELATION_FRIEND,1,party2.id)  # party1 has chosen to follow party2
			results << party2
			ActionController::Base.logger.info "saved a friend of #{party.title} named #{party2.title}"
		end
		party.update_attributes(:updated_at => Time.now )
		return limit
	end

	# this is deprecated - it doesn't get very many friends - only a dozen or so - the below is better
	def self.twitter_get_friends(parties,score=1)
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		parties.each do |party|
			limit = self.twitter_get_friends_of_party(twitter,party,results,limit,score)
			break if limit < 1
		end
		return results
	end

	# this is preferred - get ids and then later get actual parties - even if incomplete now is better
	def self.twitter_get_friends_ids(parties,score=99) 
		twitter = twitter_start
		results = []
		limit = self.twitter_get_remaining_hits
		return if limit < 1
		time = Time.now
		parties.each do |party|
			twitter.friend_ids({:user_id => party.uuid, :page=>1}).each do |blob|
				party2 = self.save_party(
					:provenance => "twitter",
					:title => 'unresolved',
					:uuid => "#{blob}",
					:begins => time,
					:score => score
					)
				party.relation_add(Note::RELATION_FRIEND,1,party2.id)  # party1 has chosen to follow party2
			end
		end
	end

	# this is perhaps best - just get a round up of friends and their most recent activity
	# it should return a few thousand and their last event
	# TODO I am concerned that if friendships break I am losing that information here.
	# TODO also I am not actually collecting their post
	def self.twitter_get_friends_most_recent_activity(parties,score=99) 
		twitter = twitter_start

		parties.each do |party|

			limit = self.twitter_get_remaining_hits
			return if limit < 1
			time = Time.now

          		ActionController::Base.logger.info "Aggregate::friends_recent_activity starting for #{party.title}"

			count = 0
			# cursor = -1
			cursor = 0
			results = twitter.friends(:user_id => party.uuid, :page => cursor)
			self.twitter_deal_with_these_friends_recent_activity(party,results,score)
			count = count + results.length

          		ActionController::Base.logger.info "Aggregate::friends_recent_activity got #{count} people so far"

			while(results.length > 0 && count < 500)
				# cursor = results.next_cursor
				cursor = cursor + 1
				results = twitter.friends(:user_id => party.uuid, :page => cursor)
				puts "at count #{cursor} we see #{results[0].name}"
				self.twitter_deal_with_these_friends_recent_activity(party,results,score)
				count = count + results.length
          			ActionController::Base.logger.info "Aggregate::friends_recent_activity got #{count} people so far"
			end	
		end
	end

=begin
XXX HERE IS WHAT WE ARE GETTING XXX
<#Hashie::Mashi
 contributors_enabled=false
 created_at="Sat Jul 14 16:09:55 +0000 2007"i
 description=""
 favourites_count=6
 followers_count=561
 following=true
 friends_count=445
 geo_enabled=true
 id=7473062
 lang="en"
 location="Grand Rapids, MI, USA"
 name="George"
 notifications=false
 profile_background_color="9ae4e8"
 profile_background_image_url="http://s.twimg.com/a/1273086425/images/themes/theme1/bg.png" profile_background_tile=false
 profile_image_url="http://a3.twimg.com/profile_images/302435511/674128734_d61cc51275_s_normal.jpg"
 profile_link_color="0000ff"
 profile_sidebar_border_color="87bc44" profile_sidebar_fill_color="e0ff92" profile_text_color="000000" protected=false
 screen_name="mixedfeelings"
 status=<#Hashie::Mash contributors=nil coordinates=nil created_at="Tue May 11 16:18:36 +0000 2010" favorited=false
 geo=<#Hashie::Mash coordinates=[47.674177, -122.304238] type="Point"> 
 id=13796535764 in_reply_to_screen_name=nil in_reply_to_status_id=nil in_reply_to_user_id=nil place=nil
 source="<a href=\"http://www.atebits.com/\" rel=\"nofollow\">Tweetie</a>"
 text="Wearing my punkest t-shirt to get grimy for 3 days on a train." truncated=false>
 statuses_count=3816 time_zone="Eastern Time (US & Canada)" url="http://www.g-rad.org" utc_offset=-18000 verified=false>
=end

	def self.twitter_deal_with_these_friends_recent_activity(party,results,score=99)

		if party && results && results.length > 0

			results.each do |blob|

				# get location
				lat = 0
				lon = 0
				if(blob.status.geo != nil)
					lat = blob.status.geo.coordinates[0]
					lon = blob.status.geo.coordinates[1]
				end

 				ActionController::Base.logger.info "Friend of #{party.title}: #{blob.screen_name} at LOC #{blob.geo} #{blob.status.geo} #{lat} #{lon}"

				# save new party
				party2 = self.save_party(
					:provenance => "twitter",
					:uuid => blob.id,
					:title => blob.screen_name,
					:location => blob["location"],
                                        :lat => lat,
                                        :lon => lon,
					:description => blob.description,
					:begins => Time.parse(blob.created_at),
					:score => score
					)

				# establish a link between parties where party2 is an esteemed friend of party1
				party.relation_add(Note::RELATION_FRIEND,1,party2.id)

				# save post associated with new party
                        	post = self.save_post(party2,
                                        :provenance => "twitter",
                                        :uuid => blob.status.id,
                                        :title => blob.status.text,
                                        :location => blob.location,
                                        :lat => lat,
                                        :lon => lon,
                                        :begins => Time.parse(blob.status.created_at),
                                        :score => score
                                        )
			end
		end
	end
	##########################################################################################################
	# collect results from twitter search that might interest us; location,rad,topic.
	# geolocate posts here if they don't have any better details
    # TODO can we only get results newer than x (no)
	# TODO can we do without a specific term?
	# TODO slightly worried that a bad rad might be passed in
	##########################################################################################################

	def self.twitter_search_unused(terms,map_s,map_w,map_n,map_e,score=99)

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
						:score => score
						#:description => twit.user.description, TODO ( a separate query )
						#:begins => Time.parse(twit.created_at) TODO ( a separate query )
						)

			# and the posts
			lat = 0
			lon = 0
			if twit["geo"] && twit["geo"]["coordinates"]
				lat = twit["geo"]["coordinates"][0]
				lon = twit["geo"]["coordinates"][1]
			end
			post = self.save_post(party,
						:provenance => provenance,
						:uuid => twit.id,
						:title => twit.text,
						:location => twit["location"],
						:lat => lat,
						:lon => lon,
						:rad => rad,
						:begins => Time.parse(twit.created_at),
						:score => score
						)

			parties << party
			posts << post
		end
		return posts,parties
	end

	##########################################################################################################
	# collect messages from a single person more recent than last collection only - also add them to system
	##########################################################################################################

	# gives us a blob like this
	#
    # contributors=nil
	# created_at="Wed Feb 24 19:42:22 +0000 2010"
	# favorited=false geo=nil
	# id=9589549592
	# in_reply_to_screen_name=nil
	# in_reply_to_status_id=nil
	# in_reply_to_user_id=nil
	# source="<a href=\"http://twitterrific.com\" rel=\"nofollow\">Twitterrific</a>"
	# text="working out of @souk in portland oregon - very nice"
	# truncated=false
	# user {
	#   contributors_enabled=false
	#   created_at="Mon Mar 05 16:37:33 +0000 2007"
	#   description="arts hidan.net makerlab.com"
	#   favourites_count=8
	#   followers_count=1612
	#   following=false
	#   friends_count=1999
	#   geo_enabled=true
	#   id=812567
	#   lang="en"
	#   location="San Francisco, California"
	#   name="anselm hook"
	#   notifications=false
	#   profile_background_color="d8ea1f"
	#   profile_background_image_url="http://a3.twimg.com/profile_background_images/13427505/3237764_ef48ae407d_o.jpg"
	#   profile_background_tile=false
	#   profile_image_url="http://a3.twimg.com/profile_images/706711399/anselm_face_normal.jpg"
	#   profile_link_color="1F98C7"
	#   profile_sidebar_border_color="398bac"
	#   profile_sidebar_fill_color="dd9869"
	#   profile_text_color="211221"
	#   protected=false
	#   screen_name="anselm"
	#   statuses_count=6086
	#   time_zone="Pacific Time (US & Canada)"
	#   url="http://hook.org"
	#   utc_offset=-28800
	#   verified=false
	# }
	#

	def self.twitter_refresh_timeline(party,score=99)

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

begin 
		ActionController::Base.logger.info "refresh for #{party.title} since #{since_id}"
		if since_id > 0
			list = twitter.user_timeline(:user_id=>party.uuid,:count=>20,:since_id=>since_id)
		else
			list = twitter.user_timeline(:user_id=>party.uuid,:count=>20)
		end
		updated_party = false
rescue
  ActionController::Base.logger.info "bad - something broken with authentication"
  return
end
  
		# ignore the supplied score and use the one set at creation time for now TODO is this ok?
		score = party.score

		list.each do |twit|

			lat = 0
			lon = 0
			if twit["geo"]
				lat = twit["geo"]["coordinates"][0]
				lon = twit["geo"]["coordinates"][1]
			end
			ActionController::Base.logger.info("LOCATION #{twit['geo']}")

			# update party information as well for convenience
			# Often parties are "empty" and have no data at all - this is a way to fill them out.
			if !updated_party
				updated_party = true
				self.save_party(
						:provenance => "twitter",
						:uuid => twit.user.id,
						:title => twit.user.screen_name,
						:location => twit["location"],
						:description => twit.user.description,
						#:begins => Time.now,
						:score => score
						)
			end

			results << self.save_post(party,
					:provenance => provenance,
					:uuid => twit.id,
					:title => twit.text,
					:location => twit.user.location,
					:lat => lat,
					:lon => lon,
					:begins => Time.parse(twit.created_at),
					:score => score
					)

			# TODO peek into the tweets to find people in their social graph and upscore those

		end

		return results
	end

	def self.twitter_get_profiles_and_timelines(parties,score=1)
		parties.each do |party|
			self.twitter_refresh_timeline(party,score)
		end
	end

	##########################################################################################################
	# yql get the timelines of a pile of people - this is a crude way of seeing somebodys own view of reality
	# TODO could also maybe do searches and geographic bounds
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as party;select * from party where id = 'anselm' and title like '%humanist%';
	# TODO use more recent than ( cannot do this )
	# TODO yahoo api rate limits
	##########################################################################################################

	def self.yql_twitter_get_timelines_unused(parties,score=99)

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

			lat = 0
			lon = 0
			if goop["geo"] && goop["geo"]["coordinates"]
				lat = goop["geo"]["coordinates"][0]
				lon = goop["geo"]["coordinates"][1]
			end

			# save the post
			self.save_post(party,{
					:provenance => "twitter",
					:uuid => uuid,
					:title => title,
					:location => party.location,
					:lat => lat,
					:lon => lon,
					:begins => begins,
					:score => score
					})

		end

	end


=begin

	##########################################################################################################
	# collect direct messages to us
	# turn off because we don't need it yet
	# TODO - can we only get results newer than x please?
	##########################################################################################################

	def self.twitter_get_replies_unused(score = 99)
		results = []
		twitter = self.twitter_start
		twitter.replies().each do |twit|
			# build a model of the participants...
			party = self.save_party(
						:provenance => "twitter",
						:uuid => twit.from_user_id,
						:title => twit.from_user,
						:location => twit["location"],
						:score => score
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
						:score => score
						)
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

	def self.twitter_update_friends_of_party(twitter,partyid,score=99)
		twitter.friends({:user_id=>partyid,:page=>0}).each do |v|
			party = self.save_party(
						:provenance => "twitter",
						:uuid => v.id,
						:title => v.screenname,
						:location => v["location"],
						:description => v.description,
						:begins => Time.parse(v.created_at),
						:score => score
						)
		end
	end

	##########################################################################################################
	# twitter get an updated timeline using yql and in this case friendfeed
	# i decided this was a bad idea because what if person x is not on friendfeed? does this read through?
	# TODO FINISH
	# TODO we have to find a way to do this asynchronously or cap the returns
	# use 'http://angel.makerlab.org/yql/twitter.user.timeline.xml' as ff;
	# select * from ff where id='anselm';
	##########################################################################################################

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


end
