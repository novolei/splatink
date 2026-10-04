class_name SplatCodeCell
extends Control
var field:LineEdit
var index:int=0
var _clock:float=0.0
var _caret:StyleBoxFlat=StyleBoxFlat.new()
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	field=get_parent() as LineEdit
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(delta:float)->void:
	_clock+=delta
	if is_instance_valid(field) and field.text.is_empty():queue_redraw()
func _draw()->void:
	if not is_instance_valid(field) or not field.text.is_empty():return
	var u:float=size.y/7.6
	var inset:float=u*.5
	var rect:Rect2=Rect2(Vector2.ONE*inset,size-Vector2.ONE*inset*2)
	var dash:float=u*.45
	var color:=Color(1,1,1,.16)
	# The source blank cells use an inset dashed frame and a bottom caret, rather than a text glyph.
	for y:float in [rect.position.y,rect.end.y]:
		var x:float=rect.position.x+u*.6
		while x<rect.end.x-u*.6:
			draw_line(Vector2(x,y),Vector2(minf(rect.end.x-u*.6,x+dash),y),color,2.0,true);x+=dash*2.0
	for x:float in [rect.position.x,rect.end.x]:
		var y:float=rect.position.y+u*.6
		while y<rect.end.y-u*.6:
			draw_line(Vector2(x,y),Vector2(x,minf(rect.end.y-u*.6,y+dash)),color,2.0,true);y+=dash*2.0
	_caret.bg_color=Color("e3ff2e") if field.has_focus() else Color(1,1,1,.2)
	_caret.bg_color.a*=1.0 if not field.has_focus() or fmod(_clock,1.0)<.5 else 0.0
	if not field.has_focus():_caret.bg_color.a*=.75+.25*sin((_clock-index*.12)*TAU/2.4)
	_caret.set_corner_radius_all(roundi(u*.25))
	draw_style_box(_caret,Rect2(size.x*.24,size.y*.86-u*.5,size.x*.52,u*.5))
