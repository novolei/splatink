extends Control
## Single pooled CanvasItem; only the short quadratic preview/cursor are regenerated.
var diorama:Control
const GROUND:=preload("res://assets/ui/source/diorama_ground.svg")
func _draw()->void:
	if diorama==null or not diorama.on:return
	var alpha:float=smoothstep(.3,.95,float(diorama.k));var pin_k:float=smoothstep(.62,1.0,float(diorama.k))
	var screen_scale:float=diorama.view.canvas.scale.x
	for index:int in diorama.pins.size():
		var pin:Dictionary=diorama.pins[index]
		if not pin.visible:continue
		var ground:Vector2=Vector2(pin.position)/diorama.view.canvas.scale
		var badge:Vector2=Vector2(pin.display)/diorama.view.canvas.scale-Vector2(0,28.16*pin_k)
		var ground_size:Vector2=Vector2(28.16 if index==4 else 19.2,8.7)
		draw_texture_rect(GROUND,Rect2(ground-ground_size*.5,ground_size),false,Color(diorama._color,alpha*pin_k))
		draw_line(ground,badge,Color(SplatUiTheme.INK,alpha*pin_k),6/screen_scale,true)
		draw_line(ground,badge,Color(1,1,1,alpha*pin_k),3/screen_scale,true)
	var arc:PackedVector2Array=diorama._arc
	if arc.size()>1:
		draw_polyline(arc,Color(SplatUiTheme.INK,alpha*.55),9,true)
		var travelled:float=0;var phase:float=fmod(float(diorama._clock)*25,15)
		for index:int in arc.size()-1:
			var a:Vector2=arc[index];var b:Vector2=arc[index+1];var length_value:float=a.distance_to(b);var offset:float=0
			while offset<length_value:
				var cycle:float=fmod(travelled+offset+phase,15);var segment:float=minf(length_value-offset,(2 if cycle<2 else 15)-cycle)
				if cycle<2:draw_line(a.lerp(b,offset/maxf(.001,length_value)),a.lerp(b,(offset+segment)/maxf(.001,length_value)),Color(diorama._color,alpha),5,true)
				offset+=maxf(.001,segment)
			travelled+=length_value
	if diorama.has_cursor:
		var point:Vector2=Vector2(diorama.cursor)*diorama.size;var radius:float=14.08*(.55 if int(diorama.hover)>=0 else 1)
		draw_arc(point,radius+2,0,TAU,32,Color(SplatUiTheme.INK,alpha*pin_k*.95),7,true)
		draw_arc(point,radius,0,TAU,32,Color(diorama._color if int(diorama.hover)>=0 else Color.WHITE,alpha*pin_k*.95),3,true)
