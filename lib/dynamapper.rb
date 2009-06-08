# module Dynamap

require 'lib/gmap.rb'

#
# Dynamapper
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

  #
  # initialize()
  # 
  def initialize(args = {})
    @apikey = args[:apikey]
    @map_cover_all_points = true
    @lat = args[:latitude] || 45.516510
    @lon = args[:longitude] || -122.678878
    @width = args[:width] || "100%"
    @height = args[:height] || "340px"
    @zoom = args[:zoom] || 9 
    @map_type = "G_SATELLITE_MAP"
    @features = []
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
ENDING
  end

  # body()
  #
  # Developers MUST invoke this body method in the body of their site layout.
  # Currently the map DIV name is hardcoded and this is a defect. TODO improve
  #
  def body()
<<ENDING
<div id="map" style="width:#{@width};height:#{@height};"></div>
ENDING
  end

  #
  def body_large()
<<ENDING
<div id="map" style="width:100%;height:600px;"></div>
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
var map_marker_chase = false;
var use_google_popup = true;
var use_pd_popup = false;
var use_tooltips = false;
var map_div = null;
var map = null;
var mgr = null;
var map_icons = [];
var map_markers = [];
var map_marker;
var lat = 28.000;
var lon = -90.500;
var zoom = 9;
var map_markers_raw = #{@features.to_json};

var icons = [ "weather-storm.png",
"weather-snow.png",
"weather-overcast.png",
"weather-showers-scattered.png",
"weather-clear.png",
"weather-few-clouds.png",
"weather-clear-night.png",
"start-here.png",
"media-skip-forward.png",
"media-record.png",
"face-wink.png",
"image-loading.png",
"face-surprise.png",
"face-smile.png",
"face-smile-big.png",
"face-sad.png",
"face-plain.png",
"face-monkey.png",
"face-kiss.png",
"face-devil-grin.png",
"face-angel.png",
"face-crying.png",
"emblem-photos.png",
"emblem-important.png",
"emblem-favorite.png",
];
var base_icon;
var icon_index = 0;

/// convenience utility: drag event handler
function mapper_disable_dragging() {
  if( map ) map.disableDragging();
}
/// convenience utility: drag event handler
function mapper_enable_dragging() {
  if( map ) map.enableDragging();
}
/// start mapping engine
function mapper_start() {
  if(map_div) return;
  map_div = document.getElementById("map");
  if(!map_div) return;
  if (!GBrowserIsCompatible()) return;
  mapper_callback();
  // google.setOnLoadCallback(mapper_callback);
  // google.load("maps", "2.x");
}
/// mapper icon support
function mapper_icons() {
	base_icon = new GIcon(G_DEFAULT_ICON);
	base_icon.shadow = "http://www.google.com/mapfiles/shadow50.png";
	base_icon.iconSize = new GSize(20, 34);
	base_icon.shadowSize = new GSize(37, 34);
	base_icon.iconAnchor = new GPoint(9, 34);
	//base_icon.infoWindowAnchor = new GPoint(9, 2);
}
/// mapping engine setup
function mapper_callback() {
  // start but dont start twice
  if(map) return;
  map = new GMap2(document.getElementById("map"));
  // map = new google.maps.Map2(document.getElementById("map"));
  var mapControl = new GMapTypeControl();
  map.addControl(mapControl);
  map.addControl(new GSmallMapControl());
  // setup custom icon support
  mapper_icons();
  // map.removeMapType(G_HYBRID_MAP);
  // set centering even if overriden otherwise google maps fails sometimes
  map.setCenter((new GLatLng(#{@lat},#{@lon})),#{@zoom}, #{@map_type});
  // add features dynamically
  mapper_inject(map_markers_raw);
  // set centering on markers if preferred
  if(#{@map_cover_all_points}) {
     mapper_center();
  }
  // an optional centering beacon
  if(map_marker_chase) {
    GEvent.addListener(map, "moveend", function() {
      var center = map.getCenter();
      mapper_save_location(center);
      mapper_set_marker(center);
    });
  }
}
/// javascript: center over predefined set 
function mapper_center() {
  var markers = map_markers;
  if (markers == null || markers.length < 1 ) return;
  var bounds = new GLatLngBounds();
  for (var i=0; i<markers.length; i++) {
    bounds.extend(markers[i].getPoint());
  }
  var thezoom = map.getBoundsZoomLevel(bounds);
  if(thezoom > 15 ) thezoom = 15;
  map.setCenter( bounds.getCenter( ), thezoom );
}
/// must be a separate function for closure : add a marker
function mapper_create_marker(point,title) {
  var number = map_markers.length
  var marker_options = { title:title }
  if ( map_icons.length > 0 ) {
	marker_options["icon"] = map_icons[map_icons.length-1];
  }
  var marker = new GMarker(point, marker_options );
  map_markers.push(marker)
  marker.value = number;
  GEvent.addListener(marker, "click", function() {
     // marker.openInfoWindowHtml(title);
     map.openInfoWindowHtml(point,title);
  });
  map.addOverlay(marker);
  return marker;
}
/// javascript: add new features 
function mapper_inject(features) {
  if(!features || !map) return;
  var j=features.length;
  for(var i=0;i<j;i++) {
    var feature = features[i];
	/*
	if(feature.kind == "icon_numbered") {
		var icon = new GIcon(base_icon);
		var letter = String.fromCharCode("A".charCodeAt(0) + icon_index);
		icon.image = "http://www.google.com/mapfiles/marker" + letter + ".png";
		map_icons.push(icon);
	  } else
	*/
    if(feature.kind == "icon") {
      var icon = new GIcon();
      icon.image = feature["image"];
      icon.iconSize = new GSize(feature["iconSize"][0],feature["iconSize"][1]);
      icon.iconAnchor = new GPoint(feature["iconAnchor"][0],feature["iconAnchor"][1]);
      //icon.infoWindowAnchor = new GPoint(feature["infoWindowAnchor"][0],feature["infoWindowAnchor"][1]);
      map_icons.push(icon);
    }
    else if( feature.kind == "marker" ) {
      var ll = new GLatLng(feature["lat"],feature["lon"]);
      var title = feature["title"];
      var marker = mapper_create_marker(ll,title);
      if(feature["style"] == "show") { GEvent.trigger(marker,"click"); }
    }
    else if( feature.kind == "line") {
      var p1 = new GLatLng(feature["lat"],feature["lon"]);
      var p2 = new GLatLng(feature["lat2"],feature["lon2"]);
      var line = new GPolyline([p1,p2], feature["color"], feature["width"], feature["opacity"] );
      map.addOverlay(line);
    }
    else if( feature.kind == "linez" ) {
      var line = new GPolyline.fromEncoded({
                          color: "#FF0000",
                          weight: 10,
                          opacity: 0.5,
                          zoomFactor: feature["zoomFactor"],
                          numLevels: feature["numLevels"],
                          points: feature["points"],
                          levels: feature["levels"]
                         });
       map.addOverlay(line);
    }
  }
}
/// convenience utility: look for an input dialog which may help determine current map focus or other map state
function mapper_get_location() {
  var x = document.getElementById("note[longitude]");
  var y = document.getElementById("note[latitude]");
  if(x && y ) {
    x = parseFloat(x.value);
    y = parseFloat(y.value);
  }
  if(x && y && ( x >= -180 && x <= 180 ) && (y >= -90 && y <= 90) ) {
    return new google.maps.LatLng(y,x);
  }
  return new google.maps.LatLng(lat,lon);
}
mapper_start();
</script>
ENDING

  end

end


