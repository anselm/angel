
require 'lib/query_support.rb'
require 'json/pure'

class IndexController < ApplicationController
	
  #
  # The client side is javascript so just deliver code to the client first
  # and javascript will take over
  #
  def index
  end

  #
  # Our first pass at an API - handle place, person and subject queries
  # and return json
  #
  def json
    question = params[:q]
    synchronous = false
    synchronous = true if params[:synchronous] && params[:synchronous] ==true
    results = QuerySupport::query(question,synchronous)
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
