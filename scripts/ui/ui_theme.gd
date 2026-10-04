class_name SplatUiTheme
extends RefCounted
## Sugar Cloud / 糖云街区: native adaptation of Mini Tanks' inkwave theme.

const INK := Color("15121c")
const PANEL := Color("261f3a")
const MUTED := Color("c3bdd6")
const ORANGE := Color("ff8a14")
const BLUE := Color("2f5bff")
const GOLD := Color("ffd54a")
const MINT := Color("3ddc84")
const DISPLAY: Font = preload("res://assets/fonts/ink_display_font.tres")
const BODY: Font = preload("res://assets/fonts/ink_body_600_font.tres")
const THEME: Theme = preload("res://resources/themes/sugar_cloud.tres")
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/themes/source_catalog.json"))
		if parsed is Dictionary:
			_catalog = parsed as Dictionary
	return _catalog

static func text(value: String, pixels: int = 24, display: bool = false, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", DISPLAY if display else BODY)
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_constant_override("outline_size", maxi(2, roundi(pixels * 0.17)))
		label.add_theme_color_override("font_outline_color", INK)
		label.add_theme_color_override("font_shadow_color", INK)
		label.add_theme_constant_override("shadow_offset_y", roundi(pixels * 0.085))
	return label

static func body(value: String, pixels: int = 21) -> Label:
	var label: Label = text(value, pixels)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func panel(color: Color = PANEL, padding: int = 22) -> PanelContainer:
	var node := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = INK
	box.set_border_width_all(4)
	box.set_corner_radius_all(20)
	box.shadow_color = Color(INK, 0.8)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 8)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	node.add_theme_stylebox_override("panel", box)
	return node

static func vbox(gap: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

static func hbox(gap: int = 14) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

static func button(value: String, callback: Callable, color: Color = ORANGE, primary: bool = false) -> SplatInkButton:
	return SplatInkButton.make(value, callback, color, primary)

static func enter(node: Control, delay: float = 0.0) -> void:
	node.modulate.a = 0.0
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * 0.94
	var tween: Tween = node.create_tween().set_ignore_time_scale(true)
	tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, 0.24)
	tween.parallel().tween_property(node, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func safe_rect(view: Vector2) -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, view)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var window: Vector2 = Vector2(DisplayServer.window_get_size())
	if safe.size.x <= 0 or safe.size.y <= 0 or window.x <= 0:
		return Rect2(Vector2.ZERO, view)
	var ratio: Vector2 = view / window
	return Rect2(Vector2(safe.position) * ratio, Vector2(safe.size) * ratio)

static func touch() -> bool:
	return OS.has_feature("mobile") or "--touch-sim" in OS.get_cmdline_user_args()
