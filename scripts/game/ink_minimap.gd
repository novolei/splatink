class_name InkMinimap
extends Node

# Original Minimap._build/_drawBase is baked by tools/export_minimap.mjs.
# Only the original quarter-metre ownership field crosses the CPU/GPU boundary.
const Live = preload("res://scripts/game/ink_minimap_live.gd")
const InkShader = preload("res://assets/minimap/ink.gdshader")
const PX_PER_M: float = 7.0
const REFRESH: float = 0.15
const FLASH_LIFE: float = 0.45
const EFFECT_CAPACITY: int = 40

var stage: Node
var game: Node
var bounds: Dictionary = {}
var metadata: Dictionary = {}
var width: int = 350
var height: int = 616
var viewer_team: int = 0
var flip: bool = false
var time: float = 0.0
var flash_time: float = 9.0
var effects: Array[Dictionary] = []
var _viewport: SubViewport
var _surface: ColorRect
var _live: Control
var _material: ShaderMaterial
var _grid_now: ImageTexture
var _grid_before: ImageTexture
var _snapshot: PackedByteArray = PackedByteArray()
var _grid_hash: int = -1
var _grid_width: int = 512
var _grid_height: int = 1
var _timer: float = 0.0
var _theme: String = "day"
var _colors: Array[Color] = [Color("ff8a14"),Color("2f5bff")]
var _built: bool = false
var active: bool = true

func configure(stage_node: Node, controller: Node = null, team: int = 0) -> void:
	stage = stage_node
	game = controller
	viewer_team = clampi(team,0,1)
	flip = viewer_team == 1
	metadata = JSON.parse_string(FileAccess.get_file_as_string("res://data/minimap/%s.json" % str(stage.get("stage_id"))))
	if metadata.is_empty():
		push_error("Original minimap metadata is missing")
		return
	bounds = metadata.bounds
	width = int(metadata.width)
	height = int(metadata.height)
	_grid_width = int(metadata.grid_width)
	_grid_height = ceili(float(int(metadata.grid_length)) / _grid_width)
	var source_grid: PackedByteArray = stage.get("grid")
	if source_grid.size() != int(metadata.grid_length):
		push_error("Minimap projection and source turf grid do not match")
		return
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "OriginalMapComposite"
		_viewport.disable_3d = true
		_viewport.transparent_bg = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.gui_disable_input = true
		add_child(_viewport)
		_surface = ColorRect.new()
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_material = ShaderMaterial.new()
		_material.shader = InkShader
		_surface.material = _material
		_viewport.add_child(_surface)
		_live = Live.new()
		_live.set("map",self)
		_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_viewport.add_child(_live)
	_viewport.size = Vector2i(width,height)
	_surface.size = Vector2(width,height)
	_live.size = Vector2(width,height)
	_material.set_shader_parameter("grid_size",Vector2(_grid_width,_grid_height))
	_material.set_shader_parameter("map_size",Vector2(width,height))
	_snapshot = _padded_grid(source_grid)
	_grid_now = ImageTexture.create_from_image(_grid_image(_snapshot))
	_grid_before = ImageTexture.create_from_image(_grid_image(_snapshot))
	_material.set_shader_parameter("grid_now",_grid_now)
	_material.set_shader_parameter("grid_before",_grid_before)
	_grid_hash = hash(source_grid)
	_built = true
	clear()
	_load_viewer()
	update(0.0,true)
	_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func set_active(value: bool) -> void:
	if value==active:return
	active=value
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if value and _built and is_instance_valid(stage):
		# Reopening a hidden map starts quietly with the latest field.
		var source_grid: PackedByteArray=stage.get("grid")
		_snapshot=_padded_grid(source_grid)
		_grid_hash=hash(source_grid)
		_grid_now.update(_grid_image(_snapshot))
		_grid_before.update(_grid_image(_snapshot))
		flash_time=9.0
		_material.set_shader_parameter("flash",0.0)
		_live.queue_redraw()

func _padded_grid(source: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result.resize(_grid_width*_grid_height)
	return result

func _grid_image(data: PackedByteArray) -> Image:
	return Image.create_from_data(_grid_width,_grid_height,false,Image.FORMAT_R8,data)

func _load_viewer() -> void:
	var record: Dictionary = metadata.viewers[viewer_team]
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(record.projection))
	if bytes.size() != width*height*16:
		push_error("Minimap cell projection has an unexpected size")
		return
	var image := Image.create_from_data(width,height,false,Image.FORMAT_RGBAF,bytes)
	_material.set_shader_parameter("cells",ImageTexture.create_from_image(image))
	_load_base()
	# A viewer change is an initial display, never a freshly painted white flash.
	_grid_before.update(_grid_image(_snapshot))
	flash_time = 9.0

func _load_base() -> void:
	var record: Dictionary = metadata.viewers[viewer_team]
	_material.set_shader_parameter("base_map",load(str(record.bases[_theme])))

