require 'lib/twitter_support.rb'

class NotesController < ApplicationController

  before_filter :get_note_from_param, :only => [ :show, :edit, :update, :destroy ]

# TODO
#  before_filter :verify_member, :only => [ :new, :edit, :update, :destroy ]
#  before_filter :verify_owner, :only => [ :edit, :update, :destroy ]

  def get_note_from_param
    @note = nil
    @note = Note.find_by_id(params[:id].to_i) if params[:id]
    return @note != nil
  end
   
  def verify_owner
    return false if !@note || !@current_user || @note.owner_id != current_user.id
    return true 
  end

  #
  # I'd like the index page to do very little; just show recent posts over the area
  # The user can use search criteria to refine their post
  #
  def index
    @query = {}
	if params[:q]
		@query[:results] = Note.find_by_tsearch(params[:q])
	else
		@query[:results] = Note.find(:all,:limit => 100, :offset=> 0, :order => "id desc" )
	end
    @query[:parties] = []
    @query[:friends] = []
  end

  def search
    @query = TwitterSupport::query(params[:q])
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @query }
    end
  end

  def show
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @note }
    end
  end

  def edit
  end

  def new
    @note = Note.new
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @note }
    end
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
    @note.destroy
    respond_to do |format|
      format.html { redirect_to(notes_url) }
      format.xml  { head :ok }
    end
  end

end
