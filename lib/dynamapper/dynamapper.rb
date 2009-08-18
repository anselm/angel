# module Dynamap

require 'lib/dynamapper/gmap.rb'

#
# Dynamapper
#
# A google maps helper for rails
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
  attr_accessor :lat
  attr_accessor :lon
  attr_accessor :width
  attr_accessor :height
  attr_accessor :zoom
  attr_accessor :map_type
  attr_accessor :features
  attr_accessor :map_usercallback

  #
  # initialize()
  # 
  def initialize(args = {})
    @apikey = args[:apikey]
    @map_cover_all_points = true
    @lat = args[:latitude] || 45.516510
    @lon = args[:longitude] || -122.678878
    @width = args[:width] || "100%"
    @height = args[:height] || "440px"
    @zoom = args[:zoom] || 9 
    @map_type = "G_SATELLITE_MAP"
    @features = []
	@map_usercallback = "map_user_initialize"
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

/******************************************************************************************************************************************/
// definitions
/******************************************************************************************************************************************/

var map_location_callback = true;
var use_google_popup = true;
var use_pd_popup = false;
var use_tooltips = false;
var map_div = null;
var map = null;
var map_longitude = 0;
var map_latitude = 0;
var mgr = null;
var map_icons = [];
var map_markers = [];
var map_marker;
var lat = 28.000;
var lon = -90.500;
var zoom = 9;
var map_markers_raw = #{@features.to_json};
var map_features = {}
var map_api_calback = "/json"

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

/******************************************************************************************************************************************/
// helper utilities
/******************************************************************************************************************************************/

