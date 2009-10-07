
require 'dynamapper/geolocate.rb'
require 'lib/twitter_support/twitter_aggregate.rb'

############################################################################################
#
# Query parsing and handling
#
# What we do here:
#  1) tear apart ordinary queries and return database results
#  2) package this up outside of the application core for clarity and general consolidation
#  3) let us watch what users are asking for so we can optionally search third party databases
#
# A query may consist of
#   1) a person or persons expressed in the @twitter nomenclature for now
#   2) any number of keywords to restrict the search
#   3) a geographic boundary
#   4) a specific geographic location request
#
# Later I would like to extend this to include
#   5) query time bounds TODO
#   6) query radius TODO
#   7) query longitudinal and latitude wraparound TODO
#
# For example a user can ask a question like "@anselm near pdx" which should yield anselm and friends activity in Portland.
#
############################################################################################

class QuerySupport

	# pull out persons, search terms and tags, location such as "@anselm pizza near portland oregon"
	# TODO should publish the query so everybody can see what everybody is searching for
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
		search = ""
		search << words.join(" ") if words.length > 0
		return { :words => words, :partynames => partynames, :placenames => placenames, :search => search }
	end

	#
	# get query location
	# stores the polygonal boundary of the query persistently if found
	#
	def self.query_locate(q,country,map_s,map_w,map_n,map_e)

		# presume no location
		q[:s] = q[:w] = q[:n] = q[:e] = 0.0
		found_boundaries = false
		q[:bounds_from_text] = "false"
		q[:multipolygon] = nil

		# if a country is specified then this always overrules any other location information
		# and we also will set a multipolygon property
		multipolygon = q[:multipolygon] = nil
		if country
			q[:multipolygon] = multipolygon = WorldBoundaries.polygon_country(country)
			if multipolygon
				found_boundaries = true
				map_w, map_e, map_s, map_n = WorldBoundaries.polygon_extent(multipolygon)
				ActionController::Base.logger.info "query: located the query to multipoly #{map_w} #{map_e} #{map_n} #{map_s}"
				q[:s] = map_s.to_f;
				q[:w] = map_w.to_f;
				q[:n] = map_n.to_f;
				q[:e] = map_e.to_f;
			end
		end

		# if we have no boundaries then try to look at hints from the query string if any
		if found_boundaries == false && q[:placenames].length
			lat,lon,rad = 0.0, 0.0, 0.0
			lat,lon,rad = Dynamapper.geolocate(q[:placenames].join(' '))
			rad = 5.0 # TODO hack remove
			if lat < 0.0 || lat > 0.0 || lon < 0.0 || lon > 0.0
				# did we get boundaries from user query as ascii? "pizza near pdx" for example.
				found_boundaries = true
				q[:bounds_from_text] = "true"
				q[:s] = lat - rad
				q[:w] = lon - rad
				q[:n] = lat + rad
				q[:e] = lon + rad
				ActionController::Base.logger.info "query: located the query #{q[:placenames].join(' ')} to #{lat} #{lon} #{rad}"
			end
		end

		# finally, when all else fails, use the supplied boundaries such as from session state
		if found_boundaries == false && ( map_s < 0.0 || map_s > 0.0 || map_w < 0.0 || map_w > 0.0 || map_n > 0.0 || map_n < 0.0 || map_e < 0.0 || map_e > 0.0 )
			q[:s] = map_s.to_f;
			q[:w] = map_w.to_f;
			q[:n] = map_n.to_f;
			q[:e] = map_e.to_f;
			ActionController::Base.logger.info "query: located the query to previous #{map_w} #{map_e} #{map_n} #{map_s}"
		end

		return q
	end

	def self.query(question,map_s,map_w,map_n,map_e,country=nil,restrict=false,synchronous=false)

		# tear apart the query and get back a nicely digested parsed version of it
		q = QuerySupport::query_parse(question)
		s,w,n,e = nil
		words = []

		# allow location query if not restricted to a specific set of users
		if !restrict

			# try to figure out a geographic location for the query based on all the hints we got
			QuerySupport::query_locate(q,country,map_s,map_w,map_n,map_e)

			# location?
			s,w,n,e = q[:s],q[:w],q[:n],q[:e]

			# also add lat long constraints
			# TODO deal with wrap around the planet
			if ( s < 0 || s > 0 || w < 0 || w > 0 || n > 0 || n < 0 || e < 0 || e > 0 )
				conditions << "lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?"
				condition_arguments << s;
				condition_arguments << n;
				condition_arguments << w;
				condition_arguments << e;
			end
		
			# always disallow features with 0,0 as a location
			# TODO this fails
			if true
				conditions << "lat <> ? AND lon <> ?"
				condition_arguments << 0
				condition_arguments << 0
			end

			# terms?
			words = q[:words]
			ActionController::Base.logger.info "Query: now looking for: #{words} at location #{s} #{w} #{n} #{e}"

		end

		# for now - collect right away the actual parties indicated by the nicks
		# TODO debatable if should be here
		if restrict
			q[:parties] = self.twitter_get_parties(q[:partynames])
			#q[:friends] = self.twitter_get_friends(q[:parties])
		end

		# aggregate?
		if synchronous
			ActionController::Base.logger.info "Aggregating synchronously beginning now"
			TwitterSupport::aggregate_memoize(q,true)
			ActionController::Base.logger.info "Aggregating synchronously done now"
		end

		# build search query
		conditions = []
		condition_arguments = []

		# if there are search terms then add them to the search boundary
		# are we totally cleaning words to disallow garbage? TODO
		if(words != nil && words.length > 0 )
			conditions << "description @@ to_tsquery(?)"
			condition_arguments << words.join('&')
			conditions << "title @@ to_tsquery(?)"
			condition_arguments << words.join('&')
		end

		#
		# filter for posts here; we'll collect people related to those posts later
		#
		if true
			conditions << "kind = ?"
			condition_arguments << Note::KIND_POST
		end

		#
		# collect a big old pile of posts
		#
		results_length = 0
		results = []

		#
		# if restricted around the named parties then explicitly get that set
		# TODO this is different enough that it is arguable if we should have it in the same code block
		# TODO not just twitter
		# TODO we could just look at the parties
		#
		if restrict && q[:partynames] && q[:partynames].length
			partyids = []
			q[:partynames].each do |name_or_id|
				party = Note.find(:first, :conditions => { 
						:provenance => "twitter",
						:uuid => name_or_id,
						:kind => Note::KIND_USER
						 })
				next if !party
				partyids << party.id
			end
			if partyids.length > 0
				conditions << "owner_id = ?"
				condition_arguments << partyids
			end
		end

		# TODO pagination

		# perform our query
		ActionController::Base.logger.info "ABOUT TO QUERY #{conditions} and #{condition_arguments.join(' *** ' ) } "
		conditions = [ conditions.join(' AND ') ] + condition_arguments
		Note.all(:conditions => conditions , :limit => 255, :order => "id desc" ).each do |note|
			results << note
			results_length = results_length + 1
		end
		ActionController::Base.logger.info "GOT #{results_length} posts "

		# INJECT PEOPLE?
		#
		# for general cases
		# lets go ahead and inject in only the people who were associated with the posts we found (so the user can see them)
		# TODO this could be cleaned up massively using a bit of smarter SQL that finds uniques only or at least a HASH join
		#

		if !restrict
			people = {}
			results.each do |post|
				person = Note.find(:first,:conditions => { :id => post.owner_id } )
				people[post.owner_id] = person if person != nil
			end
			people.each do |key,value|
				results << value
				results_length = results_length + 1
			end
		end

		# INJECT URLS?
		#
		# for general cases we also have a specific interest in 'entities' such as hashtags, urls, places and clusters
		# here i am injecting 'fake' entities into the stream for now.
		# later the thought is to promote some of the current edges to be first class entities
		# annoyingly since these are not real notes they do not have unique ids.
		# TODO should i promote urls and like concepts to be first class objects? [ probably ]
		#

		if !restrict
			entities = {}
			results.each do |post|
				next if post.kind != Note::KIND_POST
				post.relations_all(Note::RELATION_URL).each do |relation|
					ActionController::Base.logger.info "Query: got url results #{relation.kind} #{relation.value}"
					url = relation.value
					next if entities[url]
					note = Note.new
					note.title = relation.value
					note.id = post.id * 1000000 + relation.id  # TODO such a hack ugh.
					note.lat = post.lat
					note.lon = post.lon
					note.owner_id = post.owner_id
					note.kind = Note::KIND_URL
					entities[url] = note
				end
			end
			entities.each do |key,value|
				results << value
				results_length = results_length + 1
			end
		end

		# extra precise geographic boundaries?
		#
		# for general cases we want to carving against a multipolygon in some cases
		#
		if !restrict
			multipolygon = q[:multipolygon]
			if multipolygon
				ActionController::Base.logger.info "Query: got rough results #{results} #{results_length}"
				temp_results = []
				results_length = 0
				results.each do |result|
					if WorldBoundaries.polygon_inside?(multipolygon,result.lon,result.lat)
					temp_results << result
					results_length = results_length + 1
				end
				results = temp_results
			end
		end

		# return results as well as the rest of the query work
		ActionController::Base.logger.info "Query: got final results #{results} #{results_length}"
		q[:results_length] = results_length
		q[:results] = results

		return q
	end

end
