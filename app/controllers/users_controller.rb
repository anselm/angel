class UsersController < ApplicationController

  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:edit, :update, :delete]
  before_filter :get_focus_user, :only => [:show, :edit, :update, :delete ]

  def get_focus_user
    @user = User.first(:conditions => [ "login = ?", params[:id] ] )
    @user = User.first(:conditions => [ "id = ?", params[:id] ] ) if !@user
  end
  
  def new
    @user = User.new
  end
  
  def show
    @page = params[:page] || 0
    @count = params[:count] || 100
  end

  def edit
  end
  
  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Account registered!"
      redirect_back_or_default "/users/#{@user.login}"
    else
      render :action => :new
    end
  end
  
  def update
    if @user.update_attributes(params[:user])
      flash[:notice] = "Account updated!"
      redirect_to "/users/#{@user.login}"
    else
      render :action => :edit
    end
  end

  def index
    # TODO PAGINATION
    # TODO KEEP AS AN ADMINISTRATIVE ROLE
    @users = User.all
  end

  def delete
    # current_user_session.destroy
    @user.destroy
    flash[:notice] = "Account deleted!"
    respond_to do |format|
      format.html { redirect_back_or_default new_user_session_url }
      format.xml  { head :ok }
    end
  end

end
