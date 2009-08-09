require 'lib/aggregation/query_support.rb'

class IndexController < ApplicationController

  def index

=begin
	- when you submit a query the map coordinates must be injected as well
	- i do not yet actually store any state for the aggregator to use and i should do so
			- a good approach is to just collect users for a week only
			- and to collect keywords over a geography for a week only separately; or maybe we only collect users over time as a rule
	- i would not mind delaying the query results for a moment so that there could be some content
	- i should keep in mind generic uses of this code to just search for local activity
	- make the view hook up to this now
=end

	@query = AggregationSupport::query(params[:q])

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
