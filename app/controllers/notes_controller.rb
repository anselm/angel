require 'lib/twitter_support.rb'

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

  # GET /notes
  # GET /notes.xml
  def index

    @notes = Note.find(:all, :order => 'begins DESC', :limit => 50 )
    @notes.each do |item|
        @map.feature( {
          :title => "#{item.title} #{item.description}",
          :kind => :marker,
          :lat => "#{item.lat+rand(10)/100}",
          :lon => "#{item.lon+rand(10)/100}"
        }
     )
    end

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @notes }
    end
  end

  # GET /notes/1
  # GET /notes/1.xml
  def show
    @note = Note.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @note }
    end
  end

  # GET /notes/new
  # GET /notes/new.xml
  def new
    @note = Note.new
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @note }
    end
  end

  # GET /notes/1/edit
  def edit
    @note = Note.find(params[:id])
  end

  # POST /notes
  # POST /notes.xml
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

  # PUT /notes/1
  # PUT /notes/1.xml
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

  # DELETE /notes/1
  # DELETE /notes/1.xml
  def destroy
    @note = Note.find(params[:id])
    @note.destroy
    respond_to do |format|
      format.html { redirect_to(notes_url) }
      format.xml  { head :ok }
    end
  end

  # Search
  def search
     @term = params[:id]
     @notes = nil
     # @notes = Note.find_by_solr(@term)
     # @notes = @notes.docs if @notes
	 @notes = Note.search(@term)
     @notes = [] if !@notes
  end

  # Update
  def update

	@results = TwitterSupport.consume

    # get some posts from twitter
    # store them in our database if new
    # parts of speech tagging
    # geolocation
  end

end
