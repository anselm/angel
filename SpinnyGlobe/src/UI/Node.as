package UI {

	// associates to "Node" MC graphic in meadanglobe.fla library

	import flash.display.*;
	import flash.events.*;
	import flash.filters.DropShadowFilter;
	import flash.geom.*;
	import flash.net.*;
	import flash.text.*;
	import flash.utils.*;

	public class Node extends MovieClip {

		// ref
		public var app:*;

		// properties
		public var nodeID:int;
		public var id:uint;
		public var title:String;
		public var link:String;
		public var type:String;
		public var geoPosition:String;
		public var description:String;
		public var latitude:Number;
		public var longitude:Number;
		public var elevation:Number;
		public var contentPath:String;

		// scaling
		private var origXScale:Number = 1;
		private var origYScale:Number = 1;
		public var minzoom:int = 0;
		public var maxzoom:int = 999;

		// display
		private var marker:Sprite;
		private var colorCode:uint;
		private var localColors:Boolean = true;
		private var invisible:Boolean = false; // ?
		public var titleTextField:TextField;
		public var parentscope:SpinnyGlobe = null;

		// NODE CONSTRUCTOR ////////////////////////////////////
		public function Node(xmlPlacemark:XML, data:Object, p:SpinnyGlobe = null):void {
			parentscope = p;
			initContent(xmlPlacemark, data);
			setType();
			initTextDisplay();
			addEventListener(Event.ENTER_FRAME, update);
			addEventListener(MouseEvent.CLICK, clickHandler);
			addEventListener(MouseEvent.MOUSE_OVER, mouseOverHandler);
			addEventListener(MouseEvent.MOUSE_OUT, mouseOutHandler);
		}
		
		// INIT CONTENT (KML XML) ///////////////////////////////////////////////////////////////
		// note: KML may be the best standard for geodata integration
		// see: http://code.google.com/apis/kml/documentation
		private function initContent(xmlPlacemark:XML, data:Object):void {

			// declare a default namespace
			// (inherited from parent node if none declared)
		 	var ns:Namespace = xmlPlacemark.namespace();
		  	default xml namespace = ns;

			// extract data from XML //////////////////////////////////////
		    // (assumes all target members are string types)

			// get some things
			id = xmlPlacemark.@id.toString();  // xxx unused remove
		    type = xmlPlacemark.@type.toString();

			// more stuff
			title = xmlPlacemark.name.toString();
			if( title.length < 1 ) { // xxx hack georss
				title = xmlPlacemark.title.toString();
			}
			link = xmlPlacemark.link.toString();
		 	contentPath = xmlPlacemark.description.toString();

			// get other stuff
			var geoPos:Array;
			if( xmlPlacemark.Point != null && type.length > 0 ) { // xxx HACK for georss
			  	geoPosition = xmlPlacemark.Point.coordinates.toString();
				geoPos = geoPosition.split(",", 3);
				latitude  = geoPos[0];
				longitude = geoPos[1];
				elevation = 0; // (available at geoPos[2])
			}
			else if( xmlPlacemark.point != null ) {
				// <georss:point featurename="reed college, portland, oregon">45.479641 -122.629990</georss:point>
				var georss:Namespace = new Namespace("http://www.georss.org/georss");
				default xml namespace = georss;
				geoPos = xmlPlacemark.point.toString().split(" ",2);
				default xml namespace = ns;
				latitude = geoPos[0];
				longitude = geoPos[1];
	 			elevation = 0;
				type = "1"; // hack
			}

			// extract data from data object
			nodeID 		= data.nodeID; 
			app 		= data.app;

			// reset namespace to null
			// (this is necessary to avoid: "VerifyError: Error #1025: An invalid register 3 was accessed" )
			default xml namespace = null;
		}
		
		// SET TYPE /////////////////////////////////////////////////////////////////////
		private function setType():void {
			
			switch (type) {
				
				case "0":
					colorCode = 0x000000; // black
					break;
				
				case "1":
					colorCode = 0xE06117; // red
					break;
				
				case "2":
					colorCode = 0x6DC1EF; // blue
					break;
				
				case "3":
					colorCode = 0x7FDD34; // green
					break;
				
				case "4":
					colorCode = 0xD0C32E; // yellow
					break;
					
				case "8":
					colorCode = 0xFFFFFF; // white
					break;
					
				default:
					colorCode = 0xFFFFFF; // white
					break;
			}
			
			if (type != "0") {
				if (!localColors) {colorCode = 0xFFFFFF}
				colorTransform(colorCode);
			}
		}

		// TRANSFORMATIONS /////////////////////////////////////
		private function colorTransform(colorCode:uint):void {

			// change color to type
			var colorInfo:ColorTransform = this.transform.colorTransform;
			colorInfo.color = colorCode;
			this.transform.colorTransform = colorInfo;

			// apply the drop shadow
			var shadow:DropShadowFilter = new DropShadowFilter();
			shadow.distance = 7;
			shadow.angle 	= 35;
			this.filters = [shadow];

		}

		// UPDATE /////////////////////////////////////////////////////////////////////
		public function update(event:Event):void {
			render();
		}

		// RENDER (position node in 3D space) ////////////////////////////////////////
		private function render():void {
			app.marker_place(this);
		}

		// TEXT DISPLAY (initialize) ///////////////////////////////////////////////// 
		private function initTextDisplay():void {
			var showTitle:Boolean = true;
			if (showTitle) {
				// text formatting
				var format:TextFormat 				= new TextFormat();
				format.font 		  				= "Helvetica"; 
				format.color 		  				= 0xFFFFFF;
				format.size 		  				= 12;
				format.align 	      				= "left";
				// title text
				titleTextField 						= new TextField();
				titleTextField.y 					= -8;
				titleTextField.x 					= 15;
				titleTextField.autoSize 			= "left";
				titleTextField.selectable 			= false;
				titleTextField.defaultTextFormat 	= format;
				titleTextField.visible 				= true;
				titleTextField.text 				= title;
				addChild(titleTextField);
			}
		}

		// EVENT HANDLERS ///////////////////////////////////////////////////////////////
		public function clickHandler(event:MouseEvent):void {

			if(this.type == "2" ) {
				parentscope.event_focus_appropriately_on(this.latitude,this.longitude);
				return;
			}

			navigateToURL(new URLRequest(link));
			return;

			if (app.winOpen == true) {
				closeWindow();
				app.winOpen = false;
				if( app.winNodeID == nodeID ) {
					// clicking same node again leaves it closed or closes it.
					return;
				}
			}
			if (app.winOpen == false) {
				openWindow();
				addPointer();
				app.winNodeID = nodeID;
			}
		}

		public function mouseOverHandler(event:MouseEvent):void {
			if( visible == true) {
				app.marker_highlight(nodeID, true);
			}
		}

		public function mouseOutHandler(event:MouseEvent):void {
			app.marker_highlight(nodeID, false);
		}

		// GROW /////////////////////////////
		public function grow():void {
			if( visible ) {
				this.scaleX = origXScale * 1.6;
				this.scaleY = origYScale * 1.6;
			}
		}

		// SHRINK ////////////////////////////
		public function shrink():void {
			this.scaleX = origXScale;
			this.scaleY = origYScale;
		}

		// OPEN WINDOW ////////////////////////////////////////////////////////////////////////
		public function openWindow():void {
			var winMode:String = type;
			var win:WinDisplay = new WinDisplay({
								// content
								winMode		:winMode,
								title		:title,
								contentPath	:contentPath,
								colorCode   :colorCode,
								// ref
								appNode		:this,
								app			:app
								});
			win.name = "window";
			app.addChild(win);
			app.winOpen = true;
		}

		// ADD POINTER ////////////////////////////////////////////////////////////////////////
		private function addPointer():void {
			var pointer:Pointer = new Pointer({appNode:this});
			pointer.name = "pointer";
			app.addChild(pointer);
		}

		// CLOSE WINDOW ////////////////////////////////////////////////////////////////////////
		public function closeWindow():void {
			// remove pointer
			var rPointer:DisplayObject = app.getChildByName("pointer"); 	
			app.removeChild(rPointer);
			// remove window
			var rWin:DisplayObject = app.getChildByName("window"); 	
			app.removeChild(rWin);
			app.winOpen = false;
		}

		// MAKE INVISIBLE  /////////////////////////////////////////////////////////////////////
		public function makeInvisible():void {
			this.visible = false;
			removeEventListener(MouseEvent.CLICK, clickHandler);
			removeEventListener(MouseEvent.MOUSE_OVER, mouseOverHandler);
			removeEventListener(MouseEvent.MOUSE_OUT, mouseOutHandler);
		}
	}
}
