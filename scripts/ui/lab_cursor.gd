class_name SplatLabCursor
extends ColorRect
## Original Menu._updateCursor springs, for controls that do not draw their own focus ring.
var host:InkUI
var face:ShaderMaterial
var geometry:Vector4=Vector4.ZERO
var velocity:Vector4=Vector4.ZERO
var target:Vector4=Vector4.ZERO
var active:bool=false
var clock:float=0.0

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	face=ShaderMaterial.new();face.shader=preload("res://assets/ui/lab_cursor.gdshader");material=face
	color=Color.WHITE;hide()

func _process(dt:float)->void:
	if not is_instance_valid(host):return
	var focused:Control=get_viewport().gui_get_focus_owner()
	var want:bool=is_instance_valid(focused) and focused.is_visible_in_tree() and focused.has_meta("source_cursor") and bool(focused.get_meta("source_cursor")) and focused.modulate.a>.6
	if not want:active=false;hide();return
	var rect:Rect2=focused.get_global_rect()
	var pad:float=float(focused.get_meta("source_cursor_pad",7.0))
	target=Vector4(rect.position.x-pad,rect.position.y-pad,rect.size.x+pad*2.0,rect.size.y+pad*2.0)
	if not active or bool(host.settings.reduce_motion):geometry=target;velocity=Vector4.ZERO
	else:
		var steps:int=mini(8,maxi(1,ceili(dt*120.0)))
		var step:float=minf(dt,.1)/float(steps)
		for index:int in steps:
			velocity+=(560.0*(target-geometry)-34.0*velocity)*step
			geometry+=velocity*step
	active=true;show();clock+=dt
	face.set_shader_parameter("viewport_size",size)
	face.set_shader_parameter("cursor_rect",geometry)
	face.set_shader_parameter("radius",float(focused.get_meta("source_cursor_radius",12.8))*focused.get_global_transform().get_scale().x+pad)
	face.set_shader_parameter("pulse_time",clock)
	face.set_shader_parameter("reduce_motion",bool(host.settings.reduce_motion))
