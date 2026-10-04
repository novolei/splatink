class_name SplatSettingToggle
extends Button
signal changed(value:bool)
const C=preload("res://scripts/ui/lab_canvas.gd")
var on:bool=false
var _face:Control
var _knob:Control
var _label:Label
func _ready()->void:
	for state:String in ["normal","focus","hover","pressed"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	_face=C.panel(self,0,0,7,2.7,Color("100d1a"),1.35)
	_knob=C.panel(self,.3,.3,2.1,2.1,Color.WHITE,1.05)
	_label=C.label(self,"",.3,.2,6.4,2.3,.95,false,SplatUiTheme.INK)
	_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	pressed.connect(func()->void:set_on(not on,true);changed.emit(on))
	set_on(on)
func set_on(value:bool,animate:bool=false)->void:
	on=value
	if not _face:return
	(_face.material as ShaderMaterial).set_shader_parameter("top_color",SplatUiTheme.ORANGE if on else Color("100d1a"))
	(_face.material as ShaderMaterial).set_shader_parameter("bottom_color",SplatUiTheme.ORANGE if on else Color("100d1a"))
	_label.text="ON" if on else "OFF";_label.add_theme_color_override("font_color",SplatUiTheme.INK if on else Color("bdb3d3"))
	_label.position.x=.3*12.8 if on else 2.3*12.8;_label.size.x=4.4*12.8
	var x:float=4.6*12.8 if on else .3*12.8
	if animate:
		create_tween().tween_property(_knob,"position:x",x,.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:_knob.position.x=x
