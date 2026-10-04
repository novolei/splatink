class_name InkEnvironment
extends Node3D
## Original environment geometry, attribute hooks, water fields and motion.
## configure(stage_id,time_of_day,stage_node) after the stage's lights/WorldEnvironment exist.

const Source = preload("res://scripts/world/source_mesh.gd")
const SourceLighting = preload("res://scripts/world/ink_source_lighting.gd")
const WATER_Y := -1.6
const WATER_LAYER := 1 << 19
@export var reflections_enabled := true
@export_enum("low", "medium", "high", "ultra") var quality: String = "high"
@export_range(0.15,0.5,0.01) var reflection_scale := 0.4
var stage_id := "tidewater"
var time_of_day := "day"
var clock := 0.0
var data: Dictionary = {}
var _stage: Node3D
var _materials: Array[ShaderMaterial] = []
var _nodes: Dictionary = {}
var _motion: Array[Dictionary] = []
var _rest: Dictionary = {}
var _textures: Dictionary = {}
var _sea: MeshInstance3D
var _sea_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _sky_dome: MeshInstance3D
var _reflection: SubViewport
var _reflection_camera: Camera3D
var _theme_cache: Dictionary = {}
var _prop_textures: Dictionary = {}

func configure(id: String, period: String = "day", stage_node: Node3D = null) -> void:
	stage_id = id
	time_of_day = "dusk" if period == "dusk" else "day"
	_stage = stage_node if stage_node != null else get_parent() as Node3D
	var path := "res://data/%s_environment_details.json" % id
	if not FileAccess.file_exists(path):
		push_error("Original environment data missing: " + path)
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var stage_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % id))
	for record in stage_data.get("meshes", []):
		if record.material.get("map") != null:
			_prop_textures[String(record.name)] = String(record.material.map)
	var file := FileAccess.open("res://assets/world/%s_environment_details.bin" % id, FileAccess.READ)
	for record in data.meshes:
		if record.get("scope", "environment") == "props":
			_replace_dynamic_prop(file, record)
		else:
			_add_source_mesh(file, record)
	file.close()
	for key in data.textures:
		_textures[key] = _load_texture(data.textures[key])
	_install_source_sky()
	set_time_of_day(time_of_day)
	if bool(data.marina) and reflections_enabled and quality != "low" and not OS.has_feature("mobile"):
		_create_reflection()
	_animate_motion()

func _mesh(file: FileAccess, record: Dictionary) -> ArrayMesh:
	var attrs: Dictionary = record.get("attributes", {})
	if not attrs.has("position") or int(attrs.position.get("length", 0)) < 9:
		return null
	var mesh := Source.build(file, record)
	if mesh.get_surface_count() == 0:
		return null
	var arrays := mesh.surface_get_arrays(0)
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var first := PackedFloat32Array()
	var second := PackedFloat32Array()
	first.resize(count * 4)
	second.resize(count * 4)
	if attrs.has("aInfo"):
		var values := Source.floats(file, attrs.aInfo)
		var size := int(attrs.aInfo.get("size", 4))
		for i in mini(count, values.size() / maxi(size, 1)):
			for component in mini(size, 4):
				first[i * 4 + component] = values[i * size + component]
	else:
		for entry in [{"key":"glow", "channel":0}, {"key":"aPhase", "channel":1}, {"key":"flex", "channel":0}]:
			if attrs.has(entry.key) and not bool(attrs[entry.key].get("instanced", false)) and entry.key != "aPhase":
				var values := Source.floats(file, attrs[entry.key])
				var size := int(attrs[entry.key].get("size", 1))
				for i in mini(count, values.size() / maxi(size, 1)):
					first[i * 4 + int(entry.channel)] = values[i * size]
	for key in ["bld", "wave"]:
		if attrs.has(key):
			var values := Source.floats(file, attrs[key])
			var size := int(attrs[key].get("size", 3))
			for i in mini(count, values.size() / maxi(size, 1)):
				for component in mini(size, 3):
					second[i * 4 + component] = values[i * size + component]
	arrays[Mesh.ARRAY_CUSTOM0] = first
	arrays[Mesh.ARRAY_CUSTOM1] = second
	var result := ArrayMesh.new()
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return result

