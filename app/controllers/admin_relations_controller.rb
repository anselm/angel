require 'note.rb'

class AdminRelationsController < ApplicationController
  before_filter :require_admin
  layout "admin"
  active_scaffold :relation do |config|
    config.label = '<a href="/admin_users">Users</a> <a href="/admin_notes">Notes</a> Relations'
  end
end

