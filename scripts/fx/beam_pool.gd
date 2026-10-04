class_name InkBeamPool
extends MultiMeshInstance3D

var capacity: int = 64
var _beams: Array[Dictionary] = []
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []

func initialize(limit: int = 64) -> void:
	capacity = limit
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	multimesh.mesh = cylinder
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fx_beam.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func line(from: Vector3, to: Vector3, color: Color, width: float = 0.06, life: float = 0.35, charge: float = 1.0, sight: bool = false) -> void:
	if _beams.size() >= capacity or from.distance_squared_to(to) < 0.0001:
		return
	var axis: Vector3 = (to - from).normalized()
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var tangent: Vector3 = reference.cross(axis).normalized()
	_beams.append({"p": from.lerp(to, 0.5), "basis": Basis(tangent, axis, tangent.cross(axis)), "width": width, "length": from.distance_to(to), "color": color, "life": maxf(0.03, life), "age": 0.0, "charge": charge, "sight": sight})

func update(dt: float) -> void:
	if capture_render_packets:render_packets.clear()
	for i in range(_beams.size() - 1, -1, -1):
		_beams[i]["age"] += dt
		if float(_beams[i]["age"]) >= float(_beams[i]["life"]):
			_beams[i] = _beams.back()
			_beams.pop_back()
	for i in range(_beams.size()):
		var beam: Dictionary = _beams[i]
		var age: float = float(beam["age"]) / float(beam["life"])
		var width: float = float(beam["width"]) * (1.0 - age * 0.45)
		multimesh.set_instance_transform(i, Transform3D((beam["basis"] as Basis).scaled(Vector3(width, float(beam["length"]), width)), beam["p"]))
		multimesh.set_instance_color(i, beam["color"])
		if capture_render_packets:render_packets.append({"color":beam["color"]})
		multimesh.set_instance_custom_data(i, Color(age, float(beam["charge"]), 1.0 if bool(beam["sight"]) else 0.0, 1.0))
	multimesh.visible_instance_count = _beams.size()

func clear() -> void:
	_beams.clear()
	render_packets.clear()
	if multimesh:
		multimesh.visible_instance_count = 0
