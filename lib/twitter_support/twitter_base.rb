require 'net/http'
require 'uri'
require 'open-uri'
require 'hpricot'
require 'json'
require 'lib/geolocate.rb'
require 'twitter'

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
	# save a party from twitter to our database
	# TODO track contrails
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

		# do we have a party like this already?
		party = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })

		# always re geolocate the party
		lat,lon,rad = self.geolocate(location)
		if !lat && !lon
			lat = fallback_lat if fallback_lat
			lon = fallback_lon if fallback_lon
			ActionController::Base.logger.info "Geolocated a party using fallback *********** #{lat} #{lon}"
		end
		ActionController::Base.logger.info "Geolocated a party #{title} to #{lat},#{lon},#{rad} ... #{location}"

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

#test of geolocation improvement
# move this below

		# try geolocate on content or party 
		#- TODO the post itself also includes party information for that moment in time - try?
		lat,lon,rad = self.geolocate(title)
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

#testend

		# We build a model of accumulated posts but don't store posts twice
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid.to_s,
						:kind => kind
						 })


		# update the note if needed
		if note

# test
if lat || lon
note.update_attributes( :lat => lat, :lon => lon, :rad => rad )
end
# test end

			ActionController::Base.logger.info "Note already found #{uuid} #{title}"
			return "Note already found #{uuid} #{title}"
		end

		# else if note undefined then make it

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
				:statebits => ( Note::STATEBITS_DIRTY | Note::STATEBITS_GEOLOCATED )
				)
			note.save

			# build a relationship to the owner - not really needed except for CNG traversals
			# note.relation_add(Note::RELATION_OWNER,party.id)

			# build a relationship to hash tags
			# TODO verify that this works
			args[:title].scan(/#[a-zA-Z]+/).each do |tag|
				note.relation_add(Note::RELATION_TAG,tag[1..-1])
			end

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
		schema = "use 'http://xangel.makerlab.org/yql/twitter.user.profile.xml' as party;"
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
					:begins => Time.parse(blob.created_at)
					)
				party.relation_add(Note::RELATION_FRIEND,1,party2.id)  # party1 has chosen to follow party2
				results << party2
				ActionController::Base.logger.info "saved a friend of #{party.title} named #{party2.title}"
			end
			party.update_attributes(:updated_at => Time.now )
		end
		return results
	end

end
