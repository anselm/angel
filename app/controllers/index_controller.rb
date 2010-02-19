
require 'net/http'
require 'uri'
require 'open-uri'
require 'lib/query_support.rb'
require 'json/pure'
#require 'json/add/rails'
require 'note.rb'
require 'world_boundaries.rb'

  #
  # This app is largely client side driven... so server mostly exposes an API
  #
  # api goals
  #
  # 1) allow subscribers to indicate a series of sources to follow
  # 2) allow subscribers to fetch back posts of parties they are watching
  # 3) allow subscribers to issue general queries such as person, place and terms
  # 4) allow subscribers to upscore or downscore any entity
  # 5) allow subscribers to indicate a matchmaking opportunity
  # 6) allow subscribers to attach a note to a subject
  # 7) allow subscribers to make new subjects
  # 8) identify subscribers by a name and password
  # 9) allow subscribers to tag an entity to allow entity grouping
  # 10) allow subscribers to request an update on an entire set such as a tagged set
  #
  #

class IndexController < ApplicationController

  #
  # IPHONE VIEW
  # a compact view suitable for sending state to the iphone
  #

  def compress
	results = QuerySupport::query(params,session)
  end

  #
  # JSON VIEW
  #

  def json
	results = QuerySupport::query(params,session)
    render :json => results.to_json
  end

  #
  # RSS VIEW
  #
  # fetch rss results on a specified country of posts only
  #
  def rss
    @posts = []
	results = QuerySupport::query(params)
	results[:results].each do |result|
      @posts << result if result.kind == Note::KIND_POST
	end
    headers["Content-Type"] = "application/xml; charset=utf-8"
    render :layout => false
  end

  #
  # SPINNYGLOBE VIEW
  #
  # TEST  - test for flash globe - merge in above or throw away TODO
  #
  def spinnyglobe
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

  #
  # HTML VIEW
  #
  # The client side is javascript so this does very litle - it just kicks off the json callback
  # We do look at some persistent state information for where the map is centered... but thats about it.
  # The rest is done by a json callback
  # TODO it would be nicer if the javascript was constant, not dynamic.
  #
  def index

    # for the map - pass any query string down to the json layer so it can do dynamic query
    @map.question = nil
    @map.question = session[:q] = params[:q] if params[:q]
    @map.question = session[:q] if !params[:q]

    # for the map - pass any location string down to the json layer as well
    @map.south = @map.west = @map.north = @map.east = 0.0
    begin
	# attempt to fetch map location from parameters
	@map.south    = session[:s] = params[:s].to_f if params[:s]
	@map.west     = session[:w] = params[:w].to_f if params[:w]
	@map.north    = session[:n] = params[:n].to_f if params[:n]
	@map.east     = session[:e] = params[:e].to_f if params[:e]
	# otherwise fetch them from session state if present (or set to nil)
	@map.south    = session[:s].to_f if !params[:s]
	@map.west     = session[:w].to_f if !params[:w]
	@map.north    = session[:n].to_f if !params[:n]
	@map.east     = session[:e].to_f if !params[:e]
    rescue
    end

    # for the map - try tp pass any explicit country request down to the json layer
    @country = nil
    @country = params[:country] if params[:country] && params[:country].length > 1
    @map.countrycode = @country

  end

  def about
    render :layout => 'static'
  end

end