func _add_source_mesh(file: FileAccess, record: Dictionary, inherited_texture: Texture2D = null) -> GeometryInstance3D:
	var mesh := _mesh(file, record)
	if mesh == null:
		return null
	var material := _material(record, inherited_texture)
	var node: GeometryInstance3D
	if record.has("instances"):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = record.instances.size()
		var phases := PackedFloat32Array()
		if record.attributes.has("aPhase"):
			phases = Source.floats(file, record.attributes.aPhase)
		for i in record.instances.size():
			multi.set_instance_transform(i, Source.transform_matrix(record.instances[i].transform))
			multi.set_instance_color(i, _color(record.instances[i].color))
			multi.set_instance_custom_data(i, Color(phases[i] if i < phases.size() else 0.0, 0.0, 0.0, 0.0))
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multi
		node = batch
	else:
		var single := MeshInstance3D.new()
		single.mesh = mesh
		node = single
	node.name = String(record.name).replace(":", "_")
	node.set_meta("source_name", record.name)
	node.transform = Source.transform_matrix(record.transform)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = bool(record.get("visible", true))
	add_child(node)
	_nodes[String(record.name)] = node
	_rest[String(record.name)] = node.transform
	if record.get("shader") == "sea":
		_sea = node as MeshInstance3D
		_sea_material = material as ShaderMaterial
		_sea.layers = WATER_LAYER
		_sea.extra_cull_margin = 50.0
	if record.has("motion"):
		_motion.append({"node":node, "data":record.motion})
	if record.has("team_tints") and node is MultiMeshInstance3D:
		var colors: Array = _stage.get("team_colors") if _stage != null and _stage.get("team_colors") is Array else [Color("ff3f9e"),Color("18d48c")]
		for i in record.team_tints.size():
			var tint: Dictionary = record.team_tints[i]
			var col := _color(tint.color)
			if int(tint.team) >= 0:
				col = colors[int(tint.team)].srgb_to_linear().lerp(Color.WHITE, float(tint.tint))
			(node as MultiMeshInstance3D).multimesh.set_instance_color(i, col)
	return node

func _replace_dynamic_prop(file: FileAccess, record: Dictionary) -> void:
	var old: GeometryInstance3D
	if _stage != null:
		for child in _stage.get_children():
			if child is GeometryInstance3D and (child.get_meta("source_name", "") == record.name or String(child.name) == String(record.name).replace(":", "_")):
				old = child
				break
	var texture: Texture2D
	if _prop_textures.has(String(record.name)):
		texture = load("res://assets/textures/" + _prop_textures[String(record.name)]) as Texture2D
	if old != null:
		var material := old.material_override as StandardMaterial3D
		if material != null:
			texture = material.albedo_texture
		old.visible = false
		old.queue_free()
	_add_source_mesh(file, record, texture)

func _material(record: Dictionary, inherited_texture: Texture2D = null) -> Material:
	var kind := String(record.get("shader", "native"))
	if kind == "native":
		var material := Source.material(record.material)
		if inherited_texture != null:
			material.albedo_texture = inherited_texture
		var theme: Dictionary = _stage.get("lighting_theme") if _stage != null else {}
		var shaded := SourceLighting.from_standard(material,theme)
		if shaded is ShaderMaterial:
			SourceLighting.configure_data(shaded,record.material)
			SourceLighting.configure(shaded,theme)
			_materials.append(shaded)
		return shaded
	if kind == "sea":
		kind = "sea_marina" if bool(data.marina) else "sea_open"
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/environment_%s.gdshader" % kind) as Shader
	material.set_shader_parameter("base_color", _vector3(record.material.color))
	material.set_shader_parameter("base_roughness", float(record.material.roughness))
	material.set_shader_parameter("base_metallic", float(record.material.metalness))
	if inherited_texture != null:
		material.set_shader_parameter("atlas", inherited_texture)
	_materials.append(material)
	return material

