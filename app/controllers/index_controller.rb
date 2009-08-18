
require 'lib/dynamapper/geolocate.rb'
require 'lib/twitter_support/twitter_aggregate.rb'

class IndexController < ApplicationController

  #
  # print a view or search results view in desired format
  #
  def index
    @query = self.query(params)
    respond_to do |format|
      format.html # show.html.erb
      format.json  { render :json => @query.to_json }
	  format.xml { render :xml => @query }
    end
  end

  def json
    @query = self.query(params)
	render :json => @query.to_json
  end

  def about
    render :layout => 'static'
  end

  #
  # below is a test for flash globe - merge in above or throw away TODO
  #
  def test
    # we'll return a selection of recent posts that can be used to update the globe 
    @notes = Note.find(:all, :limit => 50, :order => "updated_at DESC", :conditions => { :kind => 'post' } );
    # from those posts I'd like to also return the related users
    @users = []
    @notes.each do |note|
      user = Note.find(:first,:conditions => { :id => note.owner_id, :kind => 'user' } )
      if user
        @users << user
      end
    end
    # from those users I'd like to also add a set of related users so we can map worldwide relationships
	#    @users.each do |user|
	#       party.relation_add(Note::RELATION_FRIEND,1,party2.id)  
	# end
    @notes = Note.find(:all, :limit => 50, :order => "updated_at DESC" );
    render :layout => false
  end


	############################################################################################
	#
	# Query handling in more detail.
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

	# pull out persons, search terms and tags, location such as "@anselm pizza near portland oregon"
	# TODO should publish the query so everybody can see what everybody is searching for
	def query_parse(phrase)
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
	# i want to keep this logic at the controller level for now
	#
	def query_locate(q)

		# get time
		# TODO implement
		begins = nil
		ends = nil

		# compute get bounds if any
		lat,lon,rad = 0,0,0
		lat,lon,rad = Dynamapper.geolocate(q[:placenames].join(' ')) if q[:placenames].length
		rad = 5 # TODO hack remove
		q[:lat],q[:lon],q[:rad] = lat,lon,rad
		ActionController::Base.logger.info "query: geolocated the query #{q[:placenames].join(' ')} to #{lat} #{lon} #{rad}"

		return q

	end

	def query(params)

		phrase = params[:q]
		# pull out lat and lon and stuff too

		q = self.query_parse(phrase)
		self.query_locate(q)

		# optionally we can quickly pull in some third party content to seed our database
		# for now this is just twitter
		TwitterSupport::aggregate_memoize(q)

		# look at our internal database and return best results
		results_length = 0
		results = []
		search,lat,lon,rad = q[:search],q[:lat],q[:lon],q[:rad]

		ActionController::Base.logger.info "Query: now looking for: #{search} at location #{lat} #{lon} #{rad}"

		if ( lat < 0 || lat > 0 || lon < 0 || lon > 0 )
			results_length = Note.count(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-rad,lat+rad,lon-rad,lon+rad ] )
			results = Note.all(:conditions =>  ["lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?", lat-rad,lat+rad,lon-rad,lon+rad ] )
		else
			# TODO combine not eor
			results = Note.find_by_tsearch(search) if search.length > 0
			results_length = 0 # fix TODO
			results.each do
				results_length = results_length + 1
			end
		end

 results_length = 0
 results = []
 Note.all().each do |note|
   results << note
   results_length = results_length + 1
 end

		ActionController::Base.logger.info "Query: got results #{results} #{results_length}"

		q[:results_length] = results_length
		q[:results] = results

		return q
	end


=begin
	# i found solr to be very slow so this is not used now
	def query_with_solr(phrase)
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

end
