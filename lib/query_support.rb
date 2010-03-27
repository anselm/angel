
require 'dynamapper/geolocate.rb'
require 'lib/twitter_support/twitter_aggregate.rb'

############################################################################################
#
# Utility to pick apart query parameters
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
		return {} if !phrase || phrase.length < 1
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
		if found_boundaries == false && q[:placenames] && q[:placenames].length
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
			ActionController::Base.logger.info "query: located the query to explicit #{map_w} #{map_e} #{map_n} #{map_s}"
		end

		return q
	end
	
	#
	# INJECT URLS?
	#
	# for general cases we also have a specific interest in 'entities' such as hashtags, urls, places and clusters
	# here i am injecting 'fake' entities into the stream for now.
	# later the thought is to promote some of the current edges to be first class entities
	# annoyingly since these are not real notes they do not have unique ids.
	# TODO should i promote urls and like concepts to be first class objects? [ probably ]
	#
	def self.inject_urls(results)
		ActionController::Base.logger.info "Query: injecting urls ************************ *********************************"
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

	def self.query(params,session)

		question = nil
		country = nil
		synchronous = false
		inject = true
		offset = 0
		length = 100
		utc = 0
		s = w = n = e = 0.0
		rad = nil
		lon = 0.0
		lat = 0.0
		sort = false

		# build query from raw question string
		q = QuerySupport::query_parse(params[:q])

		# accept an explicit country code - this will override the location boundary supplied above
		country = params[:country] if params[:country] && params[:country].length > 1

		# internal development test feature; test twitter aggregation
		synchronous = true if params[:synchronous] && params[:synchronous] == "true"

		# internal development test feature; do not get urls
		inject = false if params[:noinject] && params[:noinject] == "true"

		# pagination
		offset = params[:offset].to_i if params[:offset] && params[:offset].length > 0
		length = params[:length].to_i if params[:length] && params[:length].length > 0

		# last time fetched key
		utc = params[:utc].to_i if params[:utc] && params[:utc].length > 0

		# bounds
		s = session[:s] = params[:s].to_f if params[:s]
		w = session[:w] = params[:w].to_f if params[:w]
		n = session[:n] = params[:n].to_f if params[:n]
		e = session[:e] = params[:e].to_f if params[:e]

		# get bounds optional approach
		rad = params[:rad].to_f if params[:rad]
		lon = params[:lon].to_f if params[:lon]
		lat = params[:lat].to_f if params[:lat]
		if rad != nil && rad > 0.0 && lon != 0 && lat != 0
			s = lat - rad
			n = lat + rad
			w = lon - rad
			e = lon + rad
			sort = true
		end

		# hack - deal with datelines - improve later TODO
		if w > e
			if w > 0
				w = w - 360
			else
				e = e + 360
			end
		end

		#
		# settle on a final geographic location based on all hints
		#

		QuerySupport::query_locate(q,country,s,w,n,e)
		s,w,n,e = q[:s],q[:w],q[:n],q[:e]
		ActionController::Base.logger.info "Query: now looking at location #{w} #{e} #{n} #{s}"

		#
		# store arguments
		#

		q[:synchronous] = synchronous
		q[:country] = country
		q[:inject] = inject
		q[:offset] = offset
		q[:length] = length
		q[:utc] = utc
		q[:log] = [ "Query Started" ]

		#
		# build sql statement
		#

		conditions = []
		condition_arguments = []

		# restrict query by geography?
		if ( s != 0 || n != 0 || w != 0 || e != 0 ) 
			conditions << "lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?"
			condition_arguments << s;
			condition_arguments << n;
			condition_arguments << w;
			condition_arguments << e;
		end
		
		# always disallow features with 0,0 as a location
		# TODO this fails... it still includes features that are at 0,0!
		if true
			conditions << "lat <> ? AND lon <> ?"
			condition_arguments << 0
			condition_arguments << 0
		end

		#
		# if there are search terms then add them to the search boundary
		# TODO sanitize all search terms
		#
	
		if q[:words] && q[:words].length > 0
			words = q[:words]
			conditions << "description @@ to_tsquery(?)"
			condition_arguments << words.join('&')
			conditions << "title @@ to_tsquery(?)"
			condition_arguments << words.join('&')
			q[:log] << "Query: now looking for: #{words}"
			ActionController::Base.logger.info "Query: now looking for: #{words}"
		end

		#
		# filter by posts or users
		#
		if true
			conditions << " ( kind = ? OR kind = ?) "
			condition_arguments << Note::KIND_POST
			condition_arguments << Note::KIND_USER
		end

		#
		# Give aggregator an opportunity to flesh out parties if it can do so quickly
		#

		TwitterSupport::aggregate_memoize(q,synchronous)

		#
		# If parties are supplied then limit results to parties ( and possibly friends of parties )
		#

		if q[:partynames] && q[:partynames].length
			ActionController::Base.logger.info "Query: since a party was specified limit results *********"
			partyids = []
			if q[:parties] && q[:parties].length > 0
				partyids = q[:parties].collect { |party| party.id }
			else
				q[:partynames].each do |name|
					ActionController::Base.logger.info "Query: looking for #{name}"
					party = Note.find(:first, :conditions => { 
							:provenance => "twitter",
							:title => name,
							:kind => Note::KIND_USER
							 })
					next if !party
					ActionController::Base.logger.info "Query: found #{name_or_id}"
					partyids << party.id
				end
			end
			if partyids.length > 0
				conditions << "owner_id = ?"
				condition_arguments << partyids
			end

# TODO we need to include friends and maybe friends of friends

		end

		#
		# Perform the query!
		#
		# TODO not wise to copy the database iterator to an array - try avoid this
		#

@limit = 10

		results = []
		results_length = 0
		conditions = [ conditions.join(' AND ') ] + condition_arguments
		ActionController::Base.logger.info "Query: performing query ************************************"
		ActionController::Base.logger.info "ABOUT TO QUERY #{conditions.join(' ')} and #{condition_arguments.join(' ' ) } "
		q[:log] << "ABOUT TO QUERY #{conditions} and #{condition_arguments.join(' *** ' ) } "
		Note.all(:conditions => conditions , :offset => @offset , :limit => @limit, :order => "id desc" ).each do |note|
			results << note
			results_length = results_length + 1
		end
		ActionController::Base.logger.info "GOT #{results_length} posts "
		q[:log] << "GOT #{results_length} posts "

		#
		# INJECT PEOPLE?
		#
		# for general cases
		# lets go ahead and inject in only the people who were associated with the posts we found (so the user can see them)
		# TODO this could be cleaned up massively using a bit of smarter SQL that finds uniques only or at least a HASH join
		#

		if true
			ActionController::Base.logger.info "Query: injecting people *****************************"
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

		if false
			inject_urls(results)
		end

		#
		# carve precisely against geographic polygonal boundaries if specified
		#

		ActionController::Base.logger.info "Query: injecting multipolygons ***************************"
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
			end
			results = temp_results
		end

		#
		# sort results by distance?
		#

		if sort
			r = results[:results]
			r.each { |note| note.rad = (lat-note.lat)*(lat-note.lat)+(lon-note.lon)*(lon-note.lon) }
			r.sort! { |a,b| a.rad <=> b.rad }
			results[:results] = r
		end

		# return results

		ActionController::Base.logger.info "Query: got final results #{results} #{results_length}"
		q[:results_length] = results_length
		q[:results] = results

		return q
	end

end

