
############################################################################################
#
# Query Construction
#
# Queries are used to help seed the aggregation engine - which runs asynchronously
#
# Returns
#
# 	return { :words => words, :partynames => partynames, :placenames => placenames }
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

require 'lib/aggregation_support/twitter_support.rb'

class AggregationSupport

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

	#
	# parse the query and then talk to a geocoder and to twitter to build an enhanced query
	#
	def self.query_enhanced(phrase)

		ActionController::Base.logger.info "Query: beginning at time #{Time.now}"

		q = self.query_parse(phrase)

		# get time
		# TODO implement
		begins = nil
		ends = nil

		# compute get bounds if any
		lat,lon,rad = 0,0,0
		lat,lon,rad = self.geolocate(q[:placenames].join(' ')) if q[:placenames].length
		q[:lat],q[:lon],q[:rad] = lat,lon,rad
		ActionController::Base.logger.info "query: geolocated the query #{q[:placenames].join(' ')} to #{lat} #{lon} #{rad}"

		# did the user supply some people as the anchor of a search?
		# refresh them and get their friends ( this is cheap and can be done synchronously )
		q[:parties] = self.twitter_get_parties(q[:partynames])
		q[:friends] = self.twitter_get_friends(q[:parties])

		# get the extended first level network of aquaintances ... this is expensive
		# q[:acquaintances] = self.twitter_get_friends(q[:friends])

		return q
	end

=begin
	def self.query_with_solr(phrase)
		q = self.query_enhanced(phrase)
		# go ask solr
		radius = 1 # TODO bad
		total_hits = 0
		results = []
		search = []
		search << q[:words].join(" ") if q[:words].length > 0
		lat,lon,rad = q[:lat],q[:lon],q[:rad]
		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			range = 1
			search << "lat:[#{lat-range} TO #{lat+range}]"
			search << "lon:[#{lon-range-range} TO #{lon+range+range}]"
		end
		search_phrase = search.join(" AND ")
		ActionController::Base.logger.info "Query: solr now looking for: #{search_phrase}"
		if search.length
			results = Note.find_by_solr(search_phrase,
										:offset => 0,
										:limit => 50
										#:order => "id desc",
										#:operator => "and"
										)
			total_hits = 0
			total_hits = results.total_hits if results
			results = results.docs if results
			results = [] if !results
		end
		q[:search_phrase] = search_phrase 
		q[:results] = results
		q[:total_hits] = total_hits
	end
=end

	def self.query(phrase)

		q = self.query_enhanced(phrase)

		radius = 1 # TODO improve
		total_hits = 0
		results = []
		search = []
		search << q[:words].join(" ") if q[:words].length > 0
		search_phrase = ""
		search_phrase = search.join(" ") if search.length > 0
		lat,lon,rad = q[:lat],q[:lon],q[:rad]

		ActionController::Base.logger.info "Query: now looking for: #{search_phrase}"

		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			total_hits = Note.count(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-range,lat+range,lon-range,lon+range ] )
			results = Note.all(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-range,lat+range,lon-range,lon+range ] )
		else
			# TODO combine not eor
			results = Note.find_by_tsearch(search_phrase) if search.length > 0
		end

		q[:search_phrase] = search_phrase 
		q[:total_hits] = total_hits
		q[:results] = results

		return q
	end

end
