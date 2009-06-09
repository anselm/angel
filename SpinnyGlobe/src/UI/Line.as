package UI {
	
	import flash.display.*;
	import flash.events.*;
	import flash.text.*;
	import flash.net.*;
	import flash.utils.*;
	import flash.geom.*;
	import support.Vector3;
	import flash.filters.DropShadowFilter;
	
	public class Line extends Sprite {
		
		// ref
		public var app:*;
		
		// properties
		private var lineID:int;
		private var type:String;

		// positioning
		public var startNodeID:uint;
		public var midNodeID:uint;
		public var endNodeID:uint;
		public var startNode:Node;
		public var midNode:Node;
		public var endNode:Node;
	
		// display
		private var line:Sprite;
		private var colorCode:uint;
		private var meadanColors:Boolean = true;
		public var titleTextField:TextField;
		
		public var arcLine:Sprite = new Sprite();
		
		// LINE CONSTRUCTOR ///////////////////////////////////////////////////////////
		public function Line(xmlLine:XML, data:Object):void {
			
			initContent(xmlLine, data);
			setType();
			
			addChild(arcLine);
			//
			addEventListener(Event.ENTER_FRAME, update);
		}

		// INIT CONTENT ///////////////////////////////////////////////////////////////
		private function initContent(xmlLine:XML, data:Object):void {
			
			var attributes:XMLList = xmlLine.attributes();
			
			// extract data from xml attributes
			type 		= attributes[0];
			startNodeID	= attributes[1];
			endNodeID	= attributes[2];
			
			// extract data from data object
			lineID 		= data.lineID;
			app 		= data.app;
		}
		
		// SET TYPE /////////////////////////////////////////////////////////////////////
		private function setType():void {
			
			switch (type) {
				
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
					
				default:
					colorCode = 0xFFFFFF; // white
					break;
			}
		}
		
		// UPDATE /////////////////////////////////////////////////////////////////////
		public function update(event:Event):void {
			
			arcLine.graphics.clear();
   			arcLine.graphics.lineStyle(2, colorCode, 0.6);
			
			// draw curve line thru 3 points (formula by Robert Penner)
			var cx:int = 2 * midNode.x - .5 * (startNode.x + endNode.x);
			var cy:int = 2 * midNode.y - .5 * (startNode.y + endNode.y);
			arcLine.graphics.moveTo (startNode.x, startNode.y);
			arcLine.graphics.curveTo (cx, cy, endNode.x, endNode.y);
			
			// TODO: will need to modify line to show connections over horizon
		}
	}
}
