class AdminNotesController < ApplicationController
  before_filter :require_admin
  layout "admin"
  active_scaffold :note do |config|
    config.label = '<a href="/admin_users">Users</a> Notes <a href="/admin_relations">Relations</a>'
    config.columns = [:title, :kind, :link, :description, :lon, :lat, :rad, :tagstring ]
    #config.ignore_columns.add [ :created_at, :updated_at ]
    list.sorting = {:updated_at => 'ASC'}
    columns[:title].label = "Title"
  end
end

