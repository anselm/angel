package UI {
	
	// associates to "Pointer" MC graphic in meadanglobe.fla library
	
	import flash.display.*;
	import flash.events.*;
	
	public class Pointer extends MovieClip {
		
		// reference
		public var appNode:*;
		public var app:*;
		
		// POINTER /////////////////////////////////////////////////////////////// 
		public function Pointer(pntData:Object):void {
			
			// ref
			appNode 	= pntData.appNode;

			alpha 		= 0.6;
			
			// events
			addEventListener(Event.ENTER_FRAME, render);
		}
		
		// RENDER (position pointer) //////////////////////////////////////////////
		private function render(event:Event):void {
			
			// match visibility to node
			visible = appNode.visible;

			if (visible) {
				// set position relative to node position
				x = appNode.x;
				y = appNode.y;
			
				// adjust pointer rotation (4 quadrants)
				if (appNode.x < 0 && appNode.y < 0) {
					rotation = 0;
				}
				if (appNode.x < 0 && appNode.y >= 0) {
					rotation = -90;
				}
				if (appNode.x >= 0 && appNode.y < 0) {
					rotation = 90;
				}
				if (appNode.x >= 0 && appNode.y >= 0) {
					rotation = 180;
				}
			}
		}
	}
}

