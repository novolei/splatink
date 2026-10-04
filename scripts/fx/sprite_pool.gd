class_name InkSpritePool
extends MultiMeshInstance3D

## Reusable fixed records and a single draw call for each of the original puff/glow render paths.
var capacity: int = 384
var _records: Array[Dictionary] = []
var _free: Array[int] = []
var _active: Array[int] = []
var _additive: bool = false
## Explicit contract capture: headless dummy RenderingServer cannot read MultiMesh uploads back.
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []

func initialize(limit: int = 384, additive: bool = false) -> void:
	capacity = limit
	_additive = additive
	_records.clear()
	_free.clear()
	_active.clear()
	render_packets.clear()
	for i in range(limit):
		_records.append({"p": Vector3.ZERO, "v": Vector3.ZERO, "color": Color.WHITE, "start": 0.1, "end": 0.2, "life": 1.0, "age": 0.0, "alpha": 1.0, "drag": 2.2, "buoyancy": 0.0, "kind": 0.0, "fade_in": 0.08, "spin": 1.2, "rotation": 0.0, "seed": 0.5, "wobble": 0.0, "fade_out": 0.0})
		_free.append(i)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	# Original makeQuadGeo uses -0.5..0.5; size is the full billboard width.
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fx_glow.gdshader") if additive else preload("res://assets/shaders/fx_sprite.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func _random() -> float:
	return randf()

func sprite(p: Vector3, velocity: Vector3, color: Color, start: float, finish: float, life: float, alpha: float = 1.0, kind: float = 0.0, drag: float = 2.2, buoyancy: float = 0.0, fade_in: float = 0.08, spin: float = 1.2, wobble: float = 0.0, fade_out: float = 0.0) -> void:
	if capacity <= 0:return
	var full: bool = _free.is_empty()
	# Original _sprite replaces a random live slot at capacity, keeping the burst visible.
	var id: int = _active[mini(capacity-1,floori(_random()*capacity))] if full else _free.pop_back()
	var record: Dictionary = _records[id]
	var fields := PackedFloat32Array([start,finish,life,alpha,kind,drag,buoyancy,fade_in,(_random()*TAU if _additive or kind != 3.0 else 0.0),(_random()-.5)*spin,_random(),wobble,fade_out])
	record["p"] = p
	record["v"] = velocity
	record["color"] = color
	record["start"] = fields[0]
	record["end"] = fields[1]
	record["life"] = fields[2]
	record["age"] = 0.0
	record["alpha"] = fields[3]
	record["kind"] = fields[4]
	record["drag"] = fields[5]
	record["buoyancy"] = fields[6]
	record["fade_in"] = fields[7]
	record["rotation"] = fields[8]
	record["spin"] = fields[9]
	record["seed"] = fields[10]
	record["wobble"] = fields[11]
	record["fade_out"] = fields[12]
	if not full:_active.append(id)

func update(dt: float, camera: Camera3D) -> void:
	if not camera:
		return
	if capture_render_packets:render_packets.clear()
	var i: int = 0
	while i < _active.size():
		var record: Dictionary = _records[_active[i]]
		# Vector2's float32 component preserves the original Float32Array assignment.
		record["age"] = Vector2(float(record["age"])+dt,0).x
		if float(record["age"]) >= float(record["life"]):
			_free.append(_active[i])
			_active[i] = _active.back()
			_active.pop_back()
			continue
		var damping: float = maxf(0.0,1.0-float(record["drag"])*dt)
		var v: Vector3 = record["v"]
		v=Vector3(v.x*damping,v.y*damping+float(record["buoyancy"])*dt,v.z*damping)
		if float(record["wobble"])>0:
			var phase: float=float(record["age"])*2.1+float(record["seed"])*40.0
			var push: float=float(record["wobble"])*dt*2.4
			v=Vector3(v.x+cos(phase)*push,v.y,v.z+sin(phase*.83)*push)
		record["v"]=v
		var p: Vector3=record["p"]
		record["p"]=Vector3(p.x+v.x*dt,p.y+v.y*dt,p.z+v.z*dt)
		record["rotation"]=Vector2(float(record["rotation"])+float(record["spin"])*dt,0).x
		i+=1
	for draw_index in range(_active.size()):
		var record: Dictionary = _records[_active[draw_index]]
		var fraction: float = float(record["age"]) / float(record["life"])
		var remain: float=1.0-fraction
		var size: float = float(record["start"])+(float(record["end"])-float(record["start"]))* (1.0-remain*remain*remain)
		var rotation: float = float(record["rotation"])
		var right: Vector3 = camera.global_basis.x * cos(rotation) + camera.global_basis.y * sin(rotation)
		var up: Vector3 = -camera.global_basis.x * sin(rotation) + camera.global_basis.y * cos(rotation)
		var transform:=Transform3D(Basis(right * size, up * size, camera.global_basis.z * size), record["p"])
		multimesh.set_instance_transform(draw_index,transform)
		multimesh.set_instance_color(draw_index, record["color"])
		var fade: float=minf(1.0,(float(record["life"])-float(record["age"]))/float(record["fade_out"])) if float(record["fade_out"])>0 else (remain if _additive else 1.0-fraction*fraction)
		var alpha: float = float(record["alpha"])*fade
		if float(record["fade_in"]) > 0.0:
			alpha *= minf(1.0,float(record["age"])/float(record["fade_in"]))
		var custom:=Color(fraction,float(record["seed"]),float(record["kind"]),alpha)
		multimesh.set_instance_custom_data(draw_index,custom)
		if capture_render_packets:render_packets.append({"transform":transform,"custom":custom,"color":record["color"]})
	multimesh.visible_instance_count = _active.size()

func clear() -> void:
	for id in _active:
		_free.append(id)
	_active.clear()
	render_packets.clear()
	if multimesh:
		multimesh.visible_instance_count = 0
