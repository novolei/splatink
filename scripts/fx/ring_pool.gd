class_name InkRingPool
extends MultiMeshInstance3D

var capacity: int = 160
var _rings: Array[Dictionary] = []
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []

func initialize(limit: int = 160) -> void:
	capacity = limit
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	multimesh.mesh = quad
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fx_ring.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func ring(position: Vector3, normal: Vector3, color: Color, radius: float = 1.5, life: float = 0.35, thickness: float = 1.0) -> void:
	if _rings.size() >= capacity: return
	var axis: Vector3 = normal.normalized() if normal.length_squared() > 0.1 else Vector3.UP
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var tangent: Vector3 = reference.cross(axis).normalized()
	_rings.append({"p": position + axis * 0.025, "basis": Basis(tangent, axis.cross(tangent), axis), "color": color, "radius": radius, "life": maxf(0.03, life), "age": 0.0, "width": thickness, "seed": randf()})

func update(delta: float) -> void:
	if capture_render_packets:render_packets.clear()
	for index: int in range(_rings.size() - 1, -1, -1):
		_rings[index].age += delta
		if float(_rings[index].age) >= float(_rings[index].life):
			_rings[index] = _rings.back()
			_rings.pop_back()
	for index: int in _rings.size():
		var ring: Dictionary = _rings[index]
		var age: float = float(ring.age) / float(ring.life)
		var radius: float = float(ring.radius) * (0.12 + 0.88 * (1.0 - pow(1.0 - age, 3.0)))
		multimesh.set_instance_transform(index, Transform3D((ring.basis as Basis).scaled(Vector3.ONE * radius), ring.p as Vector3))
		multimesh.set_instance_color(index, ring.color as Color)
		if capture_render_packets:render_packets.append({"color":ring.color})
		multimesh.set_instance_custom_data(index, Color(age, float(ring.width), float(ring.seed), pow(1.0 - age, 1.4)))
	multimesh.visible_instance_count = _rings.size()

func clear() -> void:
	_rings.clear()
	render_packets.clear()
	if multimesh != null: multimesh.visible_instance_count = 0
