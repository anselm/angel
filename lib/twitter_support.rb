
require 'net/http'
require 'uri'
require 'hpricot'
require 'json'
require 'lib/geolocate.rb'
require 'twitter'

# A utility class that is actually tightly coupled to the specific datamodel used here
# Didn't want to burden the application model with this because I want to abstract and reuse it somehow
class TwitterSupport

	#
	# Consume inbound streams such as from twitter or other places
	# Publish any response streams needed
	#
	def self.consume
		self.twitter_replies
	#	self.notes_respond_all
	end

	# convenience utility; geolocate
	def self.geolocate(text)
		name = SETTINGS[:site_metacarta_userid]
		password = SETTINGS[:site_metacarta_pass]
		key = SETTINGS[:site_metacarta_key]
		lat,lon = Geolocate.geolocate_via_metacarta(text,name,password,key)
		return lat,lon
	end

	# convenience utility; sanitize
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

	# convenience utility; get a handle on twitter
	def self.twitter_start
		ourname = SETTINGS[:site_twitter_username]
		password = SETTINGS[:site_twitter_password]
		httpauth = Twitter::HTTPAuth.new(ourname,password)
		twitter = Twitter::Base.new(httpauth)
		return twitter
	end

	# collect results from twitter search that might interest us; location,radius,topic.
	def self.twitter_search
		results = []
		lat = SETTINGS[:site_latitude]
		lon = SETTINGS[:site_longitude]
		rad = SETTINGS[:site_radius]
 puts "searching twitter"
		Twitter::Search.new('pizza').geocode(lat,lon,rad).each do |twit|
puts "got a search result #{twit.text}"
			results << self.save_post(
						:id => twit.id,
						:text => twit.text,
						:userid => twit.from_user_id,
						:screenname => twit.from_user,
						:location => twit["location"],
						# :description ? TODO
						:provenance => "twitter",
						:begins => Time.parse(twit.created_at)
						)
		end
		return results
	end

	# collect direct messages to us
	def self.twitter_replies
		results = []
		twitter = self.twitter_start
		twitter.replies().each do |twit|
			results << self.save_post(
						:id => twit.id,
						:text => twit.text,
						:userid => twit.user.id,
						:screenname => twit.user.screen_name,
						:location => twit.user.location,
						#:description => twit.user.description,
						:provenance => "twitter",
						:begins => Time.parse(twit.created_at)
						)
		end
		return results
	end

	# In order to build a relationship graph we need to save information about people as well
	def self.save_party(args)

		noteid = args[:id]
		userid = args[:userid]
		text = args[:text]
		provenance = args[:provenance]
		screenname = args[:screenname]
		location = args[:location]
		description = args[:description]
		last_login_at = args[:begins]
		begins = args[:begins]
		kind = Note::KIND_USER
		uuid = "#{provenance}/#{kind}/#{userid}"

		party = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid,
						:kind => kind
						 })

		lat,lon = self.geolocate(location)  # TODO we could consider using text instead

		if !party
			puts "did not find user #{screenname}"
			party = Note.new(
				:kind => kind,
				:provenance => provenance,
				:title => screenname,
				:description => description,
				:location => location,
				:begins => begins,
				:lat => lat,
				:lon => lon
				)
			party.save
		else
			# TODO store user contrail
			# TODO update description
			party.update_attributes(:title => screenname );

			if lat < 0 || lat > 0 || lon < 0 || lon > 0
				party.update_attributes(:lat => lat, :lon => lon )
			end
		end

		return party

	end

	# Store posts in our data model
	def self.save_post(args)

		noteid = args[:id]
		userid = args[:userid]
		text = args[:text]
		provenance = args[:provenance]
		screenname = args[:screenname]
		location = args[:location]
		description = args[:description]
		last_login_at = args[:begins]
		begins = args[:begins]
		kind = Note::KIND_POST
		uuid = "#{provenance}/#{kind}/#{noteid}"

		# We build a model of accumulated posts but don't store posts twice
		note = Note.find(:first, :conditions => { 
						:provenance => provenance,
						:uuid => uuid,
						:kind => kind
						 })


		return "Note already found #{args[:id]} #{args[:text]}" if note

		# Also we build a model of the participants... this can be outside the transaction block
		party = self.save_party(args)

		# And we're interested in the location of the post
		lat,lon = self.geolocate(text)
	
		# Save the note, tags, and relationships between everything
		begin
                  Note.transaction do
puts "saving #{text}"
			note = Note.new(
				:kind => kind,
				:provenance => provenance,
				:uuid => uuid,
				:title => "",
				:description => text,
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

	# befriend a party on twitter
	# it's possible we can get out of sync so best to try refriend periodically
	# note that the handler throws an error so we have to test first
	def self.befriend(twitter,party)
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

#- rake db migrate
#- full text search
#- debug the above; that i can aggregate, and build a people graph
#- show just some list of results
#- i'd like to trace friend networks after that
#- show working search

	# befriend friends - trace out the social graph a couple of hops
	def self.befriend_friends
		# walk nearby friends
		# walk outwards from there
	end

	# score friends
	def self.score_friends
	end

	# score posts
	def self.score_posts
	end

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

	# delete old posts
	def self.reaper
		# TODO delete old posts
	end

end