func set_viewer_team(team: int) -> void:
	var next: int = clampi(team,0,1)
	if viewer_team == next or not _built:
		return
	viewer_team = next
	flip = viewer_team == 1
	_load_viewer()
	_live.queue_redraw()

func set_theme(value: String) -> void:
	var next: String = "sunset" if value in ["sunset","dusk"] else "day"
	if _theme != next:
		_theme = next
		if _built:
			_load_base()

func get_texture() -> Texture2D:
	return _viewport.get_texture() if is_instance_valid(_viewport) else null

func to_canvas(x: float,z: float) -> Vector2:
	var coordinate := Vector2((float(bounds.get("maxX",25))-x)*PX_PER_M,(float(bounds.get("maxZ",44))-z)*PX_PER_M)
	return Vector2(width,height)-coordinate if flip else coordinate

func to_uv(position_world: Vector3) -> Vector2:
	return to_canvas(position_world.x,position_world.z)/Vector2(width,height)

func world_at(pixel: Vector2) -> Vector3:
	var p := Vector2(width,height)-pixel if flip else pixel
	return Vector3(float(bounds.maxX)-p.x/PX_PER_M,0,float(bounds.maxZ)-p.y/PX_PER_M)

func update(dt: float, force: bool = false) -> void:
	if not active or not _built or not is_instance_valid(stage):
		return
	time += dt
	flash_time += dt
	_timer -= dt
	var source_colors: Array = stage.get("team_colors")
	if source_colors.size() >= 2:
		for i in 2:
			_colors[i] = source_colors[i]
			_material.set_shader_parameter("team_a" if i == 0 else "team_b",Vector3(_colors[i].r,_colors[i].g,_colors[i].b))
	if is_instance_valid(game):
		var options = game.get("options")
		if options is Dictionary:
			set_theme(str(options.get("time_of_day",options.get("timeOfDay","day"))))
	if force or _timer <= 0.0:
		_timer = REFRESH
		var source_grid: PackedByteArray = stage.get("grid")
		var current_hash: int = hash(source_grid)
		if current_hash != _grid_hash:
			_grid_before.update(_grid_image(_snapshot))
			_snapshot = _padded_grid(source_grid)
			_grid_now.update(_grid_image(_snapshot))
			_grid_hash = current_hash
			flash_time = 0.0
	_material.set_shader_parameter("flash",maxf(0.0,1.0-flash_time/FLASH_LIFE)*0.85)
	for index in range(effects.size()-1,-1,-1):
		effects[index].t += dt
		if float(effects[index].t) >= float(effects[index].life):
			effects.remove_at(index)
	_live.queue_redraw()

func clear() -> void:
	effects.clear()
	time = 0.0
	flash_time = 9.0
	_timer = 0.0
	if is_instance_valid(_live):
		_live.queue_redraw()

func _actor_team(actor, fallback: int = 0) -> int:
	return int(actor.get("team_id")) if is_instance_valid(actor) else fallback

func _push(kind: String, point: Vector3, team: int, radius: float, life: float, actor = null) -> void:
	if effects.size() >= EFFECT_CAPACITY:
		effects.pop_front()
	effects.append({"kind":kind,"pos":point,"team":clampi(team,0,1),"r":radius,"t":0.0,"life":life,"actor":actor})

func on_event(kind: String, data: Dictionary = {}) -> void:
	if not _built:
		return
	if is_instance_valid(game) and str(game.get("state")) != "playing":
		return
	var actor = data.get("actor")
	var event_position=data.get("pos")
	var point:Vector3=event_position if event_position is Vector3 else (actor.global_position if is_instance_valid(actor) and actor is Node3D else Vector3.ZERO)
	var team: int = int(data.get("team",_actor_team(actor)))
	match kind:
		"special:slam":
			_push("slam",point,team,float(data.get("radius",5.2)),0.9)
		"bomb:explode":
			_push("boom",point,team,float(data.get("radius",3.1)),0.7)
		"explosion":
			if str(data.get("kind")) == "bomb":
				_push("boom",point,team,float(data.get("radius",3.1)),0.7)
		"superjump":
			if str(data.get("phase")) == "flight":
				var target: Vector3 = data.get("to",point)
				if not data.has("to") and is_instance_valid(actor):
					var jump: Dictionary = actor.get("super_jump_state")
					target = jump.get("to",point)
				_push("jump",target,team,0.0,3.0,actor)
		"superjump:land":
			for effect in effects:
				if effect.kind == "jump" and effect.actor == actor:
					effect.life = minf(float(effect.life),float(effect.t)+0.35)
		"respawn":
			var pads: Array = (stage.get("layout") as Dictionary).get("spawnPads",[])
			if pads.size()>team:
				var p: Array = pads[team]
				point = Vector3(float(p[0]),float(p[1]),float(p[2]))
			_push("spawn",point,team,0.0,0.8)
		"splatted":
			var victim = data.get("victim")
			var attacker = data.get("attacker")
			if is_instance_valid(victim):
				_push("splat",victim.global_position,_actor_team(attacker,1-_actor_team(victim)),0.0,1.6)
