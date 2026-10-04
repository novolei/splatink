class_name SplatNameField
extends LineEdit
## Source _nameRow commit/cancel boundary: changing text does not save a partial name.
signal committed(value:String)
var host:InkUI
var _original:String=""
var _cancelled:bool=false
func _ready()->void:
	add_theme_constant_override("minimum_character_width",0);max_length=16
	_original=text
	add_theme_font_override("font",SplatUiTheme.DISPLAY)
	add_theme_font_size_override("font_size",20)
	add_theme_color_override("font_color",Color.WHITE)
	add_theme_color_override("font_selected_color",SplatUiTheme.INK)
	add_theme_color_override("caret_color",SplatUiTheme.ORANGE)
	add_theme_color_override("selection_color",Color("ffcc97"))
	add_theme_stylebox_override("normal",_box(Color(1,1,1,.07),Color.TRANSPARENT,0))
	add_theme_stylebox_override("focus",_box(Color.WHITE,SplatUiTheme.ORANGE,3))
	focus_entered.connect(func()->void:
		_original=text;_cancelled=false;add_theme_color_override("font_color",SplatUiTheme.INK)
		select_all.call_deferred())
	focus_exited.connect(_commit)
	text_submitted.connect(func(_value:String)->void:release_focus())
func _box(color:Color,outline:Color,width:int)->StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=outline
	box.set_border_width_all(width);box.set_corner_radius_all(10)
	box.content_margin_left=roundi(.9*12.8);box.content_margin_right=roundi(2.8*12.8)
	return box
func _gui_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:
			_cancelled=true;text=_original;release_focus();accept_event()
		elif event.keycode in [KEY_UP,KEY_DOWN,KEY_TAB]:release_focus();accept_event()
func _commit()->void:
	add_theme_color_override("font_color",Color.WHITE)
	if _cancelled:text=_original;_sound("ui_back");return
	var expression:=RegEx.new();expression.compile("\\s+")
	var value:String=expression.sub(text," ",true).strip_edges().left(16)
	if value.is_empty():
		text=_original;_sound("ui_error")
		var tween:Tween=create_tween();var origin:Vector2=position
		for shift:float in [6,-5,4,-3,0]:tween.tween_property(self,"position",origin+Vector2(shift,0),.06)
		return
	text=value
	if value==_original:return
	_original=value
	if is_instance_valid(host):host.profile.name=value;host.save_profile()
	committed.emit(value);_sound("ui_confirm")
	pivot_offset=size*.5
	var tween:Tween=create_tween();tween.tween_property(self,"scale",Vector2.ONE*1.03,.12)
	tween.tween_property(self,"scale",Vector2.ONE,.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
func _sound(id:String)->void:
	if is_instance_valid(host) and is_instance_valid(host.main) and host.main.get("audio")!=null:host.main.audio.play(id)
