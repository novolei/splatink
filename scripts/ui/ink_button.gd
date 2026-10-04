class_name SplatInkButton
extends Button
## Original inkwave / 糖云街区 shader, with project-independent focus feedback.

const FACE: Shader = preload("res://assets/ui/ink_button.gdshader")
var ink_color: Color = SplatUiTheme.ORANGE
var primary: bool = false
var _face: ColorRect
var _material: ShaderMaterial
var _feedback: Tween
var source_layout: bool = false
var source_font: float = 21
var source_label: String = ""
var source_subtitle: String = ""
var source_icon: String = ""
var source_tilt: float = 0
var source_online:bool=false
var source_ghost:bool=false
var source_blocked:bool=false
var _source_words: Control
var _base_position: Vector2

static func make(value: String, callback: Callable, color: Color, is_primary: bool = false) -> SplatInkButton:
	var button := SplatInkButton.new()
	button.text = value
	button.ink_color = color
	button.primary = is_primary
	button.custom_minimum_size = Vector2(180, 66 if is_primary else 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button

func _ready() -> void:
	SplatSourceFeedback.attach(self,"ui_confirm" if source_label in ["PLAY","ONLINE","START!","DONE","REMATCH","CONTINUE","TRY IT","TO THE ROOM"] else "ui_click")
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override("font", SplatUiTheme.DISPLAY)
	add_theme_font_size_override("font_size", 26 if primary else 21)
	add_theme_color_override("font_color", _on_ink() if primary else Color.WHITE)
	add_theme_color_override("font_hover_color", _on_ink())
	add_theme_color_override("font_focus_color", _on_ink())
	add_theme_color_override("font_pressed_color", _on_ink())
	add_theme_color_override("font_outline_color", SplatUiTheme.INK)
	add_theme_constant_override("outline_size", 2)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_material = ShaderMaterial.new()
	_material.shader = FACE
	_material.set_shader_parameter("fill", Color.WHITE if primary or source_online else ink_color)
	_material.set_shader_parameter("bg", ink_color if primary or source_online else Color("141020"))
	_material.set_shader_parameter("dots",1.0 if source_online else 0.0)
	_material.set_shader_parameter("focus_accent",ink_color)
	_material.set_shader_parameter("stripes", 1.0 if primary else 0.0)
	_material.set_shader_parameter("blob", 0.0)
	_material.set_shader_parameter("focus", 0.0)
	if source_blocked:
		_material.set_shader_parameter("bg",Color("3b3352"));_material.set_shader_parameter("stripes",1.0);_material.set_shader_parameter("stripe_alpha",.06);_material.set_shader_parameter("stripe_period_px",30.72);_material.set_shader_parameter("stripe_width_px",15.36);_material.set_shader_parameter("ring_rest",Color(1,1,1,.7))
	if source_ghost:
		_material.set_shader_parameter("bg",Color(1,1,1,.07))
		_material.set_shader_parameter("lip_rest",Color.TRANSPARENT)
		_material.set_shader_parameter("ring_rest",Color(1,1,1,.14))
	_face = ColorRect.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.material = _material
	_face.z_index = 0
	add_child(_face)
	resized.connect(_layout)
	mouse_entered.connect(func() -> void: _focus(true))
	mouse_exited.connect(func() -> void: _focus(has_focus()))
	focus_entered.connect(func() -> void: _focus(true))
	focus_exited.connect(func() -> void: _focus(false))
	button_down.connect(func() -> void: _press(0.955))
	button_up.connect(func() -> void: _press(1.0))
	_layout()
	if source_layout:
		_base_position = position
		rotation = source_tilt
		_source_words = Control.new()
		_source_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_source_words)
		_source_words.modulate = Color.WHITE if source_blocked else _on_ink() if primary else Color.WHITE
		var font_u: float = source_font / 12.8
		var left: float = 1.8 if primary else 1.6
		if not source_icon.is_empty():
			SplatLabCanvas.icon(_source_words, source_icon, left, (size.y / 12.8 - font_u * 1.35) * .5, font_u * 1.35, font_u * 1.35)
			left += font_u * 1.35 + 1.1
		var text_h: float = font_u + (1.1 if not source_subtitle.is_empty() else 0.0)
		var top: float = (size.y / 12.8 - text_h) * .5
		var title: Label = SplatLabCanvas.label(_source_words, source_label, left, top, size.x / 12.8 - left - 1, font_u, font_u, false)
		title.add_theme_font_override("font", SplatUiTheme.DISPLAY)
		if not source_subtitle.is_empty(): SplatLabCanvas.label(_source_words, source_subtitle, left, top + font_u + .38, size.x / 12.8 - left - 1, 1.0, 1.1 if primary else .95)

func _process(_delta: float) -> void:
	if is_visible_in_tree() and primary and not source_blocked:
		_material.set_shader_parameter("stripe_phase", fposmod(Time.get_ticks_msec() * 0.000604, 1.0))
	if is_visible_in_tree() and source_online:
		_material.set_shader_parameter("dot_phase", Vector2(Time.get_ticks_msec()*.000667,-Time.get_ticks_msec()*.000334))

func _layout() -> void:
	if _face == null:
		return
	_face.position = Vector2(-24, -20)
	_face.size = size + Vector2(48, 48)
	_material.set_shader_parameter("quad_size", _face.size)
	_material.set_shader_parameter("body_pos", Vector2(24, 20))
	_material.set_shader_parameter("body_size", size)
	_material.set_shader_parameter("radius", 15.36 if source_layout else 17.0)
	pivot_offset = size * 0.5

func _focus(on: bool) -> void:
	if disabled:
		return
	if _feedback != null:
		_feedback.kill()
	var pointer: Vector2 = get_local_mouse_position() / Vector2(maxf(size.x, 1), maxf(size.y, 1))
	_material.set_shader_parameter("blob_origin", pointer.clamp(Vector2.ZERO, Vector2.ONE))
	_feedback = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_feedback.tween_method(func(value: float) -> void: _material.set_shader_parameter("blob", value), float(_material.get_shader_parameter("blob")), 1.0 if on else 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_feedback.tween_method(func(value: float) -> void: _material.set_shader_parameter("focus", value), float(_material.get_shader_parameter("focus")), 1.0 if on else 0.0, 0.25)
	_feedback.tween_property(self, "scale", Vector2.ONE * ((1.045 if source_layout else 1.025) if on else 1.0), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if source_layout:
		_feedback.tween_property(self, "rotation", 0.0 if on else source_tilt, .42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_feedback.tween_property(self, "position", _base_position + Vector2(8.96 if on else 0, 0), .42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _source_words != null: _source_words.modulate = SplatUiTheme.INK if on and (primary or source_online or ink_color.get_luminance() > .36) else Color.WHITE if source_blocked else _on_ink() if primary else Color.WHITE

func _press(factor: float) -> void:
	create_tween().set_ignore_time_scale(true).tween_property(self, "scale", Vector2.ONE * factor, 0.08)

func _on_ink() -> Color:
	return SplatUiTheme.INK if ink_color.get_luminance() > 0.36 else Color.WHITE

func set_source_label(value:String)->void:
	source_label=value
	if _source_words:
		for child:Node in _source_words.get_children():
			if child is Label:(child as Label).text=value;return

func set_source_ghost()->void:
	source_ghost=true
	if _material:
		_material.set_shader_parameter("bg",Color(1,1,1,.07))
		_material.set_shader_parameter("lip_rest",Color.TRANSPARENT)
		_material.set_shader_parameter("ring_rest",Color(1,1,1,.14))