func _install_source_sky() -> void:
	if _stage == null:
		return
	var worlds := _stage.find_children("*", "WorldEnvironment", true, false)
	if worlds.is_empty():
		return
	var world := worlds[0] as WorldEnvironment
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://assets/shaders/environment_sky.gdshader") as Shader
	var radiance := _stage.get("source_radiance") as Cubemap
	if radiance != null:
		_sky_material.set_shader_parameter("source_radiance",radiance)
		_sky_material.set_shader_parameter("source_radiance_enabled",true)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	var pmrem := _stage.get("source_pmrem") as Texture2D
	if pmrem!=null: sky.set_meta("source_pmrem",pmrem)
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	world.environment.sky = sky
	_materials.append(_sky_material)
	# Animated visible sky is a far-plane dome. IBL uses a separate source ENV_PASS shader frozen at t=0.
	_sky_dome = MeshInstance3D.new()
	_sky_dome.name = "OriginalAnimatedSky"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_sky_dome.mesh = sphere
	_sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_dome.extra_cull_margin = 100000.0
	var background := ShaderMaterial.new()
	background.shader = load("res://assets/shaders/environment_sky_dome.gdshader") as Shader
	_sky_dome.material_override = background
	add_child(_sky_dome)
	_materials.append(background)

func set_time_of_day(period: String) -> void:
	if data.is_empty():
		return
	time_of_day = "dusk" if period == "dusk" else "day"
	var theme: Dictionary = data.themes[time_of_day]
	if not _theme_cache.has(time_of_day):
		var cache := {"cloud": _load_texture(theme.cloud)}
		if not theme.far.is_empty():
			var images: Array[Image] = []
			for info in theme.far:
				var image := _load_image(info)
				image.flip_y()
				image.generate_mipmaps()
				images.append(image)
			var cube := Cubemap.new()
			cube.create_from_images(images)
			cache.far = cube
		_theme_cache[time_of_day] = cache
	var assets: Dictionary = _theme_cache[time_of_day]
	for material in _materials:
		for key in theme.uniforms:
			material.set_shader_parameter(key, _uniform_value(theme.uniforms[key]))
		for key in _textures:
			material.set_shader_parameter(key, _textures[key])
		material.set_shader_parameter("uCloudTex", assets.cloud)
		material.set_shader_parameter("uReflOn", 0.0)
		material.set_shader_parameter("uFarOn", 1.0 if assets.has("far") else 0.0)
		if assets.has("far"):
			material.set_shader_parameter("uFarCube", assets.far)
		material.set_shader_parameter("uShafts", 1.0 if stage_id == "halyard" and time_of_day == "day" else 0.0)
		material.set_shader_parameter("uCol", Vector3(1.0,0.7605,0.3916))
	if _nodes.has("LighthouseBeam"):
		_nodes.LighthouseBeam.visible = time_of_day == "dusk"

static func _load_image(info: Dictionary) -> Image:
	var bytes := FileAccess.get_file_as_bytes(String(info.path))
	var format: int = {"rgba8":Image.FORMAT_RGBA8,"l8":Image.FORMAT_L8,"rgba16f":Image.FORMAT_RGBAH}[String(info.format)]
	return Image.create_from_data(int(info.width), int(info.height), false, format, bytes)

static func _load_texture(info: Dictionary) -> ImageTexture:
	var image := _load_image(info)
	# Source DataTexture normals use trilinear mipmaps + anisotropy, unlike the foam/cloud lookup fields.
	if bool(info.get("mipmaps", String(info.path).contains("uWaveTex"))):
		image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func _uniform_value(record: Dictionary) -> Variant:
	var value: Variant = record.value
	match String(record.kind):
		"vec2": return Vector2(value[0],value[1])
		"vec3": return _vector3(value)
		"vec4": return Vector4(value[0],value[1],value[2],value[3])
		"mat4": return Projection(Vector4(value[0],value[1],value[2],value[3]),Vector4(value[4],value[5],value[6],value[7]),Vector4(value[8],value[9],value[10],value[11]),Vector4(value[12],value[13],value[14],value[15]))
		"array_vec2":
			var result := PackedVector2Array()
			for item in value: result.append(Vector2(item[0],item[1]))
			return result
		"array_vec4":
			var result := PackedVector4Array()
			for item in value: result.append(Vector4(item[0],item[1],item[2],item[3]))
			return result
	return value

