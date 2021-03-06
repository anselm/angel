var map_countrycode = "";
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
var map_icon_names = {};
var map_markers = [];
var map_marker;
var lat = 28.000;
var lon = -90.500;
var zoom = 9;
var map_features = {}
var map_api_calback = "/json"

var icons = [
 "weather-storm.png",
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
var mapper_page_update_already_busy = 0;


/******************************************************************************************************************************************/
// helper utilities
/******************************************************************************************************************************************/

function mapper_make_links_clickable(twitter,username) {
    var status;

    /* buggy
    // http://deanjrobinson.com/wp-content/uploads/2009/07/blogger-mod.js.txt
    // status = twitter.replace(/((https?|s?ftp|ssh)\:\/\/[^"\s\<\>]*[^.,;'">\:\s\<\>\)\]\!])/g, function(url) {
    // status = twitter.replace(/http[s]?:\/\[a-zA-Z0-9_]/g, function(url) {
    // status = twitter.replace(/https?:\/\/([-\w\.]+)+(:\d+)?(\/([\w/_\.]*(\?\S+)?)?)?/g, function(url) {
    //  return '<a href="'+url+'">'+url+'</a>';
    // })
    status = twitter.replace(/\B@([_a-z0-9]+)/ig, function(reply) {
      return reply.charAt(0)+'<a href="http://twitter.com/'+reply.substring(1)+'">'+reply.substring(1)+'</a>';
    }).replace(/\B#([_a-z0-9]+)/ig, function(hashtag) {
      return '<a href="http://search.twitter.com/search?q=%23'+hashtag.substring(1)+'">'+hashtag+'</a>';
    });
    */

    var results = twitter.split(" ");
    for(var i = 0; i < results.length; i++ ) {
      var xxx = results[i];
      if(xxx.startsWith("http://")) {
        results[i] = "<a href='"+xxx+"'>"+xxx+"</a>";
      }
      else if(xxx.startsWith("@")) {
        results[i] = "<a href='http://twitter.com/"+xxx.substring(1)+"'>"+xxx+"</a>";
      }
      else if(xxx.startsWith("#")) {
        results[i] = "<a href='http://search.twitter.com/search?q=%23"+xxx.substring(1)+"'>"+xxx+"</a>";
      }
    }
    status = results.join(" ");

    return '<div style="position:relative;background:#aaaaff;width:95%;border:1px solid #ddddff;">'
            + '<div style="position:absolute;right:-20px;top:0px;width:20px;height:20px;background:#aaaaff;"></div>'
            + '<a href="http://twitter.com/'+username+'">'+username+'</a> '
            + status 
            + "</div>"
            ;

}

function relative_time(time_value) {
  var values = time_value.split(" ");
  time_value = values[1] + " " + values[2] + ", " + values[5] + " " + values[3];
  var parsed_date = Date.parse(time_value);
  var relative_to = (arguments.length > 1) ? arguments[1] : new Date();
  var delta = parseInt((relative_to.getTime() - parsed_date) / 1000);
  delta = delta + (relative_to.getTimezoneOffset() * 60);

  if (delta < 60) {
    return 'less than a minute ago';
  } else if(delta < 120) {
    return 'about a minute ago';
  } else if(delta < (60*60)) {
    return (parseInt(delta / 60)).toString() + ' minutes ago';
  } else if(delta < (120*60)) {
    return 'about an hour ago';
  } else if(delta < (24*60*60)) {
    return 'about ' + (parseInt(delta / 3600)).toString() + ' hours ago';
  } else if(delta < (48*60*60)) {
    return '1 day ago';
  } else {
    return (parseInt(delta / 86400)).toString() + ' days ago';
  }
}

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
function mapper_create_marker(point,title,glyph) {
  var number = map_markers.length
  var marker_options = { title:title }
  if ( glyph != null ) {
	marker_options["icon"] = glyph;
  }
  else if ( map_icons.length > 0 ) {
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
/// saving the map location to a hidden input form if found
/// [ very convenient for say telling server about location of a search form submission ]
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
  var x = document.getElementById("note[lon]");
  var y = document.getElementById("note[lat]");
  if(x && y) {
    x.value = center.lat();
    y.value = center.lng();
  }
  var x = document.getElementById("note_lon");
  var y = document.getElementById("note_lat");
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

var mapper_features = {};

/// a list tracking all features active on the screen so that we can not re-create ones that already exist
/// do we have this feature on the screen? caller has to construct and supply a unique key signature identifying this object
function mapper_feature_exists_test_and_mark(key) {
	var feature = mapper_features[key];
	if(feature != null) {
		feature.stale = false;
		return true;
	}
	return false;
}
/// visit all features and mark them as stale; this is done prior to adding more data to a view as an efficiency measure
function mapper_mark_all_stale() {
	for(var key in mapper_features) {
		var feature = mapper_features[key];
		if(feature != null) {
			feature.stale = true;
		}
	}
}
/// mark this feature as not stale
function mapper_track_and_mark_not_stale(pointer,key) {
	pointer.stale = false;
	mapper_features[key] = pointer;
}
/// hide all stale features 
/// arguably to save memory we could actually remove these features but unsure if javascript conserves memory like so anyway
function mapper_hide_stale() {
	for(var key in mapper_features) {
		var feature = mapper_features[key];
		if(feature != null && feature.stale == true) {
			feature.hide(); // removeOverlay();
		} else if( feature != null ) {
			feature.show();
		}
	}
}
/// build a key to more or less uniquely identify a feature
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
      map_icon_names[icon.image] = icon;
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
      var glyph = feature["glyph"];
      if(glyph != null) {
        glyph = map_icon_names[glyph];
      }
      var marker = mapper_create_marker(ll,title,glyph);
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

var glyph_post = null;
var glyph_person = null;
var glyph_url = null;

//
// Define some common features
//
function mapper_page_paint_icons() {

        if( glyph_url != null ) return;

        if(true) { 
        glyph_post = "/dynamapper/icons/weather-clear.png";
        var feature = {};
        feature["kind"] = "icon";
        feature["image"] = glyph_post;
        feature["iconSize"] = [ 32, 32 ];
        feature["iconAnchor"] = [ 9, 34 ];
        feature["iconWindowAnchor"] = [ 9, 2 ];
        mapper_inject_feature(feature);
        }

        if(true) {
        glyph_person = "/dynamapper/icons/emblem-favorite.png";
        var feature = {};
        feature["kind"] = "icon";
        feature["image"] = glyph_person;
        feature["iconSize"] = [ 32, 32 ];
        feature["iconAnchor"] = [ 9, 34 ];
        feature["iconWindowAnchor"] = [ 9, 2 ];
        mapper_inject_feature(feature);
        }

        if(true) {
        glyph_url = "/dynamapper/icons/emblem-important.png";
        var feature = {};
        feature["kind"] = "icon";
        feature["image"] = glyph_url;
        feature["iconSize"] = [ 32, 32 ];
        feature["iconAnchor"] = [ 9, 34 ];
        feature["iconWindowAnchor"] = [ 9, 2 ];
        mapper_inject_feature(feature);
        }
}

//
// Paint a display in js
//
function mapper_page_paint_markers(blob) {

	// mark all objects as stale
	mapper_mark_all_stale();

        // build icons
        mapper_page_paint_icons();

	// visit all the markers and add them
	var markers = blob['results'];
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

		var glyph = glyph_post;
		if( kind == "KIND_USER" ) glyph = glyph_person;
		if( kind == "KIND_URL" ) glyph = glyph_url;

		// Build map feature
		// TODO - i should publish all related parties by drawing lines
		// TODO - i should publish all the depictions from twitter as icons
		if(true) {
                var feature = {};
		feature["kind"] = "marker";
		feature["title"] = title;
		feature["lat"] = lat;
		feature["lon"] = lon;
		feature["glyph"] = glyph;
		mapper_inject_feature(feature);
		}
	}

	// sweep the ones that are not part of this display
	mapper_hide_stale();
}

function mapper_page_paint_text(blob) {

        // draw to these text widgets explicitly for now 
        var people_box = document.getElementById("people_box");
        var posts_box = document.getElementById("posts_box");
        var urls_box = document.getElementById("urls_box");
        if ( people_box != null && people_box.hasChildNodes() ) {
                while ( people_box.childNodes.length >= 1 ) { people_box.removeChild( people_box.firstChild ); }
        }
        if ( posts_box != null && posts_box.hasChildNodes() ) {
                while ( posts_box.childNodes.length >= 1 ) { posts_box.removeChild( posts_box.firstChild ); }
        }
        if ( urls_box != null && urls_box.hasChildNodes() ) {
                while ( urls_box.childNodes.length >= 1 ) { urls_box.removeChild( urls_box.firstChild ); }
        }

        // visit all the markers and add them
        var count_url = 0;
        var count_user = 0;
        var count_post = 0;
        var markers = blob['results'];
        for (var i=0; i<markers.length; i++) {

		var item = markers[i]['note'];

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
                var ownername = "person"
                for (var j=0; j<markers.length; j++) {
                  if(markers[j]['note']['id'] == owner_id) {
                     ownername = markers[j]['note']['title']
                  }
                }

                var glyph = glyph_post;
                if( kind == "KIND_USER" ) glyph = glyph_person;
                if( kind == "KIND_URL" ) glyph = glyph_url;

                // Draw a list of features as well
                var node = document.createElement('div');
                node.style.cursor = "move";
                node.id = "drag"+id;
                if(node) {

                        if(kind == "KIND_URL" && urls_box != null) {
                                node.innerHTML = "<a href='"+title+"'>"+title+"</a>";
                                urls_box.appendChild(node);
                                count_url++;
                        }
                        if(kind == "KIND_USER" && people_box != null) {
                                node.innerHTML = "<a href='http://twitter.com/"+title+"'>"+title+"</a>";
                                people_box.appendChild(node);
                                count_user++;
                        }
                        if(kind == "KIND_POST" && posts_box != null) {
                                node.innerHTML = mapper_make_links_clickable(title,ownername);
                                posts_box.appendChild(node);
                                count_post++;
                        }
                }

// test
node.originalLeft = node.style.left;
node.originalTop = node.style.top;
new Draggable(node,{ revert:mapper_drag_done, ghosting: true  });

	}
        // alert("total urls,users,posts = " + count_url + " " + count_user + " " + count_post );
}

function mapper_drag_done(result) {
  //alert(result.style.left + " -  " + result.style.top);
  return true;
}


/// - figure out where the absolute drag target is
/// - if absolute drag target is in the saved or match area then move it appropriately
//      - make a copy into the new bucket ( such as into saved )
//      - post a new object to the server with this state  ( an insert on this id - or just tag the item perhaps )
//      - probably the reverse is true as well - when you pull out then retag
//      - if two items are dragged overtop each other then thats a match
//              - denote that match on the server
//              - refresh that column on client
//              - play a sound for fun
//              - repaint scor
//
// - 








///
/// Go ahead and paint the supplied set
///
function mapper_page_paint(blob) {

        if(mapper_page_update_already_busy) { return true; }
        mapper_page_update_already_busy = 1;

        try {
            mapper_page_paint_text(blob);
        } catch(err) {
            alert(err);
        }
        
        try {
            mapper_page_paint_markers(blob);
        } catch(err) {
            alert(err);
        }

        mapper_page_update_already_busy = 0;
}

//
// Ask the server for a fresh set of map markers
//
function mapper_page_paint_request(recenter) {

	if(map == null) return;
	var url = "/json?country=" + map_countrycode + "&";

	// tack on the search phrase
	var q = document.getElementById("q");
	if(q != null) {
		q = q.value;
		if(q != null && q.length < 1) q = null;
	}
	if(q != null) {
		url = url + "q="+q+"&";
	}

	// send the bounds upward to server as well
	var sw = map.getBounds().getSouthWest();
	var ne = map.getBounds().getNorthEast();
	if(sw == null || ne == null) {
		return;
	}
	var s = sw.lat();
	var w = sw.lng();
	var n = ne.lat();
	var e = ne.lng();
	url = url + "s="+s+"&w="+w+"&n="+n+"&e="+e;

        // spinner
        var spinner = document.getElementById('spinner');
        if(!spinner) {
          spinner = document.createElement('img');
          spinner.src = "/spinner.gif";
          spinner.id = "spinner";
          spinner.style.position = "absolute";
          spinner.style.left = "10px";
          spinner.style.top = "300px";
          spinner.style.display = "block";
          document.body.appendChild(spinner);
        }
        spinner.style.display = "block";

	new Ajax.Request(url, {
		method:'get',
		requestHeaders: {Accept: 'application/json'},
		onSuccess: function(transport) {
			spinner.style.display = "none";
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

function mapper_goto_location() {
	// send the bounds upward to server as well
	var sw = map.getBounds().getSouthWest();
	var ne = map.getBounds().getNorthEast();
	if(sw == null || ne == null) {
		return;
	}
	var s = sw.lat();
	var w = sw.lng();
	var n = ne.lat();
	var e = ne.lng();
	url = "/?s="+s+"&w="+w+"&n="+n+"&e="+e;
        document.getElementById('newplace').action = url;
        location.href = url;
        return false;
}

/******************************************************************************************************************************************/
// initialization - start up and add any statically defined markers - (we keep markers in javascript as an array to be processed by client)
/******************************************************************************************************************************************/

///
/// Start mapping engine once only
///
function mapper_initialize(
         map_markers_raw,
         mapper_countrycode,
         mapper_south,
         mapper_west,
         mapper_north,
         mapper_east,
         mapper_cover_all_points
       )
{
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
  // map.removeMapType(G_HYBRID_MAP);

  // setup custom icon support
  mapper_icons();

  // try to respect supplied map boundaries for the very first refresh before user does any actions
  map_countrycode = mapper_countrycode;
  map.south = mapper_south;
  map.west = mapper_west;
  map.north = mapper_north;
  map.east = mapper_east;

  // recenter now
  var map_please_recenter = true;
  if(map.north < 0.0 || map.north > 0.0 || map.south < 0.0 || map.south > 0.0) {
    map_please_recenter = false;
    var bounds = new GLatLngBounds( new GLatLng(map.south,map.west,false), new GLatLng(map.north,map.east,false) );
    var center = bounds.getCenter();
    var zoom = map.getBoundsZoomLevel(bounds);
    if(zoom < 2 ) zoom = 2;
    map.setCenter(center,zoom);
  }

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
  if( map_please_recenter && mapper_cover_all_points ) {
  	mapper_center();
  }

  // ask to add features from a remote connection dynamically [ and will center on them ]
  mapper_page_paint_request(map_please_recenter);

  // call a user callback as a last step
  //if(self[mapper_usercallback] && typeof mapper_usercallback = 'function') {
  //  mapper_usercallback();
  //}
}

// TODO consider switching back to this google provided abstraction wrapper
// google.setOnLoadCallback(mapper_initialize);
// google.load("maps", "2.x");
