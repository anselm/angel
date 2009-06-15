# require 'lib/twitter_support.rb'

class NotesController < ApplicationController

  before_filter :get_note_from_param
#  before_filter :verify_member, :only => [ :new, :edit, :update, :destroy ]
#  before_filter :verify_owner, :only => [ :edit, :update, :destroy ]

  def get_note_from_param
    @note = nil
    @note = Note.find(:first,:id => params[:id]) if params[:id]
    return @note != nil
  end
   
  def verify_owner
    return false if !@note || !@current_user || @note.owner_id != current_user.id
    return true 
  end

  def update
    @results = TwitterSupport.consume
  end

  def index
    @query = TwitterSupport::query(params[:q])
#    respond_to do |format|
#      format.html # index.html.erb
#      format.xml  { render :xml => @query }
#    end
  end

  def xml
    # dump a selection of recent activity for purposes of a demo at the banff centre june 12 2009
    # in combination with a background crontab this is basically just accumulating more data and piping it onwards

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
    @users.each do |user|

 #                               party.relation_add(Note::RELATION_FRIEND,1,party2.id)  
      # 
    end

    @notes = Note.find(:all, :limit => 50, :order => "updated_at DESC" );
    render :layout => false
  end

  def show
    @note = Note.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @note }
    end
  end

  def new
    @note = Note.new
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @note }
    end
  end

  def edit
    @note = Note.find(params[:id])
  end

  def create
    @note = Note.new(params[:note])
    respond_to do |format|
      if @note.save
        flash[:notice] = 'Note was successfully created.'
        format.html { redirect_to(@note) }
        format.xml  { render :xml => @note, :status => :created, :location => @note }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @note.errors, :status => :unprocessable_entity }
      end
    end
  end

  def update
    @note = Note.find(params[:id])
    respond_to do |format|
      if @note.update_attributes(params[:note])
        flash[:notice] = 'Note was successfully updated.'
        format.html { redirect_to(@note) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @note.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @note = Note.find(params[:id])
    @note.destroy
    respond_to do |format|
      format.html { redirect_to(notes_url) }
      format.xml  { head :ok }
    end
  end

end
