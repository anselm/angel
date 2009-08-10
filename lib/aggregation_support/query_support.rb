
############################################################################################
#
# Queries
#
# Queries are used to help seed the aggregation engine - which runs asynchronously
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

require 'lib/aggregation_support/twitter_base.rb'
require 'lib/aggregation_support/twitter_collect.rb'
require 'lib/aggregation_support/twitter_aggregate.rb'

class AggregationSupport

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
		return { :words => words, :partynames => partynames, :placenames => placenames }
	end

	#
	# get query location
	#
	def self.query_locate(q)

		# get time
		# TODO implement
		begins = nil
		ends = nil

		# compute get bounds if any
		lat,lon,rad = 0,0,0
		lat,lon,rad = self.geolocate(q[:placenames].join(' ')) if q[:placenames].length
		q[:lat],q[:lon],q[:rad] = lat,lon,rad
		ActionController::Base.logger.info "query: geolocated the query #{q[:placenames].join(' ')} to #{lat} #{lon} #{rad}"

		return q

	end

=begin
	def self.query_with_solr(phrase)
		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			search << "lat:[#{lat-rad} TO #{lat+rad}]"
			search << "lon:[#{lon-rad-rad} TO #{lon+rad+rad}]"
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
		ActionController::Base.logger.info "Query: solr now done"
	end
=end

	def self.query(params)

		phrase = params[:q]
		# pull out lat and lon and stuff too

		q = self.query_parse(phrase)
		self.query_locate(q)
		self.aggregate_memoize(q)

		# now look at our internal database and return best results

		total_hits = 0
		results = []
		search = []
		search << q[:words].join(" ") if q[:words].length > 0
		search_phrase = ""
		search_phrase = search.join(" ") if search.length > 0
		lat,lon,rad = q[:lat],q[:lon],q[:rad]
		rad = 1 # TODO remove this constraint

		ActionController::Base.logger.info "Query: now looking for: #{search_phrase}"

		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			total_hits = Note.count(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-rad,lat+rad,lon-rad,lon+rad ] )
			results = Note.all(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-rad,lat+rad,lon-rad,lon+rad ] )
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
