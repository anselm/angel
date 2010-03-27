# module Dynamap

require 'lib/dynamapper/gmap.rb'

#
# Dynamapper
#
# A google maps helper for rails
# TODO I want associated javascript to be static not dynamic; means peeking at passed parameters instead
#
# This was written for call2action but was never used - it is public domain - anselm hook
# 
# To use this class the developer MUST follow a pattern like this:
# 
#   In control logic such as application.rb:
#
#     map = Dynamapper.new
#     map.feature( { :kind => :marker, :lat => 0, :lon => 0 } )
#
#   In layout templates such as layout.rhtml:
#   
#      <html>
#       <head>
#        <%= map.header() %>
#       </head>
#       <body>
#        <%= map.body() %>
#       </body>
#       <%= map.tail() %>
#      </html>
#
#   

class Dynamapper

  attr_accessor :apikey
  attr_accessor :map_cover_all_points
  attr_accessor :question
  attr_accessor :south
  attr_accessor :west
  attr_accessor :north
  attr_accessor :east
  attr_accessor :width
  attr_accessor :height
  attr_accessor :zoom
  attr_accessor :map_type
  attr_accessor :features
  attr_accessor :countrycode

  #
  # initialize()
  # TODO many of these parameters are not yet percolated through to client side
  # 
  def initialize(args = {})
    @south = @west = @east = @north = 0.0
    @apikey = args[:apikey]
    @map_cover_all_points = true
    @lat = args[:latitude] || 45.516510
    @lon = args[:longitude] || -122.678878
    @width = args[:width] || "100%"
    @height = args[:height] || "440px"
    @zoom = args[:zoom] || 9 
    @map_type = "G_SATELLITE_MAP"
    @features = []
    @countrycode = ""
  end

  #
  # center()
  #
  def center(lat,lon,zoom)
    @lat = lat
    @lon = lon
    @zoom = zoom
  end

  #
  # feature()
  #
  # Add a static "feature" to the map before it is rendered.
  # 
  # The map is intended to support dynamic polling of the server, but
  # it is always convenient to pre-load the map with content prior to render.
  # In implementation these features are turned into a json blob that acts
  # as if it was something fetched by an ajax callback; even though it is
  # preloaded in this case.
  # 
  # The philosophy here is to keep the ruby lightweight; so error handling
  # if any is in the javascript - the ruby side just forwards the hash to
  # the javascript side.
  # 
  # The features supported ARE the google maps features - identically.
  # For documentation on what google maps supports - read the google maps api.
  # This API is a pure facade that just passes parameters through to google maps
  # - this API doesn't even know or care what those properties are.
  # 
  # There are these kinds of objects that we pass through:
  # 
  #    icons - which are google maps compliant png artwork
  #    markers - which are google maps makers
  #    lines - which are google maps line segments
  #    linez - compressed lines which are built here
  # 
  # Here is a brief overview of the kinds of properties we pass to google maps:
  # 
  #   :kind => icon
  #      :image => an image name string
  #      :iconSize => an integer
  #      :iconAnchor => an integer
  #      :infoWindowAnchor => an array with two floats such as { 42.1, -112.512 }
  # 
  #  :kind => marker
  #      :lat => latitude
  #      :lon => longitude
  #      :icon => a named citation to a piece of artwork defined as an icon
  #      :title => a text string
  #      :infoWindow => a snippet of html
  #      
  #  :kind => line ...
  #      :lat
  #      :lon
  #      :lat2
  #      :lon2
  #      :color
  #      :width
  #      :opacity
  #
  #  :kind => linez ... { see example }
  #  
  #  All properties are mandatory right now.
  #  
  #  The feature is returned but an id field is set to allow things to link together
  #  For example the icons link to the marker so that markers can have pretty icons
  #
  def feature(args)
    @features << args
    return @features.length
  end

  #
  # feature_line() with encoding of an array of line segment pairs
  #
  def feature_line(somedata)
    encoder = GMapPolylineEncoder.new()
    result = encoder.encode( somedata )
    somehash = {
           :kind => :linez,
           :color => "red", # "#FF0000",
           :weight => 10,
           :opacity => 1,
           :zoomFactor => result[:zoomFactor],
           :numLevels => "#{result[:numLevels]}",
           :points => "#{result[:points]}",
           :levels => "#{result[:levels]}"
           }
    @features << somehash
    return @features.length
  end

  #
  # header()
  #
  def header()
<<ENDING
<style type="text/css">
   div.markerTooltip, div.markerDetail {
      color: black;
      font-weight: bold;
      background-color: white;
      white-space: nowrap;
      margin: 0;
      padding: 2px 4px;
      border: 1px solid black;
   }
</style>
<script src="http://maps.google.com/maps?file=api&amp;v=2&amp;key=#{@apikey}" type="text/javascript"></script>
<script src="/javascripts/dynamapper.js" type="text/javascript"></script>
ENDING
  end

  # body()
  #
  # Developers MUST invoke this body method in the body of their site layout.
  # OR put it in by hand if they want style control
  # Currently the map DIV name is hardcoded and this is a defect. TODO improve
  #
  def body(force_width=0,force_height=0)
    # we have to track width and height for a variety of annoying reasons; so must be set here
    @width = force_width if force_width > 0
    @height = force_height if force_height > 0
<<ENDING
<div id="map" style="width:#{@width};height:#{@height};"></div>
ENDING
  end

  # tail()
  #
  # Developers MUST invoke this tail method at the end of their site layout.
  # This does all the work.
  #
  def tail()
<<ENDING
<script defer>
  var map_markers_raw = #{@features.to_json};
  mapper_initialize(map_markers_raw,"#{countrycode}",#{@south},#{@west},#{@north},#{@east},#{map_cover_all_points});
</script>
ENDING
  end
end

