require 'net/http'
require 'uri'
require 'open-uri'
require 'lib/query_support.rb'
# require 'json/pure'
#require 'json/add/rails'
require 'note.rb'
require 'world_boundaries.rb'

class IndexController < ApplicationController

  #
  # generate rss - with country boundary respect if supplied
  #
  def rss
    @posts = []
    @country = nil
    @country = params[:country] if params[:country] && params[:country].length > 1
    if @country
      @multipolygon = WorldBoundaries.polygon_country(@country)
      if @multipolygon
        @w,@e,@s,@n = WorldBoundaries.polygon_extent(@multipolygon)
        synchronous = false
        results = QuerySupport::query(@q,@s,@w,@n,@e,synchronous)
        results[:results].each do |result|
          next if result.kind != Note::KIND_POST
          if WorldBoundaries.polygon_inside?(@multipolygon,result.lon,result.lat)
            @posts << result
          end
        end
      end
    end
    headers["Content-Type"] = "application/xml; charset=utf-8"
    render :layout => false
  end

  #
  # The client side is javascript so this does very litle
  #
  def index

    @country = nil
    @country = params[:country] if params[:country] && params[:country].length > 1
    if @country
      @multipolygon = WorldBoundaries.polygon_country(@country)
      if @multipolygon
        params[:w],params[:e],params[:s],params[:n] = WorldBoundaries.polygon_extent(@multipolygon)
      end
      @map.countrycode = @country
    end

    # strive to supply session state of previous question if any to the map for json refresh
    @map.question = nil
    @map.question = session[:q] = params[:q] if params[:q]
    @map.question = session[:q] if !params[:q]
    # strive to supply a hint to the map regarding where to center 
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
  end

  #
  # Our first pass at an API - handle place, person and subject queries
  #
  def json

    # preferentially pull user question and location of question; ignore session state
    @q = nil
    @q = session[:q] = params[:q].to_s if params[:q]

    # always grab the explicit bounds if any - can be overloaded 
    @s = @w = @n = @e = 0.0
    begin
      @s = session[:s] = params[:s].to_f if params[:s]
      @w = session[:w] = params[:w].to_f if params[:w]
      @n = session[:n] = params[:n].to_f if params[:n]
      @e = session[:e] = params[:e].to_f if params[:e]
    rescue
    end

    # allow explicit country code to set boundaries - overrides supplied bounds
    @country = nil
    @country = params[:country] if params[:country] && params[:country].length > 1
    if @country
      @multipolygon = WorldBoundaries.polygon_country(@country)
      if @multipolygon
        @w,@e,@s,@n = WorldBoundaries.polygon_extent(@multipolygon)
      end
    end

    # pull user search term if supplied
    synchronous = false
    synchronous = true if params[:synchronous] && params[:synchronous] ==true
    results = QuerySupport::query(@q,@s,@w,@n,@e,synchronous)

    # finalize the culling
    if @multipolygon
      temp_results = []
      results[:results].each do |result|
        if WorldBoundaries.polygon_inside?(@multipolygon,result.lon,result.lat)
          temp_results << result
        end
      end
      results[:results] = temp_results
    end

    render :json => results.to_json
  end

  def about
    render :layout => 'static'
  end

  #
  # below is a test for flash globe - merge in above or throw away TODO
  #
  def test2
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

end