static func _vector3(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func _color(value: Array) -> Color:
	return Color(value[0],value[1],value[2])

func _process(dt: float) -> void:
	if data.is_empty():
		return
	clock += minf(dt, 0.1)
	for material in _materials:
		if material != _sky_material:
			material.set_shader_parameter("uTime", clock)
	_animate_motion()
	_update_reflection()

func _animate_motion() -> void:
	for entry in _motion:
		var node := entry.node as MultiMeshInstance3D
		var motion: Dictionary = entry.data
		for i in motion.recs.size():
			var record: Dictionary = motion.recs[i]
			if motion.kind == "spin":
				var base := Source.transform_matrix(record.base)
				var axis := Vector3.BACK if motion.axis == "z" else Vector3.UP
				node.multimesh.set_instance_transform(i, base * Transform3D(Basis(axis, clock * float(record.speed) + float(record.phase)), Vector3.ZERO))
			else:
				var s := 0.5 + 0.5 * sin(clock * float(record.rate) * TAU + float(record.phase))
				var k := s * s * (3.0 - 2.0 * s)
				var on := 1.0 if k > 0.6 else k / 0.6 * 0.25
				node.multimesh.set_instance_color(i, _color(record.color) * lerpf(float(record.lo),float(record.hi),on))
	for field in ["sails", "buoys", "gulls"]:
		var name: String = {"sails":"Sailboats", "buoys":"Buoys", "gulls":"Gulls"}[field]
		if not _nodes.has(name):
			continue
		var node := _nodes[name] as MultiMeshInstance3D
		for i in data.motion[field].size():
			var record: Dictionary = data.motion[field][i]
			var position := Vector3.ZERO
			var rotation := Vector3.ZERO
			var scale: float = record.s
			if field == "sails":
				var a := float(record.a) + float(record.w) * clock
				position = Vector3(cos(a)*record.d,0,sin(a)*record.d)
				position.y = water_height_at(position.x,position.z)
				var direction := signf(float(record.w))
				rotation = Vector3(0.03*sin(clock*0.8+record.phase),atan2(-sin(a)*direction,cos(a)*direction),(0.13+0.05*sin(clock*0.6+record.phase))*direction)
			elif field == "buoys":
				position = Vector3(record.x,water_height_at(record.x,record.z)+0.06*sin(clock*1.7+record.phase),record.z)
				rotation = Vector3(0.09*sin(clock*1.1+record.phase),record.phase,0.09*cos(clock*0.93+record.phase*1.3))
			else:
				var a := float(record.a0) + float(record.w) * clock
				var direction := signf(float(record.w))
				position = Vector3(record.cx+cos(a)*record.r,record.h+sin(clock*0.4+record.a0)*1.5,record.cz+sin(a)*record.r)
				rotation = Vector3(0.0,atan2(-sin(a)*direction,cos(a)*direction),-0.35*direction)
			node.multimesh.set_instance_transform(i,Transform3D(Basis.from_euler(rotation,EULER_ORDER_YXZ).scaled(Vector3.ONE*scale),position))
	for boat in data.motion.moored:
		if not _nodes.has(String(boat.name)):
			continue
		var node := _nodes[String(boat.name)] as Node3D
		node.position.y = water_height_at(boat.spec.x,boat.spec.z)+0.03*sin(clock*1.3+boat.phase)
		node.rotation.z = float(boat.roll)*sin(clock*0.9+boat.phase)
		node.rotation.x = 0.012*sin(clock*0.7+boat.phase*2.0)
	if _nodes.has("FerrisWheel"):
		_nodes.FerrisWheel.basis = (_rest.FerrisWheel as Transform3D).basis * Basis(Vector3.BACK,clock*0.045)
	if _nodes.has("LighthouseBeam"):
		_nodes.LighthouseBeam.rotation.y = clock*0.55

func water_height_at(x: float, z: float, time: float = -1.0) -> float:
	var t := clock if time < 0.0 else time
	var distance := 1e5
	var sets: Array = [data.footprint]
	if bool(data.get("marina", false)):
		sets = [data.marina_sets.decks,data.marina_sets.wet]
	for records in sets:
		for rect in records:
			distance = minf(distance,_rect_distance(Vector2(x,z),rect))
	var amp := lerpf(0.035,0.16,smoothstep(3.0,70.0,distance))
	if bool(data.get("marina", false)):
		var b: Dictionary = data.bounds
		var q := Vector2(absf(x-(b.minX+b.maxX)*0.5)-(b.maxX-b.minX)*0.5,absf(z-(b.minZ+b.maxZ)*0.5)-(b.maxZ-b.minZ)*0.5)
		var arena_distance := q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0.0)
		amp *= lerpf(0.45,1.0,smoothstep(60.0,210.0,arena_distance))
	var swell := 0.45*sin(x*0.11+z*0.047+t*0.95)+0.35*sin(-x*0.052+z*0.097+t*1.13+1.7)+0.2*sin(x*0.173-z*0.141+t*1.61+4.1)
	return WATER_Y+swell*amp

