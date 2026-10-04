class_name InkSheetPool
extends MultiMeshInstance3D

var capacity: int = 64
var _sheets: Array[Dictionary] = []
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []

func initialize(limit: int = 64) -> void:
	capacity = limit
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 16
	sphere.rings = 8
	multimesh.mesh = sphere
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fx_sheet.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func set_lighting(light:Dictionary) -> void:
	var material:ShaderMaterial=material_override
	material.set_shader_parameter("sun_direction",light.sun_direction)
	for key in ["sun_color","sky_color"]:material.set_shader_parameter(key,(light[key] as Color).linear_to_srgb())

func sheet(position: Vector3, normal: Vector3, color: Color, start: float, radius: float, life: float = 0.3, crown: float = 0.0, stretch: Vector3 = Vector3.ONE) -> void:
	if _sheets.size() >= capacity: return
	var axis: Vector3 = normal.normalized() if normal.length_squared() > 0.1 else Vector3.UP
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var tangent: Vector3 = reference.cross(axis).normalized()
	_sheets.append({"p": position, "basis": Basis(tangent, axis.cross(tangent), axis), "color": color, "start": start, "radius": radius, "life": life, "age": 0.0, "seed": randf(), "crown": crown, "stretch": stretch})

func update(delta: float) -> void:
	if capture_render_packets:render_packets.clear()
	for index: int in range(_sheets.size() - 1, -1, -1):
		_sheets[index].age += delta
		if float(_sheets[index].age) >= float(_sheets[index].life):
			_sheets[index] = _sheets.back()
			_sheets.pop_back()
	for index: int in _sheets.size():
		var sheet: Dictionary = _sheets[index]
		var age: float = float(sheet.age) / maxf(0.03, float(sheet.life))
		var radius: float = lerpf(float(sheet.start), float(sheet.radius), 1.0 - pow(1.0 - age, 3.0))
		multimesh.set_instance_transform(index, Transform3D((sheet.basis as Basis).scaled((sheet.stretch as Vector3) * radius), sheet.p as Vector3))
		multimesh.set_instance_color(index, sheet.color as Color)
		if capture_render_packets:render_packets.append({"color":sheet.color})
		multimesh.set_instance_custom_data(index, Color(age, float(sheet.seed), 0.20, float(sheet.crown)))
	multimesh.visible_instance_count = _sheets.size()

func clear() -> void:
	_sheets.clear()
	render_packets.clear()
	if multimesh != null: multimesh.visible_instance_count = 0
