class_name SplatLabCanvas
extends Control
## Source CSS uses --u=min(1vw,1.7778vh). Geometry below is expressed in u.
signal layout_changed
static func defer_focus(node:Control)->void:
	(func()->void:
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():node.grab_focus()
	).call_deferred()
var canvas: Control
var width_u: float = 100.0
var height_u: float = 56.25
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	resized.connect(_layout)
	_layout()
func _layout() -> void:
	if canvas == null: return
	var scale_factor: float = minf(size.x / 100.0, size.y / 56.25) / 12.8
	if scale_factor <= 0: return
	canvas.scale = Vector2.ONE * scale_factor
	canvas.size = size / scale_factor
	width_u = canvas.size.x / 12.8
	height_u = canvas.size.y / 12.8
	layout_changed.emit()
static func at(node: Control, x: float, y: float, w: float, h: float) -> Control:
	node.position = Vector2(x, y) * 12.8
	node.size = Vector2(w, h) * 12.8
	return node

static func keycap(parent:Node,key:String,x:float,y:float,fs:float=.9,pad:bool=false)->float:
	var w:float=maxf(fs*1.6,SplatUiTheme.BODY.get_string_size(key,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*.88*12.8)).x/12.8+fs*.7)
	var h:float=fs*1.75
	if key in ["LMB","RMB","MOUSE"]:
		icon(parent,"mouse_%s"%("L" if key=="LMB" else "R" if key=="RMB" else "M"),x,y-.3,fs*2.1,fs*2.4)
		return fs*2.3
	if pad:
		var face:bool=key in ["A","B","X","Y"]
		var stick:bool=key in ["LS","RS"]
		var system:bool=key in ["View","Start","DPad"]
		var color:Color=Color("3cbd62") if key=="A" else Color("e95b62") if key=="B" else Color("4399e7") if key=="X" else Color("efbb34") if key=="Y" else Color.WHITE
		w=fs*2.1 if face or stick or system else maxf(fs*2.3,w);h=fs*2.35 if key in ["LT","RT"] else fs*2.1
		var plate:Control=panel(parent,x,y,w,h,color,w*.5 if face or stick or system else .6)
		(plate.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.INK);(plate.material as ShaderMaterial).set_shader_parameter("border",2)
		if system:icon(plate,"pad_"+key,w*.19,h*.19,w*.62,h*.62).modulate=SplatUiTheme.INK
		else:label(plate,key[0] if stick else key,0,0,w,h,fs*.95,false,Color.WHITE if face else SplatUiTheme.INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	else:
		var plate:Control=panel(parent,x,y,w,h,Color.WHITE,.35)
		(plate.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.INK);(plate.material as ShaderMaterial).set_shader_parameter("border",2)
		label(plate,key,0,-.02,w,h,fs*.88,false,SplatUiTheme.INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return w+.22*fs
static func label(parent: Node, value: String, x: float, y: float, w: float, h: float, fs: float = 1.0, display: bool = false, color: Color = Color.WHITE) -> Label:
	var node: Label = SplatUiTheme.text(value, roundi(fs * 12.8), display, color)
	node.clip_text = not display
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(node)
	at(node, x, y, w, h)
	return node
static func image(parent: Node, path: String, x: float, y: float, w: float, h: float) -> TextureRect:
	var node := TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path): node.texture = load(path) as Texture2D
	parent.add_child(node)
	at(node, x, y, w, h)
	return node
static func icon(parent: Node, id: String, x: float, y: float, w: float, h: float) -> TextureRect:
	return image(parent, "res://assets/ui/source/%s.svg" % id, x, y, w, h)
static func panel(parent: Node, x: float, y: float, w: float, h: float, color: Color = Color.TRANSPARENT, radius: float = 1.5) -> Control:
	var node := ColorRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := ShaderMaterial.new()
	face.shader = preload("res://assets/ui/lab_panel.gdshader")
	face.set_shader_parameter("panel_size", Vector2(w, h) * 12.8)
	face.set_shader_parameter("radius", radius * 12.8)
	if color.a > 0:
		face.set_shader_parameter("top_color", color)
		face.set_shader_parameter("bottom_color", color)
	face.set_shader_parameter("border", 1.2)
	node.material = face
	parent.add_child(node)
	at(node, x, y, w, h)
	return node
static func bar(parent: Node, x: float, y: float, w: float, h: float, fraction: float, color: Color) -> Control:
	var node: Control = panel(parent, x, y, w, h, Color("0f0b18"), h * 0.5)
	panel(node, 0, 0, w * clampf(fraction, 0, 1), h, color, h * 0.5)
	return node
static func button(parent: Node, value: String, callback: Callable, x: float, y: float, w: float, h: float, fs: float = 1.7, icon_id: String = "", subtitle: String = "", primary: bool = false, color: Color = SplatUiTheme.ORANGE, tilt: float = 0) -> SplatInkButton:
	var node := SplatInkButton.make("", callback, color, primary)
	node.source_layout = true
	node.source_online=value=="ONLINE"
	node.source_font = fs * 12.8
	node.source_label = value
	node.source_subtitle = subtitle
	node.source_icon = icon_id
	node.source_tilt = deg_to_rad(tilt)
	node.custom_minimum_size = Vector2.ZERO
	at(node, x, y, w, h)
	parent.add_child(node)
	return node
static func tile(parent: Node, callback: Callable, x: float, y: float, w: float, h: float, selected: bool = false,source_style:String="") -> Button:
	var node := Button.new()
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]: node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	at(node, x, y, w, h)
	parent.add_child(node)
	var face: Control = panel(node, 0, 0, w, h, Color("171320"), 1.1)
	face.z_index = 0
	if source_style=="setting":
		node.set_meta("source_cursor",true);node.set_meta("source_cursor_radius",12.8)
		(face.material as ShaderMaterial).set_shader_parameter("top_color",Color(1,1,1,.035));(face.material as ShaderMaterial).set_shader_parameter("bottom_color",Color(1,1,1,.035));(face.material as ShaderMaterial).set_shader_parameter("border_color",Color.TRANSPARENT);(face.material as ShaderMaterial).set_shader_parameter("border",0.0)
	if selected: (face.material as ShaderMaterial).set_shader_parameter("border_color", SplatUiTheme.ORANGE); (face.material as ShaderMaterial).set_shader_parameter("border", 2.5)
	var focus: Control = panel(node, -.25, -.25, w + .5, h + .5, Color(0, 0, 0, 0), 1.3)
	focus.z_index=10
	(focus.material as ShaderMaterial).set_shader_parameter("top_color", Color(0, 0, 0, 0))
	(focus.material as ShaderMaterial).set_shader_parameter("bottom_color", Color(0, 0, 0, 0))
	(focus.material as ShaderMaterial).set_shader_parameter("border_color", Color.WHITE)
	(focus.material as ShaderMaterial).set_shader_parameter("border", 2.5)
	focus.hide()
	var orange:Control=panel(node,-.7,-.7,w+1.4,h+1.4,Color.TRANSPARENT,1.55);orange.z_index=9
	(orange.material as ShaderMaterial).set_shader_parameter("top_color",Color.TRANSPARENT);(orange.material as ShaderMaterial).set_shader_parameter("bottom_color",Color.TRANSPARENT);(orange.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.ORANGE);(orange.material as ShaderMaterial).set_shader_parameter("border",4.5);orange.hide()
	if source_style=="setting":
		at(focus,0,0,w,h);(focus.material as ShaderMaterial).set_shader_parameter("panel_size",focus.size);(focus.material as ShaderMaterial).set_shader_parameter("top_color",Color(SplatUiTheme.ORANGE,.14));(focus.material as ShaderMaterial).set_shader_parameter("bottom_color",Color(SplatUiTheme.ORANGE,.14));(focus.material as ShaderMaterial).set_shader_parameter("border",0.0);focus.z_index=0
	node.pivot_offset=node.size*.5
	var original_position:Vector2=node.position
	node.focus_entered.connect(func() -> void:
		focus.show();orange.visible=source_style!="setting";node.z_index=2
		if source_style=="setting":node.create_tween().tween_property(node,"position:x",original_position.x+4.48,.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.create_tween().tween_property(node,"scale",Vector2.ONE*(1.0 if source_style=="setting" else 1.035),.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	node.focus_exited.connect(func() -> void:
		focus.hide();orange.hide();node.z_index=0
		if source_style=="setting":node.create_tween().tween_property(node,"position:x",original_position.x,.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.create_tween().tween_property(node,"scale",Vector2.ONE,.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	node.pressed.connect(callback)
	SplatSourceFeedback.attach(node,"ui_click" if selected else "ui_confirm")
	return node
