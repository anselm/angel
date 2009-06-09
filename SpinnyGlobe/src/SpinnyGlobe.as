
//
// Spinny Globe App
// Open Source / Free / Public Domain
// By Anselm Hook, Michael Gaio, Alain Bloch, Matthew Stadler, Stephanie Snyder, Paige Saez and others
// This work was funded by Meedan and Call2Action and MakerLab - thanks so much we love ya!
//
// The hope is to provide a 'good enough' minimalist 3d zoomable globe in flash that others can build on.
// Many people have written proprietary flash globes and the hope here is to reduce that duplicate effort.
//
// In general I've tried to generate the globe surface as a single polygon mesh to avoid slivers.
// The poles are not well dealt with and I avoid those cases by limiting the camera pan and zoom for now.
// In general there should be a 'pole cap' applied or a different rendering algorithm for the poles.
//
// The application also loads in XML content with markers and pop-up dialogs.  Line drawing is supported.
//
// There will hopefully be ongoing incremental improvements - see http://spinnyglobe.googlecode.com
//
//   - anselm sep 1 2008
//
// Notes:
//
// http://www.mail-archive.com/geotools-gt2-users@lists.sourceforge.net/msg04243.html
// http://docs.codehaus.org/display/GEOTDOC/Image+Mosaic+Plugin
// http://geoserver.org/display/GEOSDOC/TileCache+Tutorial
//
// Bugs:
//
//  * polygons are not rendering in certain cases at zoom of 1 - this must be some kind of boundary failure. fixed.
//  * polar caps and slivers
//		* draw white or skip.
//		- a filler polar cap must be drawn? doesn't seem critical yet.
//		- i can still get slivers anyway; circumvented for now but should we unfold as we zoom or render more data?
//		- should we not be so aggressive about only rendering a 3 x 3 ?  if we allowed more (if cached) it may help
//	* remove arcball or apply constraint lock; fixed.
//	* navigation jumps at some zooms; this turns out to be an event handling bug in flash; fixed.
//	* button controls need to scale and a reset would be nice.  fixed.
//  * when you drag outside the screen and let go of the mouse it think the mouse is still down. fixed.
//  * the size of the globe has to be carefully chosen to avoid showing incomplete slivers. fixed.
//  * on a reset the manipulator zoom was not reset so it would drag at the wrong speed. fixed.
//	* draw lines
//	* draw map markers, map popups, load map data
//  * draw a logo
//	* the logo leads to an url that leads to the makerlab site
//  * click on a dot to close little dialog window as well as open it
//  * tie into georss
//	* cannot repeat zoom when you double click again and zoom again
//  * the description is not showing up in georss
//  x decluttering
//		* different zoom levels for data
//  ~ street level data
//  x make pop mode conditional
//  * start over portland oregon
//	- improve line elevation in some cases and think about crossing prime meridian
//	- double buffer by drawing two globes and switching after entirety has loaded
//  - motion momentum
//	- an animation sequencing engine for storytelling
//	- particle effects
//  - compile with flex to let more people participate in coding
//	- remoting for map data is failing - why???
//  - don't open a new window but try use the same window... this is a problem with an iframe
//  - double clicking is failing
//	- a way to toggle between popup and hover information
//	- the info is not revising the same window but instead is opening a new one... bad.
//
//  - server side map data generation strategy
//	    * mapnik builds
//	    - draw map data from open street maps using mapnik as a wms?
//	    - draw base data from mapserver
//	    - draw data behind tilecache
//
//  - server side unix issues on civicmaps.org:
//		- boost won't build so mapnik wont built and mapnik cannot find built in boost
//		- gdal 1.5 won't build due to weird error so bigtiff won't build - so mapserver too - a problem?
//		- could try all on meedan hardware i guess?
//

