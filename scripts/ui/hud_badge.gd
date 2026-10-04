class_name SplatHudBadge
extends Control
const PATH := "M32 2.5 C35.5 2.5 43 9 47.5 14.5 C50 14 55 15.5 57 18.5 C58.6 21 57.4 23.6 55.2 24.8 A24.5 24.5 0 1 1 8.8 24.8 C6.6 23.6 5.4 21 7 18.5 C9 15.5 14 14 16.5 14.5 C21 9 28.5 2.5 32 2.5 Z"
static var cache: Dictionary = {}
var _shape: TextureRect
var _weapon: TextureRect
var _dead: Label
var _respawn: Label
var _self: Label
var _last: String = ""
var _spark:ColorRect
var _ring:ColorRect
var _special_ready:bool=false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark=ColorRect.new();add_child(_spark);SplatLabCanvas.at(_spark,-1.08,-1.08,5.76,5.76);_spark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var spark_material:=ShaderMaterial.new();spark_material.shader=preload("res://assets/ui/lab_badge_spark.gdshader");_spark.material=spark_material;_spark.hide()
	_shape = TextureRect.new(); _shape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; _shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_shape)
	_weapon = SplatLabCanvas.icon(self, "weaponw_shooter", .68, 1.3, 2.23, 1.83)
	_dead = SplatLabCanvas.label(self, "×", .7, .7, 2.2, 2.2, 2.0, true); _dead.hide()
	_ring=ColorRect.new();add_child(_ring);SplatLabCanvas.at(_ring,.25,.25,3.1,3.1);_ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var ring_material:=ShaderMaterial.new();ring_material.shader=preload("res://assets/ui/lab_respawn.gdshader");_ring.material=ring_material;_ring.hide()
	move_child(_dead,get_child_count()-1)
	_respawn = SplatLabCanvas.label(self, "", 2.8, 2.8, 1.0, 1, .8, true)
	_self = SplatLabCanvas.label(self, "▾", 1.15, 3.7, 1.3, 1, .75); _self.hide()
func update_badge(player: Dictionary, color: Color) -> void:
	var alive: bool = bool(player.get("alive", true))
	var weapon: String = str(player.get("weapon", "shooter"))
	_special_ready=alive and float(player.get("special",0))>=.98
	_spark.visible=_special_ready;(_spark.material as ShaderMaterial).set_shader_parameter("ink",color.lightened(.4))
	_ring.visible=not alive;(_ring.material as ShaderMaterial).set_shader_parameter("progress",1.0-float(player.get("respawn",0))/5)
	var signature: String = "%s/%s/%s/%s/%s" % [weapon, alive, ceili(float(player.get("respawn", 0))), player.get("isSelf", false), color]
	if signature == _last: return
	_last = signature
	var fill: Color = color if alive else Color("4a4458")
	var key: String = fill.to_html(false)
	if not cache.has(key):
		var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path d="%s" fill="none" stroke="#15121c" stroke-width="7" stroke-linejoin="round"/><path d="%s" fill="#%s" stroke="white" stroke-width="3" stroke-linejoin="round"/><path d="M17 30 Q20 22 28 19" fill="none" stroke="white" stroke-opacity=".55" stroke-width="3.5" stroke-linecap="round"/></svg>' % [PATH, PATH, key]
		var image := Image.new(); image.load_svg_from_string(svg); cache[key] = ImageTexture.create_from_image(image)
	_shape.texture = cache[key]
	var path: String = "res://assets/ui/source/weaponw_%s.svg" % weapon
	if ResourceLoader.exists(path): _weapon.texture = load(path) as Texture2D
	_weapon.modulate.a = 1.0 if alive else .35
	_dead.visible = not alive
	_respawn.text = str(ceili(float(player.get("respawn", 0)))) if not alive else ""
	_self.visible = bool(player.get("isSelf", false))
func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	if _self.visible: _self.position.y = (3.7 + .08 * sin(Time.get_ticks_msec() * .0044)) * 12.8
	if _special_ready:
		_shape.modulate=Color(1.0,1.0,1.0,1.0)*(1.0+.18*(.5+.5*sin(Time.get_ticks_msec()*.0057)))
		_shape.position.y=-.15*12.8*(.5+.5*sin(Time.get_ticks_msec()*.0057))
	else:_shape.modulate=Color.WHITE;_shape.position.y=0
