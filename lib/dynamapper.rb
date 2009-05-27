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
  # This is the constructor.
  # 
  # The default is to center on longitude and latitude 0,0 .
  #
  def initialize(apikey)
    @apikey = apikey
    @map_cover_all_points = true
    @lat = 45.516510
    @lon = -122.678878
    @width = "100%"
    @height = "340px"
    @zoom = 9 
    @map_type = "G_SATELLITE_MAP"
    # an array of hashes of google maps features 
    @features = []
  end

  #
  # center()
  #
  # Set the map latitude, longitude and zoom coordinates in google map notation.
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
  # figured it would be easier to do these separately
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
  # To use this library one MUST write this block into the layout header.
  # The application MUST declare config/gmaps_api_key.yml .
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
<script type="text/javascript" src="/dynamapper/pdmarker.js"></script>
<script src="/dynamapper/extinfowindow_packed.js" type="text/javascript"></script>
<script src="/dynamapper/tooltip.js" type="text/javascript"></script>
<script>
// the header declares these stubs which may be overriden by body code
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
var zoom = 1;
</script>
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
<div id="pdmarkerwork"></div>
ENDING
  end

  #
  def body_large()
<<ENDING
<div id="map" style="width:100%;height:600px;"></div>
<div id="pdmarkerwork"></div>
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
/// features from page refresh
var map_markers_raw = #{@features.to_json};
/// the code
function mapper_disable_dragging() {
  if( map ) map.disableDragging();
}
function mapper_enable_dragging() {
  if( map ) map.enableDragging();
}
function mapper_start() {
  if(map_div) return;
  map_div = document.getElementById("map");
  if(!map_div) return;
  if (!GBrowserIsCompatible()) return;
  mapper_callback();
  // google.setOnLoadCallback(mapper_callback);
  // google.load("maps", "2.x");
}
function mapper_callback() {

  // start but dont start twice
  if(map) return;

  map = new GMap2(document.getElementById("map"));
  // map = new google.maps.Map2(document.getElementById("map"));
  var mapControl = new GMapTypeControl();
  map.addControl(mapControl);
  map.addControl(new GSmallMapControl());
  // map.removeMapType(G_HYBRID_MAP);

  // add the features - this could be invoked dynamically as well
  mapper_inject(map_markers_raw);

  map.setCenter((new GLatLng(#{@lat},#{@lon})),#{@zoom}, #{@map_type});
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

  // unused
  // mgr = new MarkerManager(map,{ borderPadding: 50, maxZoom: 15, minZoom: 4 ,trackMarkers: true });

  // unused
  // set default position based on bounds of features
  // var center = mapper_get_location(); 
  // map.setCenter(center,zoom);
  // mapper_add_markers();
}
/// javascript: center over predefined set 
function mapper_center() {
  var markers = map_markers;
  if (markers == null || markers.length < 1 ) return;
  var bounds = new GLatLngBounds();
  for (var i=0; i<markers.length; i++) {
    bounds.extend(markers[i].getPoint());
  }
  map.setCenter( bounds.getCenter( ), map.getBoundsZoomLevel( bounds ) - 1 );
}
/// javascript: add new features 
function mapper_inject(features) {
  if(!features || !map) return;
  var j=features.length;
  for(var i=0;i<j;i++) {
    var feature = features[i];
    if(feature.kind == "icon") {
      var icon = new GIcon();
      icon.image = feature["image"];
      icon.iconSize = new GSize(feature["iconSize"][0],feature["iconSize"][1]);
      icon.iconAnchor = new GPoint(feature["iconAnchor"][0],feature["iconAnchor"][1]);
      icon.infoWindowAnchor = new GPoint(feature["infoWindowAnchor"][0],feature["infoWindowAnchor"][1]);
      map_icons.push(icon);
    } 
    else if( feature.kind == "marker" ) {
      var marker =null;
      if(use_google_popup) {

        // ordinary marker
        marker = new GMarker(
                    new GLatLng(feature["lat"],feature["lon"]),
                    { title:feature["title"], icon:map_icons[feature["icon"]-1]}
                  );


        if(use_tooltips) {
          // custom tooltip - unfortunately seems to break in latest google maps
  	  //var content = {el:'dl',ch:[{el:'dt',ch:[{txt: "hellow"}]}]};
  	  var content = "<div style='border:1px solid red;>"+feature['title']+"</div>";
          var tooltip = new Tooltip(marker,jsonToDom(content),5);
          marker.tooltip = tooltip;
          map.addOverlay(tooltip);
          GEvent.addListener(marker,'mouseover',function(){ this.tooltip.show(); });
          GEvent.addListener(marker,'mouseout',function(){ this.tooltip.hide(); });
        } else {
          marker.tooltip = null;
        }

        // ordinary info window; needs to know about tooltip.
        GEvent.addListener(marker, "click", function() {
             // ah = may 19 2009 is this bad?
             //if(marker.tooltip) {
             //  marker.tooltip.hide();
             //}
	     map.closeInfoWindow();
             marker.openInfoWindowHtml(feature["title"]);
           });

        map.addOverlay(marker);
      
     } else if (use_pd_popup) {
        // pdmarker; offering tooltips but has many incompatabilities
        marker = new PdMarker(new GLatLng(feature["lat"],feature["lon"]),
                         { icon:map_icons[feature["icon"]-1]});
        map.addOverlay(marker);
        marker.setTooltip(feature["title"]);
        marker.setDetailWinHTML(feature["title"]);
      } else {
        // extengine; pretty but has a centering bug that has to be fixed TODO
        marker = new PdMarker(new GLatLng(feature["lat"],feature["lon"]),
                         { icon:map_icons[feature["icon"]-1]});
        map.addOverlay(marker);
        marker.setTooltip(feature["title"]);
        //GEvent.addListener(marker, 'click', function() {
        //     marker.openExtInfoWindow(map, "opacity_window", feature["title"], {} );
        //   });
        //if(feature["style"]) marker.openExtInfoWindow(map, "opacity_window", feature["title"], {} );
      }

      // save marker in a list for later
      if(marker) {
        map_markers.push(marker);
      }

      // trigger a pop-up in some cases
      if(marker && feature["style"]) {
        if(feature["style"] == "show") {
          GEvent.trigger(marker,"click");
        }
        if(feature["style"] == "full") {
          var node = document.createElement("div");
          node.innerHTML = feature["full"];
          map_div.appendChild(node);
        }
      }

    } 
    else if( feature.kind == "line") {
      var line = new GPolyline(
                     [ new GLatLng(feature["lat"],feature["lon"]),
                       new GLatLng(feature["lat2"],feature["lon2"] ) ],
                       feature["color"], feature["width"], feature["opacity"]
                   );
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

// add a set of markers from predefined javascript json 
function mapper_add_markers() {

  var baseIcon = new GIcon();
  baseIcon.shadow = "/dynamapper/shadow50.png"
  // baseIcon.shadow = "http://www.google.com/mapfiles/shadow50.png";
  baseIcon.iconSize = new GSize(20, 34);
  baseIcon.shadowSize = new GSize(37, 34);
  baseIcon.iconAnchor = new GPoint(9, 34);
  baseIcon.infoWindowAnchor = new GPoint(9, 2);
  baseIcon.infoShadowAnchor = new GPoint(18, 25);

  for(var i = 0; i < map_markers.length; i++) {
    var info = map_markers[i];
    var point = new google.maps.LatLng(info.lat,info.lon);
    var myicon = new GIcon(baseIcon);
    myicon.image = "/dynamapper/marker" + i + ".png";
    var options = { icon:myicon, draggable:true };
    var marker = new GMarker(point,options);
    map.addOverlay(marker);
    marker.mydescription = map_markers[i].description;
    marker.myhandler = function() {
        this.openInfoWindowHtml(this.mydescription); }
    GEvent.addListener(marker, "click", marker.myhandler );
  }
}

function mapper_set_marker(point) {
  if(map_marker) {
    map.removeOverlay(map_marker);
    map_marker = null;
  }
  if(!map_marker) {
    map_marker = new GMarker(point,{draggable: true});
    map.addOverlay(map_marker);
    GEvent.addListener(map_marker, "dragend", function() {
       map_save_location(map_marker.getPoint());
    });
  }
}

// the document may have an input dialog that has a defined location
//  this is useful for allowing developers to build forms and have the map centered
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

// the document may want to store permanently where a user has dragged the map to  
function mapper_save_location(point) {
  var x = document.getElementById("note[longitude]");
  var y = document.getElementById("note[latitude]");
  if(x && y ) {
    x.value = point.x;
    y.value = point.y;
  }
}

mapper_start();
</script>
ENDING
  end

end


# end

