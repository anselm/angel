require 'net/http'
require 'uri'
require 'open-uri'
require 'lib/query_support.rb'
require 'note.rb'

#require 'json/pure'
#require 'json/add/rails'

class IndexController < ApplicationController

  def expand_url(url)
    begin
      timeout(60) do
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host)
		http.open_timeout = 30
		http.read_timeout = 60
		if uri.host == "ping.fm" || uri.host == "www.ping.fm"
			logger.info "ping.fm requires us to fetch the body"
			response = http.get(uri.path)
			return nil
		else
			response = http.head(uri.path) # get2(uri.path,{ 'Range' => 'bytes=0-1' })
			if response.class == Net::HTTPRedirection || response.class == Net::HTTPMovedPermanently
				logger.info "expand_url #{response} looking at relationship #{r.value} to become #{response['location']}"
				return response['location']
			end
		end
	  end
    rescue => exception
      logger.info "expand_url inner rescue error #{exception} while fetching #{url}"
      return nil
    end
	return nil
  end

  def fix_relations
    # fix the broken links
    Relation.find(:all, :conditions => { :kind => Note::RELATION_URL } ).each do |r|
      ActionController::Base.logger.info "looking at relationship #{r.value}"
	  fixed = expand_url(r.value)
	  if fixed
	    r.value = fixed
		r.save
	  end
	end
  end

  #
  # The client side is javascript so this does very litle
  #
  def index

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

    # pull user question and location of question; ignore session state
	@q = nil
    @q = session[:q] = params[:q].to_s if params[:q]
	@s = @w = @n = @e = 0.0
	begin
		@s = session[:s] = params[:s].to_f if params[:s]
		@w = session[:w] = params[:w].to_f if params[:w]
		@n = session[:n] = params[:n].to_f if params[:n]
		@e = session[:e] = params[:e].to_f if params[:e]
	rescue
	end

    # pull user search term if supplied
    synchronous = false
    synchronous = true if params[:synchronous] && params[:synchronous] ==true
    results = QuerySupport::query(@q,@s,@w,@n,@e,synchronous)
    render :json => results.to_json
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

end