/// convenience utility: drag event handler
function mapper_disable_dragging() {
  if( map ) map.disableDragging();
}
/// convenience utility: drag event handler
function mapper_enable_dragging() {
  if( map ) map.enableDragging();
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
/// add a map centering marker - unused
function mapper_center_marker() {	  
  var center = map.getCenter();
  //mapper_set_marker(center);
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
/// add a marker [ must be a separate function for closure ]
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
/// saving the map location to a hidden input form if found [ very convenient for say telling server about location of a search form submission ]
function mapper_save_location(center) {
  if(map == null ) return;
  var center = map.getCenter();
  if(center == null) return;
  var x = document.getElementById("longitude");
  var y = document.getElementById("latitude");
  if(x && y) {
    x.value = center.lat();
    y.value = center.lng();
  }
  map_latitude = center.lat();
  map_longitude = center.lng();
}
/// convenience utility: page refresh may supply map location [ this is the opposite ]
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

/******************************************************************************************************************************************/
// duplicate tracking
/******************************************************************************************************************************************/

// a list tracking all features active on the screen so that we can not re-create ones that already exist
var mapper_features = {};
// do we already have this feature on the screen? caller has to construct and supply a unique key signature identifying this object
function mapper_feature_exists_test_and_mark(key) {
	var feature = mapper_features[key];
	if(feature != null) {
		feature.stale = false;
		return true;
	}
	return false;
}
// visit all features and mark them as stale; this is done prior to adding more data to a view as an efficiency measure
function mapper_mark_all_stale() {
	for(var key in mapper_features) {
		var feature = mapper_features[key];
		if(feature != null) {
			feature.stale = true;
		}
	}
}
// mark this feature as not stale
function mapper_track_and_mark_not_stale(pointer,key) {
	pointer.stale = false;
	mapper_features[key] = pointer;
}
// hide all stale features ; arguably to save memory we could actually remove these features but unsure if javascript conserves memory like so anyway
function mapper_hide_stale() {
	for(var key in mapper_features) {
		var feature = mapper_features[key];
		if(feature != null && feature.stale == true) {
			feature.hide(); // removeOverlay();
		}
	}
}

function mapper_make_key(feature) {
	var key = feature["lat"] + ":" + feature["lon"] + ":" + feature["title"];
	return key;
}


/******************************************************************************************************************************************/
// do actual meat of binding our fairly generic system to google maps - add a feature to google maps
/******************************************************************************************************************************************/

/// javascript: try to get feature up
function mapper_inject_feature(feature) {

  if(feature) {
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
      var key = mapper_make_key(feature);
	  if(mapper_feature_exists_test_and_mark(key)) {
		return;
	  }

      // Slightly randomize the map position of marker so markers do not always overlap
      var randx = Math.random()*0.01 - 0.005;
      var randy = Math.random()*0.01 - 0.005;

      var ll = new GLatLng(feature["lat"] + randy ,feature["lon"] + randx);
      var title = feature["title"];
      var marker = mapper_create_marker(ll,title);
      if(feature["style"] == "show") { GEvent.trigger(marker,"click"); }
	  mapper_track_and_mark_not_stale(marker,key);
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
/// javascript: add a whole pile of new features 
function mapper_inject(features) {
  if(!features || !map) return;
  var j=features.length;
  for(var i=0;i<j;i++) {
    var feature = features[i];
    mapper_inject_feature(feature);
  }
}

/******************************************************************************************************************************************/
// paint markers - this is somewhat application specialized and could be separated away
/******************************************************************************************************************************************/

//
// Paint a display in js
//
var mapper_page_update_already_busy = 0;
function mapper_page_paint(blob) {

	if(mapper_page_update_already_busy) { return true; }
	mapper_page_update_already_busy = 1;

	var dom_status = document.getElementById("status");
	var dom_posts = document.getElementById("posts");
	var dom_people = document.getElementById("parties");

	var search = blob['search'];
	var markers = blob['results'];
	var words = blob['words'];

	// Set iconography
	var feature = {};
	feature["kind"] = "icon";
	feature["image"] = "/dynamapper/icons/weather-clear.png";
	feature["iconSize"] = [ 32, 32 ];
	feature["iconAnchor"] = [ 9, 34 ];
	feature["iconWindowAnchor"] = [ 9, 2 ];
	mapper_inject_feature(feature);

	// mark all objects as stale
	mapper_mark_all_stale();

	// visit all the markers and add them
	for (var i=0; i<markers.length; i++) {

		var item = markers[i]['note'];

		var key = mapper_make_key(item);
		if( mapper_feature_exists_test_and_mark(key) ) {
			continue;
		}

		var id = item['id'];
		var kind = item['kind'];
		var lat = item['lat'];
		var lon = item['lon'];
		var title = item['title'];
		var link = item['link'];
		var description = item['description'];
		var location = item['location'];
		var created_at = item['created_at'];
		var tagstring = item['tagstring'];
		var statebits = item['statebits'];
		var photo_file_name = item['photo_file_name'];
		var photo_content_type = item['photo_content_type'];
		var provenance = item['provenance'];
		var owner_id = item['owner_id'];
		var begins = item['begins'];
		var ends = item['ends'];

		// TODO - i should publish all related parties
		// TODO - i should publish all the depictions
		// TODO - also publish all the relationships

		// Build map feature
		var feature = {};
		feature["kind"] = "marker";
		feature["title"] = title;
		feature["lat"] = lat;
		feature["lon"] = lon;
		mapper_inject_feature(feature);
	}

	// sweep the ones that are not part of this display
	mapper_hide_stale();

	mapper_page_update_already_busy = 0;

}

//
// Ask the server for a fresh set of map markers
//
function mapper_page_paint_request(recenter) {

	var q = document.getElementById("q");
	if(map == null) return;
	var center = map.getCenter();
	var lat = 0;
	var lng = 0;
	if(center != null) {
		lat = center.lat();
		lng = center.lng();
	}

	var url = "/json?q="+q+"&lat="+lat+"&lng="+lng;
	map_div.style.border = "1px solid yellow";

	new Ajax.Request(url, {
		method:'get',
		requestHeaders: {Accept: 'application/json'},
		onSuccess: function(transport) {
			map_div.style.border = "1px solid green";
			var blob = transport.responseText.evalJSON();
			if( blob ) {
				mapper_page_paint(blob);
				if( recenter == true ) {
					mapper_center();
				}
			}
		}
	});

}

/******************************************************************************************************************************************/
// initialization - start up and add any statically defined markers - (we keep markers in javascript as an array to be processed by client)
/******************************************************************************************************************************************/


/// start mapping engine (invoked once only)
function mapper_initialize() {
  if(map_div) return;
  map_div = document.getElementById("map");
  if(!map_div) return;
  if (!GBrowserIsCompatible()) return;
  if(map) return;
  map = new GMap2(document.getElementById("map"));
  // map = new google.maps.Map2(document.getElementById("map"));
  var mapControl = new GMapTypeControl();
  map.addControl(mapControl);
  map.addControl(new GSmallMapControl());
  // setup custom icon support
  mapper_icons();
  // map.removeMapType(G_HYBRID_MAP);
  // capture map location whenever the map is moved and go ahead and ask for a view of that areas markers from our own server
  if(map_location_callback) {
    GEvent.addListener(map, "moveend", function() {
      mapper_save_location();
	  // when the map is moved go ahead and fetch new markers [ but do not center on them ]
	  mapper_page_paint_request(false);
    });
	// also capture map location once at least
	mapper_save_location();
  }
  // add features from a statically cached list if any [ this can help make first page display a bit faster ]
  mapper_inject(map_markers_raw);
  // center on any data we have already if any [ slight tension here with dynamic updates so can be disabled ]
  if(#{@map_cover_all_points}) {
    mapper_center();
  }
  // ask to add features from a remote connection dynamically [ and will center on them ]
  mapper_page_paint_request(true);
  // call a user callback as a last step
  if(self['#{@map_usercallback}'] && typeof #{@map_usercallback} == 'function') {
    #{@map_usercallback}();
  }
}

// google.setOnLoadCallback(mapper_initialize);
// google.load("maps", "2.x");
mapper_initialize();

</script>
ENDING

  end

end