package {

	import UI.HUDNode;
	import UI.Node;
	
	import flash.display.*;
	import flash.events.*;
	import flash.external.*;
	import flash.filters.*;
	import flash.geom.*;
	import flash.net.*;
	import flash.text.*;
	import flash.utils.*;
	import flash.xml.*;
	
	import org.makerlab.*;
	import org.papervision3d.cameras.*;
	import org.papervision3d.core.geom.Particles;
	import org.papervision3d.core.geom.renderables.Particle;
	import org.papervision3d.core.geom.renderables.Vertex3D;
	import org.papervision3d.core.math.*;
	import org.papervision3d.core.utils.*;
	import org.papervision3d.events.*;
	import org.papervision3d.lights.*;
	import org.papervision3d.materials.*;
	import org.papervision3d.materials.shaders.*;
	import org.papervision3d.materials.special.*;
	import org.papervision3d.materials.utils.*;
	import org.papervision3d.objects.*;
	import org.papervision3d.objects.primitives.*;
	import org.papervision3d.objects.special.*;
	import org.papervision3d.render.*;
	import org.papervision3d.scenes.*;
	import org.papervision3d.view.*;
	
	import support.DataLoader;

	[SWF(width="400", height="400", backgroundColor="#000000", frameRate="31")]
	public class SpinnyGlobe extends Sprite {

		// Markers
		// http://civicmaps.org/suddenly/kmldata.xml
		public var dataPath1:String = "assets/kmldata.xml";
		public var dataPath2:String  = "assets/connections.xml";

		// The planetary surface is always at 0,0,0 and always has this radius
		// Scaling is accomplished by a hack which renders a partial surface fragment on demand
		public var surface_radius:Number = 600;

		// The camera always points at 0,0,0 and has a fixed distance as well.
		// The manipulator rotates the camera while leaving it pointed at the origin.
		// The camera also has a zoom scaling factor and a clipping plane that we change in concert to fake zoom
		public var camera_distance:Number = 5000.0;
		public var camera_focus:Number = 300.0;
		public var camera_zoom:Number = 5.0;
		public var user_zoom:Number = 0.0;
		public var w:Number = 300.0;
		public var h:Number = 300.0;

		// Papervision3d Scenery
		public var spin_scene:Scene3D;
		public var spin_camera:LocalCamera3D;
		public var spin_viewport:Viewport3D;
		public var spin_renderer:BasicRenderEngine;
		public var manipulator:Manipulator = null;
		public var planet:WMSLayer;
		public var backing:Sprite;

		// Navigation button events [ look elsewhere for mouse move and drag events ]
		private function event_move_up   (event:MouseEvent):void { manipulator.event_move(  0, 50); }
		private function event_move_down (event:MouseEvent):void { manipulator.event_move(  0,-50); }
		private function event_move_left (event:MouseEvent):void { manipulator.event_move( 50,  0); }
		private function event_move_right(event:MouseEvent):void { manipulator.event_move(-50,  0); }
		private function event_zoom_out(event:MouseEvent):void {
			if(user_zoom>0) {
				user_zoom--;
				manipulator.zoom = user_zoom;
				spin_camera.zoom = spin_camera.zoom / 2;
			}
		}
		private function event_zoom_in(event:MouseEvent):void {
			if(user_zoom < 17 ) {
				user_zoom++;
				manipulator.zoom = user_zoom;
				spin_camera.zoom = spin_camera.zoom * 2;
			}
		}
		private function event_reset(event:MouseEvent):void {
			user_zoom = 0;
			manipulator.zoom = user_zoom;
			manipulator.reset();
			spin_camera.reset();
		}
		public function event_focus_appropriately_on(_lat:Number,_lon:Number,_zoom:Number=8):void {
			state_target_lat = _lat;
			state_target_lon = _lon;
			user_zoom = _zoom;
			spin_camera.reset();
			spin_camera.set_zoom(user_zoom);
			manipulator.event_set_focus(user_zoom,_lat,_lon);
			// the manipulator will write to the camera and set it - but doesn't set camera zoom atm
		}

		///////////////////////////////////////////////////////////////////////////////////////////////////
		// A STATE ENGINE ( unused and incomplete )
		///////////////////////////////////////////////////////////////////////////////////////////////////

		private var state_target_zoom:Number = 45;
		private var state_target_lon:Number = -122;
		private var state_target_lat:Number = 0;
		private var state_motion_x:Number = 0.1;
		private var state_motion_y:Number = 0.1;
		private var state_activity:Number = 0;
		
		private function sequence_suspend():void {
			state_activity = 30;
		}

		private function sequence_goto(lat:Number,lon:Number,zoom:Number = 0):void {
			state_target_lat = lat;
			state_target_lon = lon;
			state_target_zoom = zoom;
		}

		private function sequencing_engine():void {
			if(true) return;
			// a script driven state machine that incrementally moves things over time...
			if( state_activity > 0 ) {
				state_activity = state_activity - 1;
				return;
			}
			event_focus_appropriately_on(state_target_lat,state_target_lon-0.3,user_zoom);
		}

		///////////////////////////////////////////////////////////////////////////////////////////////////
		// KEY CAPTURE
		///////////////////////////////////////////////////////////////////////////////////////////////////

		/*
		// TODO: this does not work if inside of a manipulator - why?
		public override function event_key_down(e:KeyboardEvent):void {

			trace("got key "+ e.keyCode );

			switch(e.keyCode) {

				// NUMBERS
				case 48: // 0
					trace ("0");
					user_zoom = 0;
					break;
					
				case 49: // 1
					trace ("1");
					user_zoom = 1;
					break;
					
				case 50: // 2
					trace ("2");
					user_zoom = 2;
					break;
					
				case 51: // 3
					trace ("3");
					user_zoom = 3;
					break;
					
				case 52: // 4
					user_zoom = 4;
					break;
					
				case 53: // 5
					user_zoom = 5;
					break;
					
				case 54: // 6
					user_zoom = 6;
					break;
					
				case 55: // 7
					user_zoom = 7;
					break;
				
				case 56: // 8
					user_zoom = 8;
					break;
					
				case 57: // 9
					user_zoom = 9;
					break;
					
				default:
					break;
			}
		}
		public override function event_mouse_zoom(e:MouseEvent):void {
			//if( e.delta > 0 ) zoom = zoom + 1;
			//if( e.delta < 0 ) zoom = zoom - 1;
			//if( zoom > 10 ) zoom = 10;
			//if( zoom < 0 ) zoom = 0;
		}
		*/

		public function makerlab_listenener():void {
			navigateToURL(new URLRequest("http://makerlab.com"));
		}

		///////////////////////////////////////////////////////////////////////////////////////////////////
		// START
		///////////////////////////////////////////////////////////////////////////////////////////////////

		public function SpinnyGlobe():void {

			opaqueBackground = 0xffffff;

			// some mumbo jumbo
			stage.scaleMode = "noScale"

			// width and height
			if( stage.stageWidth > 0 ) {
				w = stage.stageWidth;
				h = stage.stageHeight;
			}

			// A mandatory backdrop to catch mouse events
			if( true ) {
				backing = new Sprite();
				backing.x = w / 2;
				backing.y = h / 2;
				addChild(backing);
			}

			// An optional earth glow effect
			if (true) {
				var earthglow:Sprite = new Sprite();
				// TODO: scaling is not working properly
				var glowRadius:Number = surface_radius;
				var fillType:String = GradientType.RADIAL;
				var colors:Array = [0x0ACCFF, 0x003399];
				var alphas:Array = [100, 0];
				var ratios:Array = [140, 165];
				var matr:Matrix = new Matrix();
				matr.createGradientBox(glowRadius, glowRadius, 0, -(glowRadius/2), -(glowRadius/2));
				var spreadMethod:String = SpreadMethod.PAD;
				earthglow.graphics.beginGradientFill (
					fillType, colors, alphas, ratios, matr, spreadMethod);  
				earthglow.graphics.drawCircle(0, 0, glowRadius);
				earthglow.graphics.endFill();
				earthglow.x = w / 2 ;
				earthglow.y = h / 2 ;
				addChildAt(earthglow, 0);
			}

			// papervision3d startup
			spin_viewport = new Viewport3D(w, h, true, true);
			addChild( spin_viewport );
			spin_renderer = new BasicRenderEngine();
			spin_scene = new Scene3D();

			// An optional pretty star-field - slow
			if (false) {
				var star_material:BitmapFileMaterial = new BitmapFileMaterial("assets/stars.png");
				star_material.doubleSided = false;
				star_material.smooth = false;
				var stars:Sphere = new Sphere( star_material, camera_distance*1.1, 32, 16 );
				spin_scene.addChild(stars);
			}

			// A WMS tiled sphere - the core of the whole project
			if (true) {
				planet = new WMSLayer(surface_radius);
				planet.focus(0,0,0);
				spin_scene.addChild(planet);
			}

			// An optional test object for debugging
			if (false) {
				var material2:BitmapFileMaterial = new BitmapFileMaterial("assets/earth.jpg");
				material2.doubleSided = false;
				material2.smooth = false;
				var globe:Sphere = new Sphere(null,surface_radius, 42, 42);
				spin_scene.addChild(globe);
			}

			// a logo rendered via ordinary flash
			if(true) {
				var loader:Loader = new Loader();
				this.addChild(loader);
				loader.x = 0;
				loader.y = h-22;
				loader.load(new URLRequest("assets/m.png"));
				//loader.addEventListener(MouseEvent.CLICK, makerlab_listener );
			}

			// Map navigation controls
			if( true ) {
				var s:Sprite;
				var size:Number = 20;

				// up
				s = new Sprite();
				s.x=2*size; s.y=1*size;
				s.graphics.beginFill(0xffff00);
				s.graphics.drawCircle(0,0,size/2);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_move_up);
				addChild(s);

				// down
				s = new Sprite();
				s.x=2*size; s.y=3*size;
				s.graphics.beginFill(0xffff00);
				s.graphics.drawCircle(0,0,size/2);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_move_down);
				addChild(s);

				// left
				s = new Sprite();
				s.x=1*size; s.y=2*size;
				s.graphics.beginFill(0xfff000);
				s.graphics.drawCircle(0,0,size/2);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_move_left);
				addChild(s);

				// right
				s = new Sprite();
				s.x=3*size; s.y=2*size;
				s.graphics.beginFill(0xfff000);
				s.graphics.drawCircle(0,0,size/2);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_move_right);
				addChild(s);

				// zoom out
				s = new Sprite();
				s.x=2*size; s.y=5*size-size/5;
				s.graphics.beginFill(0xff00ff);
				s.graphics.drawCircle(0,0,size/2);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_zoom_out);
				addChild(s);

				// zoom in
				s = new Sprite();
				s.x=2*size; s.y=6*size;
				s.graphics.beginFill(0xff00ff);
				s.graphics.drawCircle(0,0,10);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_zoom_in);
				addChild(s);

				// reset
				s = new Sprite();
				s.x=2*size; s.y=8*size;
				s.graphics.beginFill(0xff0000);
				s.graphics.drawCircle(0,0,10);
				s.graphics.endFill();
				s.addEventListener(MouseEvent.CLICK,event_reset);
				addChild(s);

			}

			// Camera and controller over the scene
			if( true ) {
				spin_camera = new LocalCamera3D(camera_distance,camera_focus,camera_zoom);
				manipulator = new Rotater(surface_radius,w,h);
				manipulator.event_set_focus(user_zoom,40,-120);
			}

			// tests to deal with when papervision3d source code is revved and inevitably breaks my work
			if( false ) {
				var cube:Cube;
				var cube2:Cube;
				var mat:FlatShadeMaterial = new FlatShadeMaterial(new PointLight3D(), 0xFFFFFF, 0xFF0000);
				var mat2:WireframeMaterial = new WireframeMaterial(0x00FF00);
				var plane:Plane = new Plane(null, 2000, 2000, 10, 10);
				cube = new Cube(new MaterialsList( { all: mat } ), 100, 100, 100);
				cube.y = 0;
				cube2 = new Cube(new MaterialsList( { all: mat2 } ), 100, 100, 100);
				cube2.y = 0;
				cube2.x = 1000;
				cube2.z = 1000;
				plane.material.lineColor = 0x777777;
				plane.material.doubleSided = true;
				plane.pitch(90);
				plane.y = -50;
				spin_scene.addChild(plane);
				spin_scene.addChild(cube);
				spin_scene.addChild(cube2);
				spin_camera.x = 0;
				spin_camera.z = camera_distance;
				spin_camera.y = 0;
				//spin_camera.lookAt(cube);
			}

			event_focus_appropriately_on(45,-122,0);
			
			// Event handling for keyboard and mouse drag type events [ and not for mouse button click events ]
			if( manipulator ) {
				addEventListener(KeyboardEvent.KEY_DOWN, manipulator.event_key_down , true);
				addEventListener(MouseEvent.MOUSE_UP,    event_mouse_up , true);
				addEventListener(MouseEvent.MOUSE_DOWN,  event_mouse_down , true);
				addEventListener(MouseEvent.MOUSE_MOVE,  event_mouse_move , true);
				addEventListener(MouseEvent.MOUSE_WHEEL, event_mouse_zoom , true);
			}

			addEventListener(Event.ENTER_FRAME, event_update);

			// load markers with zoom levels
			markers_load(dataPath1,0,6);

			// draw test lines
			lines_load(dataPath2);

			// add heads up display
			hud_create();

			// lets look at the flash variables
			this.loaderInfo.addEventListener(Event.COMPLETE, this.loaderComplete);

		}

		///////////////////////////////////////////////
		// native method gateway / api
		///////////////////////////////////////////////
		public function testme():void {
			trace("hello");
		}
		
		//////////////////////////////////////////////
		// bizarre flash code to get at html parameters
		//////////////////////////////////////////////
		public function loaderComplete(myEvent:Event):void {
			// trace( this.loaderInfo.parameters );
		}

		//////////////////////////////////////////////
		// bizarre flash code to do double click
		//////////////////////////////////////////////
		private var lastclick:int = 0;
		private var clickstate:int = 0;
		private var lastx:int = 0;
		private var lasty:int = 0;

		public function event_mouse_down(e:MouseEvent):void {
			sequence_suspend();
			if( clickstate < 2 ) {
				clickstate = 1;
				lastclick = getTimer();
				lastx = e.stageX;
				lasty = e.stageY;
			} else {
				clickstate = 0;
				if( (getTimer() - lastclick) < 300 ) {
					//why is e.stageX zero? xxx if( lastx == e.stageX && lasty == e.stageY ) {
						event_zoom_in(e);
					//}
				}
			}
			manipulator.event_mouse_down(e);
		}

		public function event_mouse_up(e:MouseEvent):void {
			if( clickstate == 1 ) {
				clickstate = 2;
			}
			manipulator.event_mouse_up(e);
		}

		public function event_mouse_move(e:MouseEvent):void {
			if( e.buttonDown ) sequence_suspend();
			manipulator.event_mouse_move(e);
		}

		public function event_mouse_zoom(e:MouseEvent):void {
			sequence_suspend();
			manipulator.event_mouse_zoom(e);
		}

		//
		// convert longitude and latitude into a vector
		//

		public function to_vector(latitude:Number,longitude:Number,elevation:Number = 0):Vertex3D {
			var v:Vertex3D = new Vertex3D();
			latitude = Math.PI * latitude / 180;
			longitude = Math.PI * longitude / 180;
			// rotate into our frame
			longitude += Math.PI/2;
			latitude -= Math.PI/2;
			elevation = elevation ? elevation : surface_radius;
			v.x = elevation * Math.sin(latitude) * Math.cos(longitude);
			v.z = elevation * Math.sin(latitude) * Math.sin(longitude);
			v.y = elevation * Math.cos(latitude);
			return v;
		}

		//import org.papervision3d.materials.special.LineMaterial;
		//import org.papervision3d.core.geom.Lines3D;
		//var lm:LineMaterial = new LineMaterial(0xff0000,0.5);
		//var lines:Lines3D = new Lines3D();

		// ************************************************************************************************************************
		// lines
		// ************************************************************************************************************************

		private function lines_load(dataPath:String):void {
			var dataType:String = "XML";
			var xmlSession:DataLoader = new DataLoader({
				dataType: 	dataType,
				dataPath:	dataPath,
				app:		this,
				onLoad:		this.lines_parse
			});
			xmlSession.loadData();
		}

		public function lines_parse(xmlData:XML):void {
			for each (var blob:XML in xmlData.line) { 			
				var attributes:XMLList = blob.attributes();
				var type:Number = attributes[0];
				var startNodeID:Number = attributes[1];
				var endNodeID:Number = attributes[2];
				hudText.text = "hello " + nodes.length;
			lines_arc(50,-122,60,-112);
				if(nodes.length > startNodeID && nodes.length > endNodeID ) {
					var n1:Node	= nodes[startNodeID];
					var n2:Node = nodes[endNodeID];
					lines_arc(n1.latitude,n1.longitude,n2.latitude,n2.longitude);
				}
			}
		}

		public function lines_arc(lat1:Number,lon1:Number,lat2:Number,lon2:Number):void {
			var a:Vertex3D = to_vector(lat1,lon1);
			var b:Vertex3D = to_vector(lat2,lon2);
			// TODO xxx wraparound
			var x:Number = (lat1+lat2)/2;
			var y:Number = (lon1+lon2)/2;
			// TODO xxx hack less
			var z:Number = Math.sqrt(x*x+y*y)*3 + surface_radius;
			var c:Vertex3D = to_vector(x,y,z);
			var be:Bezier3D = new Bezier3D(0xccff44,2,10,a,b,c);
			spin_scene.addChild(be._instance);
		}

		// ************************************************************************************************************************
		// markers
		// ************************************************************************************************************************

		// nodes
		private var node:Node;
		private var nodeID:int = 0;
		private var nodes:Array = new Array();
		private var marker_particles:Particles = null;
		public var winOpen:Boolean = false;
		public var winNodeID:int = -1;
		public var minzoom:int = 0;
		public var maxzoom:int = 999;

		private function markers_load(filename:String,_minzoom:int = 0,_maxzoom:int = 999):void {
			this.minzoom = _minzoom;
			this.maxzoom = _maxzoom;
			var xmlSession:DataLoader = new DataLoader({
				dataType: "XML",
				dataPath: filename,
				app: this,
				onLoad: this.markers_parse
			});
			xmlSession.loadData();
		}

		public function markers_parse(xmlData:XML):void {

			// make a particle place holder; we don't use it for the art for now
			if( marker_particles == null) marker_particles = new Particles();
			var pm:ParticleMaterial = new ParticleMaterial(0xff0000,0,1);

			// turn the xml into scenery
			var ns:Namespace = xmlData.namespace();
			for each (var xmlPlacemark:XML in xmlData.ns::Placemark) {
				var node:Node = new Node(xmlPlacemark,{ nodeID: nodeID, app: this }, this );
				nodes.push(node);
				node.minzoom = this.minzoom;
				node.maxzoom = this.maxzoom;
				this.addChild(node);
				nodeID++;
				// make facade geometry as a place holder
				var v:Vertex3D = to_vector(node.latitude,node.longitude);
				var p:Particle = new Particle(pm,0,v.x,v.y,v.z);
				marker_particles.addParticle(p);
			}
			spin_scene.addChild(marker_particles);

/*
			// hack - load some more
			this.minzoom = 7;
			this.maxzoom = 999;
			markers_load_rss("http://suddenly.org/?feed=rss2",7,999);
*/
		}

		public function marker_place(node:Node):void {
			// this routine dynamically updates the nodes every frame
			// http://www.everydayflash.com/blog/index.php/2008/07/07/pixel-precision-in-papervision3d/
			if( user_zoom < node.minzoom || user_zoom > node.maxzoom ) {
				node.visible = false;
				return;
			} else {
				node.visible = marker_particles.geometry.vertices[node.nodeID].vertex3DInstance.z < camera_distance;
			}
			node.x = marker_particles.geometry.vertices[node.nodeID].vertex3DInstance.x + spin_viewport.viewportWidth / 2;
			node.y = marker_particles.geometry.vertices[node.nodeID].vertex3DInstance.y + spin_viewport.viewportHeight / 2;
			// - xxx would be nice to do a shadow...
			// - xxx can bitmapparticalmaterial present the same node and same data without interleaving? no.
			// adjust alpha transparency for z dimension (optional)
			// alpha = (1 - (tempPos.z + app.radius * 2) / (app.radius * 2)) * 0.3 + 0.7;
			// adjust alpha transparency for z dimension on just the shadow (optional)
			// node.shadowpoint.alpha = (1 - (tempPos.z + app.radius * 2) / (app.radius * 2)) * 0.3 + 0.7;				
		}

		public function marker_highlight(nodeID:int,state:Boolean):void {
			var hudNode:DisplayObject = this.getChildByName("hudNode");  
			if (state && hudNode) {
				node = nodes[nodeID];
				if(node == null) return;
				hudNode.x = node.x;
				hudNode.y = node.y;
				hudNode.visible = true;
				node.titleTextField.visible = true;
			} else {
				hudNode.visible= false;
				//node.titleTextField.visible = false;
			}
		}

		// ************************************************************************************************************************
		// rss markers
		// ************************************************************************************************************************

		private function markers_load_rss(filename:String,_minzoom:int = 7 ,_maxzoom:int = 999):void {
			this.minzoom = _minzoom;
			this.maxzoom = _maxzoom;
			var xmlSession:DataLoader = new DataLoader({
				dataType: "XML",
				dataPath: filename,
				app: this,
				onLoad: this.markers_parse_rss
			});
			xmlSession.loadData();
		}

		public function markers_parse_rss(xmlData:XML):void {

			// make a particle place holder; we don't use it for the art for now
			if(marker_particles == null) marker_particles = new Particles();
			var pm:ParticleMaterial = new ParticleMaterial(0xff0000,0,1);

			// turn the xml into scenery
			var ns:Namespace = xmlData.namespace();
			for each (var channel:XML in xmlData.ns::channel) {
				for each (var xmlPlacemark:XML in channel.ns::item) {
					var node:Node = new Node(xmlPlacemark,{ nodeID: nodeID, app: this }, this);
					node.minzoom = this.minzoom;
					node.maxzoom = this.maxzoom;
					nodes.push(node);
					this.addChild(node);
					nodeID++;
					// make facade geometry as a place holder
					var v:Vertex3D = to_vector(node.latitude,node.longitude);
					var p:Particle = new Particle(pm,0,v.x,v.y,v.z);
					marker_particles.addParticle(p);
				}
			}
			spin_scene.addChild(marker_particles);

		}
		
		// ************************************************************************************************************************
		// hud
		// ************************************************************************************************************************

		private var hudNode:HUDNode = null;
		private var activeNodes:Boolean = true;
		private var showHudText:Boolean = true;
		private var hudText:TextField = new TextField();

		private function hud_create():void {

			// hud text info
			if (showHudText) {
				hudText.x 					= 10;
    	   	 	hudText.y 					= 10;
				hudText.selectable 			= false;
				var tFormat:TextFormat 		= new TextFormat();
				tFormat.font 				= "Courier";
				tFormat.color				= 0xaaaaaa;
				tFormat.size 				= 10;
				tFormat.align 				= "left";
				hudText.defaultTextFormat 	= tFormat;
				hudText.width				= 500;
				addChild(hudText);
			}

			// hud marker highlight
			var hudNode:HUDNode = new HUDNode({app:this});
			hudNode.name = "hudNode";
			hudNode.visible = true;
			this.addChild(hudNode);
		}

		// general update; flash doesn't support vertical beam synchronization... dunno how fast this is.
		public function event_update(e:Event):void {
			if( manipulator ) {
				spin_camera.my_transform = manipulator.get_transform();
			}
			if( planet ) {
				planet.focus(spin_camera.lat(),spin_camera.lon(),user_zoom);
			}
			spin_renderer.renderScene(spin_scene, spin_camera, spin_viewport);
			sequencing_engine();
		}
	}
}

