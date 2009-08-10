require 'lib/content_support/query_support.rb'

class IndexController < ApplicationController

  #
  # handles searches
  # one note is that this code in general is used for a bare bones locative app as well and searches should be a part of that
  # for bare bones use we really just want to show places and maps meeting a criteria - and not do any aggregation
  #
  def index

	# TODO pass in map coordinates.
	# TODO move the aggregation features off to one side and have an ordinary local search capability

	@query = AggregationSupport::query(params)
  end

  # TEST
  def xml
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