static func _rect_distance(point: Vector2, rect: Dictionary) -> float:
	var relative := point-Vector2(rect.cx,rect.cz)
	var axis := Vector2(rect.ax,rect.az)
	var q := Vector2(absf(relative.dot(axis))-rect.hx,absf(relative.dot(Vector2(-axis.y,axis.x)))-rect.hz)
	return q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0.0)

func _create_reflection() -> void:
	_reflection = SubViewport.new()
	_reflection.name = "MarinaReflection"
	_reflection.world_3d = get_world_3d()
	_reflection.transparent_bg = true
	_reflection.use_hdr_2d = true
	_reflection.size = Vector2i(512,288)
	_reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_reflection)
	_reflection_camera = Camera3D.new()
	_reflection_camera.cull_mask = 0xFFFFF & ~WATER_LAYER
	_reflection.add_child(_reflection_camera)
	_reflection_camera.current = true
	var reflected_environment := get_world_3d().environment.duplicate() as Environment
	reflected_environment.background_mode = Environment.BG_COLOR
	reflected_environment.background_color = Color(0,0,0,0)
	reflected_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	reflected_environment.tonemap_exposure = 1.0
	reflected_environment.glow_enabled = false
	_reflection_camera.environment = reflected_environment
	_sea_material.set_shader_parameter("uReflTex",_reflection.get_texture())

func _update_reflection() -> void:
	if _reflection_camera == null:
		return
	if not reflections_enabled or quality == "low":
		_sea_material.set_shader_parameter("uReflOn",0.0)
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var main := get_viewport().get_camera_3d()
	if main == null or main.global_position.y < WATER_Y+0.05:
		_sea_material.set_shader_parameter("uReflOn",0.0)
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var dimensions := get_viewport().get_visible_rect().size*reflection_scale
	_reflection.size = Vector2i(maxi(64,int(dimensions.x)),maxi(64,int(dimensions.y)))
	_reflection_camera.projection = main.projection
	_reflection_camera.fov = main.fov
	_reflection_camera.size = main.size
	_reflection_camera.keep_aspect = main.keep_aspect
	_reflection_camera.near = main.near
	_reflection_camera.far = main.far
	var forward := -main.global_basis.z
	var up := main.global_basis.y
	forward.y = -forward.y
	up.y = -up.y
	var right := forward.cross(up).normalized()
	var position := main.global_position
	position.y = 2.0*WATER_Y-position.y
	_reflection_camera.global_transform = Transform3D(Basis(right,up,-forward),position)
	var bias := Projection(Vector4(0.5,0,0,0),Vector4(0,-0.5,0,0),Vector4(0,0,0.5,0),Vector4(0.5,0.5,0.5,1))
	var matrix := bias*_reflection_camera.get_camera_projection()*Projection(_reflection_camera.global_transform.affine_inverse())
	_sea_material.set_shader_parameter("uReflMat",matrix)
	_sea_material.set_shader_parameter("uReflOn",1.0)

func set_quality(value: String) -> void:
	quality = value if value in ["low", "medium", "high", "ultra"] else "high"
	reflection_scale = {"low":0.0, "medium":0.28, "high":0.4, "ultra":0.5}[quality]
	if OS.has_feature("mobile"):
		reflections_enabled = false
	if _reflection_camera == null and reflections_enabled and quality != "low" and bool(data.get("marina",false)):
		_create_reflection()
	_update_reflection()
