package UI {
	
	import flash.display.*;
	import flash.events.*;
	import flash.text.*;
	
	public class HUDNode extends Sprite {
		
		public var hudHighlight:Sprite;
		public var app:*; // the calling application
		
		// properties
		public var title:String;
		
		// display
		public var titleTextField:TextField = new TextField();
		
		// CONSTRUCTOR ///////////////////////////////////////////////////////////////
		public function HUDNode(data:Object):void {
			//createHighlight();
			//initTextDisplay();
		}
		
		// CREATE HIGHLIGHT ///////////////////////////////////////////////////////////
		private function createHighlight():void {
			hudHighlight = new Sprite();
			hudHighlight.graphics.lineStyle(3, 0xFFFFFF, 0.5);
			hudHighlight.graphics.beginFill(0xFFFFFF, 1);
			hudHighlight.graphics.drawCircle(0, 0, 20);
			hudHighlight.alpha = 0.3;
			addChild(hudHighlight);
		}
		
		/* preferred over node *
		// TEXT DISPLAY (initialize) ///////////////////////////////////////////////// 
		private function initTextDisplay:void() {
			
			var showTitle:Boolean = true;
			if (showTitle == true) {
				
				// text formatting
				var format:TextFormat = new TextFormat();
				format.font 	= "Courier"; 
				format.color 	= 0xFFFFFF;
				format.size 	= 12;
				format.align 	= "left";
				
				// title text
				titleTextField.y = -10;
				titleTextField.x = 10;
				titleTextField.autoSize = "left";
				titleTextField.selectable = false;
				titleTextField.defaultTextFormat = format;
				addChild(titleTextField);
				titleTextField.visible = false;
				titleTextField.text = title;
			}
		}*/
	}
}
