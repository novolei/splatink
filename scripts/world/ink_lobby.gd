class_name InkLobby
extends Node3D
## Source LobbySet alley and Showcase studio. Host UI drives page/framing/drag APIs.
## update(dt) is explicit, so a hidden menu costs no per-frame work.

const Source = preload("res://scripts/world/source_mesh.gd")
const SourceEnvironment = preload("res://scripts/world/ink_environment.gd")
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Grade = preload("res://scripts/world/ink_grade.gd")
const Stage = preload("res://scripts/world/ink_stage.gd")
const REFLECTION_EXCLUDE := 1 << 19
const RESULTS_SLOTS := [Vector3(0,0.72,0),Vector3(-1.34,0.46,-0.14),Vector3(1.34,0.46,-0.14),Vector3(2.55,0.22,-0.36)]
var data: Dictionary = {}
var page := ""
var camera: Camera3D
var preview: InkAvatar
var players: Array[InkAvatar] = []
var clock := 0.0
var page_clock := 0.0
var spin := 0.0
var spin_velocity := 0.0
var since_drag := 99.0
var dragging := false
var quality := "high"
var _groups: Dictionary = {}
var _nodes: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _lights: Dictionary = {}
var _world: WorldEnvironment
var _alley_environment: Environment
var _studio_environment: Environment
var _studio_pmrem: Texture2D
var _alley_pmrem: Texture2D
var grade: InkGrade
var _textures: Dictionary = {}
var _library: Dictionary = {}
var _team_a := Color("ff8a14")
var _team_b := Color("2f5bff")
var _ui_rect := Rect2()
var _glows: Array = []
var _drips: Array[Dictionary] = []
var _ripples := PackedVector4Array()
var _ripple_index := 0
var _next_drip := 1.2
var _next_sweep := 3.0
var _sweep_time := -1.0
var _sweep_direction := 1.0
var _active := true
var active: bool:
	get: return _active
var _look: Dictionary = {}
var _look_next: Dictionary = {}
var _phase := "emerge"
var _phase_time := 0.0
var _land_time := -10.0
var _reflection: SubViewport
var _reflection_camera: Camera3D
var _results_won := true

func configure(_game: Node = null) -> void:
	if not data.is_empty():
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/lobby.json"))
	for scope in ["alley","pedestal","podium","alley_lights","studio_lights"]:
		var group := Node3D.new()
		group.name = String(scope).to_pascal_case()
		_groups[scope] = group
		add_child(group)
	for info in data.materials:
		_materials.append(_material(info))
	var file := FileAccess.open("res://assets/world/lobby.bin", FileAccess.READ)
	for record in data.meshes:
		_add_mesh(file,record)
	file.close()
	for scope in ["alley","studio"]:
		for info in data.lights[scope]:
			_add_light(info,scope)
	_world = WorldEnvironment.new()
	_world.name = "LobbyLighting"
	add_child(_world)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		grade = Grade.new()
		grade.bloom_enabled = false
		# Showcase.makeCompositeMaterial applies saturation 1.06 + Neutral, with no world HDR grade.
		grade.configure({"grade":{"uSat":1.06,"uVib":0.0,"uContrast":1.0,"uLift":0.0,"uShadowTint":[1,1,1],"uHighTint":[1,1,1],"uExposure":1.0,"uVignette":0.0}})
		var compositor := Compositor.new()
		compositor.compositor_effects = [grade]
		_world.compositor = compositor
	_alley_environment = _environment(true)
	_studio_environment = _environment(false)
	camera = Camera3D.new()
	camera.name = "OriginalShowcaseCamera"
	add_child(camera)
	camera.current = true
	preview = Avatar.new()
	preview.name = "LockerPreview"
	preview.force_lod = 0
	add_child(preview)
	preview.configure(_team_a,"shooter",{})
	preview.set_dance("")
	_glows = data.dynamics.glows.duplicate(true)
	for i in 6:
		_drips.append({"p":Vector3.ZERO,"v":0.0,"on":false})
		_ripples.append(Vector4(0,0,-999,0))
	set_team_colors(_team_a,_team_b)
	set_quality("low" if OS.has_feature("mobile") else quality)
	show_page("loadout")

func _mesh(file: FileAccess, record: Dictionary) -> ArrayMesh:
	var source := Source.build(file,record)
	var arrays := source.surface_get_arrays(0)
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var first := PackedFloat32Array()
	var second := PackedFloat32Array()
	first.resize(count*4)
	second.resize(count*4)
	for key in ["aSurf","aLit","aNeon","aGlow","aSeed","aF","aSway"]:
		if not record.attributes.has(key):
			continue
		var info: Dictionary = record.attributes[key]
		var values := Source.floats(file,info)
		var size := int(info.size)
		for i in mini(count,values.size()/maxi(1,size)):
			for k in mini(4,size):
				first[i*4+k] = values[i*size+k]
	if record.attributes.has("aDec"):
		var values := Source.floats(file,record.attributes.aDec)
		for i in mini(count,values.size()/3):
			for k in 3:
				second[i*4+k] = values[i*3+k]
	arrays[Mesh.ARRAY_CUSTOM0] = first
	arrays[Mesh.ARRAY_CUSTOM1] = second
	var mesh := ArrayMesh.new()
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
	return mesh

func _add_mesh(file: FileAccess, record: Dictionary) -> void:
	var mesh := _mesh(file,record)
	var node: GeometryInstance3D
	if record.has("instances"):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = record.instances.size()
		multi.visible_instance_count = int(record.visible_count)
		for i in record.instances.size():
			multi.set_instance_transform(i,Source.transform_matrix(record.instances[i].transform))
			multi.set_instance_color(i,_color(record.instances[i].color))
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multi
		node = batch
	else:
		var single := MeshInstance3D.new()
		single.mesh = mesh
		node = single
	node.name = String(record.name).replace(":","_")
	node.set_meta("source_name",record.name)
	node.transform = Source.transform_matrix(record.transform)
	node.material_override = _materials[int(record.material)]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(record.cast_shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = bool(record.visible)
	if record.name in ["lobbySet:ground","lobbySet:curbs","lobbySet:steam"]:
		node.layers = REFLECTION_EXCLUDE
	if record.name == "lobbySet:sky":
		node.extra_cull_margin = 100000.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_groups[String(record.scope)].add_child(node)
	_nodes[String(record.name)] = node

func _material(info: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/lobby_%02d.gdshader" % int(info.id)) as Shader
	for name in info.uniforms:
		var value: Dictionary = info.uniforms[name]
		material.set_shader_parameter(name,_texture(value.value) if value.kind == "texture" else SourceEnvironment._uniform_value(value))
	if info.emissive_map != null:
		material.set_shader_parameter("emissive_map",_texture(info.emissive_map))
		material.set_shader_parameter("has_emissive_map",1.0)
	return material

func _texture(info: Dictionary) -> Texture:
	if info.has("library"):
		var kind := String(info.library)
		return Stage.load_texture_library(kind)
	var key := String(info.path)
	if not _textures.has(key):
		var texture := load(key) as Texture2D
		var image := texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		if bool(info.flip_y):
			image.flip_y()
		if bool(info.mipmaps):
			image.generate_mipmaps()
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]

func _environment(alley: bool) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR if alley else Environment.BG_CLEAR_COLOR
	env.background_color = Color(0,0,0,0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if alley:
		var images: Array[Image] = []
		for info in data.environment:
			var image := SourceEnvironment._load_image(info)
			image.flip_y()
			image.generate_mipmaps()
			images.append(image)
		var cube := Cubemap.new()
		cube.create_from_images(images)
		var material := ShaderMaterial.new()
		material.shader = load("res://assets/shaders/lobby_radiance.gdshader")
		material.set_shader_parameter("source_cube",cube)
		material.set_shader_parameter("intensity",float(data.environment_intensity))
		var sky := Sky.new()
		sky.sky_material = material
		if FileAccess.file_exists("res://data/lobby_pmrem.json"):
			var pmrem_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lobby_pmrem.json"))
			_alley_pmrem = ImageTexture.create_from_image(SourceEnvironment._load_image(pmrem_info))
			sky.set_meta("source_pmrem",_alley_pmrem)
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = 0.0
	return env

func _add_light(info: Dictionary, scope: String) -> void:
	if info.type == "HemisphereLight":
		return
	var light: Light3D
	match String(info.type):
		"DirectionalLight": light = DirectionalLight3D.new()
		"SpotLight":
			var spot := SpotLight3D.new()
			spot.spot_range = float(info.distance) if float(info.distance) > 0 else 120.0
			spot.spot_attenuation = float(info.get("decay",2.0))
			spot.spot_angle = rad_to_deg(float(info.angle))
			spot.spot_angle_attenuation = lerpf(8.0,1.0,float(info.penumbra))
			light = spot
		"PointLight":
			var omni := OmniLight3D.new()
			omni.omni_range = float(info.distance) if float(info.distance) > 0 else 120.0
			omni.omni_attenuation = float(info.get("decay",2.0))
			light = omni
		_: return
	light.name = String(info.name)
	_groups[scope+"_lights"].add_child(light)
	light.position = _vector(info.pos)
	light.light_color = _color(info.color).linear_to_srgb()
	light.light_energy = float(info.intensity)/PI
	light.shadow_enabled = bool(info.cast_shadow)
	if info.get("shadow") != null:
		light.shadow_normal_bias = float(info.shadow.normal_bias)
	if info.get("target") != null and light.position.distance_squared_to(_vector(info.target)) > 0.00001:
		light.look_at(_vector(info.target),Vector3.UP)
	_lights[scope+"_"+String(info.name)] = light

func show_page(value: String) -> void:
	if data.is_empty():
		configure()
	page = value
	page_clock = 0.0
	var alley := value in ["hub","lobby"]
	_groups.alley.visible = alley
	_groups.alley_lights.visible = alley
	_groups.pedestal.visible = value in ["loadout","locker","main"]
	_groups.podium.visible = value == "results"
	_groups.studio_lights.visible = not alley
	_world.environment = (_alley_environment if alley else _studio_environment) if _active else null
	preview.visible = value != "lobby" and value != "results" and not value.is_empty()
	for child in players:
		child.visible = value in ["lobby","results"]
	_phase = "pose" if alley else "emerge"
	_phase_time = 0.0
	preview.set_dance("lobby_pose" if alley else "")
	_update_lighting()
	_update_camera(1.0)

func set_active(value: bool) -> void:
	_active = value
	visible = value
	if camera != null: camera.current = value
	if _world != null:
		_world.environment = (_alley_environment if page in ["hub","lobby"] else _studio_environment) if value else null
	if _reflection != null and not value:
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED

func set_studio_radiance(source_sky: Sky, intensity: float = 0.6) -> void:
	# The original overlay borrows G.env.envMap. Share the stage's frozen IBL resource;
	# its moving dome remains in the attract world and never enters this transparent viewport.
	if _studio_environment == null or source_sky == null: return
	_studio_environment.sky = source_sky
	_studio_pmrem = source_sky.get_meta("source_pmrem",null) as Texture2D
	_studio_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_studio_environment.ambient_light_energy = intensity
	_update_lighting()

func set_style(style: Dictionary, color: Color = Color("ff8a14"), weapon: String = "shooter", cause: String = "") -> void:
	if preview == null:
		configure()
	_team_a = color
	if cause.is_empty() or page not in ["locker","loadout","main"]:
		preview.configure(color,weapon,style)
		preview.set_dance("lobby_pose")
	else:
		var change := {"style":style.duplicate(),"color":color,"weapon":weapon,"cause":cause,"swapped":false,"landed":false,"t":0.0}
		if not _look.is_empty() and not bool(_look.get("swapped",false)):
			_look.merge(change,true)
			if cause in ["preset","random"]: _phase = "dip"
		elif not _look.is_empty() or _phase != "pose":
			_look_next = change
		else:
			_start_look(change)
	set_team_colors(color,_team_b)

func _start_look(change: Dictionary) -> void:
	_look = change
	_phase = "dip" if change.cause in ["preset","random"] else "pop"
	_phase_time = 0.0
	if _phase == "dip": preview.trigger("jump")

func set_players(rows: Array, won: bool = true) -> void:
	_results_won = won
	for child in players:
		child.queue_free()
	players.clear()
	for i in mini(rows.size(),4 if page == "results" else 8):
		var row: Dictionary = rows[i]
		var child := Avatar.new()
		child.name = "ShowcasePlayer%d" % i
		child.force_lod = 0 if i == 0 else 1
		add_child(child)
		var col: Color = row.get("color",_team_a if i < 4 else _team_b)
		child.configure(col,String(row.get("weapon","shooter")),row.get("style",{}))
		if page == "results":
			child.position = RESULTS_SLOTS[i]
			child.rotation.y = [0.0,0.2,-0.2,-0.34][i]
			child.set_dance("victory" if won else "defeat")
		else:
			child.position = _vector(data.spots[i].pos)
			child.rotation.y = float(data.spots[i].yaw)
			child.set_dance("lobby_pose")
		players.append(child)
	_update_lighting()

func arrival_path(slot: int) -> PackedVector3Array:
	var path := PackedVector3Array()
	if slot >= 0 and slot < data.lanes.size():
		for point in data.lanes[slot]:
			path.append(_vector(point))
	return path

func _projected_player(index: int) -> InkAvatar:
	if page in ["lobby","results"]:
		return players[index] if index>=0 and index<players.size() else null
	return preview if index==0 else null

func project_player(index: int) -> Vector2:
	var child := _projected_player(index)
	if child == null or camera == null: return Vector2(-10000,-10000)
	# Original Showcase.PLATE_H=1.64 m; pixels are local to this SubViewport.
	return camera.unproject_position(child.global_position+Vector3.UP*1.64)

func player_projection_visible(index: int) -> bool:
	var child := _projected_player(index)
	if not _active or child == null or not child.visible or camera == null: return false
	var anchor := child.global_position+Vector3.UP*1.64
	return not camera.is_position_behind(anchor) and get_viewport().get_visible_rect().has_point(camera.unproject_position(anchor))

func set_team_colors(a: Color, b: Color) -> void:
	_team_a = a
	_team_b = b
	var ca := a.srgb_to_linear()
	var cb := b.srgb_to_linear()
	for material in _materials:
		material.set_shader_parameter("uTeamA",Vector3(ca.r,ca.g,ca.b))
		material.set_shader_parameter("uTeamB",Vector3(cb.r,cb.g,cb.b))
	_materials[0].set_shader_parameter("uCol",Vector3(ca.r,ca.g,ca.b))
	_materials[1].set_shader_parameter("uCol",Vector3(cb.r,cb.g,cb.b))
	_materials[18].set_shader_parameter("base_color",Vector3(ca.r,ca.g,ca.b))
	_update_lighting()

func _update_lighting() -> void:
	if data.is_empty() or preview == null: return
	var hemi: Dictionary = {}
	if page in ["hub","lobby"]:
		for info in data.lights.alley:
			if info.type == "HemisphereLight": hemi = info
		hemi = hemi.duplicate()
		hemi.source_pmrem = _alley_pmrem
		hemi.envK = float(data.environment_intensity)
	else:
		var mood_name := ("win" if _results_won else "lose") if page=="results" else "loadout"
		var mood: Dictionary = data.studio_moods[mood_name]
		var sky := _hex_color(int(mood.sky)).srgb_to_linear()
		var ground := _hex_color(int(mood.ground)).srgb_to_linear()
		hemi = {"type":"HemisphereLight","color":[sky.r,sky.g,sky.b],"ground":[ground.r,ground.g,ground.b],"intensity":mood.hemi}
		hemi.source_pmrem = _studio_pmrem
		hemi.envK = float(mood.env)
		var focus := Vector3(0.55,1.25,0) if page=="results" else Vector3(0,0.8,0)
		var spread := 2.6 if page=="results" else 1.0
		var ink := _team_a.srgb_to_linear()
		ink /= maxf(maxf(ink.r,ink.g),maxf(ink.b,0.0001))
		_studio_light("key",focus+Vector3(-3.4,5.4,4.6)*spread,focus,_hex_color(int(mood.keyCol)),float(mood.key))
		_studio_light("rimA",focus+Vector3(3.8,2.8,-4.4),focus,ink.lerp(Color.WHITE,0.18).linear_to_srgb(),float(mood.rimA))
		_studio_light("rimB",focus+Vector3(-4.4,2,-3.6),focus,Color("d4e8ff"),float(mood.rimB))
		_studio_light("fill",focus+Vector3(4.6,0.6,3.8),focus,Color("e3ecff"),float(mood.fill))
		var glow := ink.lerp(Color.WHITE,0.3)*float(mood.glow)
		_materials[17].set_shader_parameter("uGlow",Vector3(glow.r,glow.g,glow.b))
		if _studio_environment.sky != null:
			_studio_environment.ambient_light_energy = float(mood.env)
	preview.configure_lighting(hemi)
	for child in players: child.configure_lighting(hemi)
	var irradiance := Avatar._hemi_parameters(hemi)
	for material in _materials:
		material.set_shader_parameter("hemi_sky",irradiance.sky)
		material.set_shader_parameter("hemi_ground",irradiance.ground)

func _studio_light(id: String, where: Vector3, focus: Vector3, color: Color, intensity: float) -> void:
	var light := _lights.get("studio_"+id) as DirectionalLight3D
	if light == null: return
	light.position = where
	light.look_at(focus,Vector3.UP)
	light.light_color = color
	light.light_energy = intensity/PI

static func _hex_color(value: int) -> Color:
	return Color("%06x"%value)

func set_ui_rect(free_area: Rect2) -> void:
	_ui_rect = free_area
	_update_camera(1.0)

func begin_drag(_pointer_x: float = 0.0) -> void:
	dragging = page in ["loadout","locker","main","hub"]
	spin_velocity = 0.0

func drag_by(pixel_delta_x: float, dt: float = 0.016) -> void:
	if not dragging:
		return
	spin += pixel_delta_x*0.011
	spin_velocity = lerpf(spin_velocity,pixel_delta_x*0.011/maxf(0.008,dt),0.5)
	since_drag = 0.0

func end_drag() -> void:
	dragging = false

func update(dt: float) -> void:
	if data.is_empty() or page.is_empty() or not _active:
		return
	dt = clampf(dt,0.0,0.1)
	clock += dt
	page_clock += dt
	for material in _materials:
		material.set_shader_parameter("uTime",clock)
	if page in ["hub","lobby"]:
		_update_alley(dt)
	else:
		_update_studio(dt)
	_update_camera(dt)
	_update_reflection()
	for child in players:
		child.animate(dt,{"speed":0.0,"grounded":true,"form":"kid","tank":1.0})

func _update_studio(dt: float) -> void:
	if not dragging:
		spin += spin_velocity*dt
		spin_velocity *= exp(-3.4*dt)
		since_drag += dt
		if since_drag > 2.4 and absf(spin_velocity) < 0.35:
			spin = lerpf(spin,roundf(spin/TAU)*TAU,1.0-exp(-1.1*dt))
	var stage_y := -0.95*(1.0-_back_out(page_clock/0.6,1.25))
	var yaw := spin+0.17*sin((page_clock-1.6)*0.5)*smoothstep(1.6,4.0,page_clock)
	_groups.pedestal.position.y = stage_y
	_groups.pedestal.rotation.y = yaw
	_phase_time += dt
	var y := 0.0
	var vy := 0.0
	var sy := 1.0
	var turn := 0.0
	var air := false
	var form := "kid"
	if _phase == "dip":
		if _phase_time < 0.09:
			sy = 1.0-0.12*sin(PI*0.5*_phase_time/0.09)
		else:
			var x := minf(1.0,(_phase_time-0.09)/0.4)
			var b := 0.44+2.0*sqrt(0.22*0.22+0.22*1.5)
			y = (-1.5-b)*x*x+b*x
			vy = (2.0*(-1.5-b)*x+b)/0.4
			turn = 1.2*_ease(x)
			air = true
			form = "squid" if x > 0.3 else "kid"
			if x >= 1.0:
				_swap_look()
				_phase = "emerge"
				_phase_time = 0.02
	elif _phase == "emerge":
		var te := _phase_time-0.12
		var gravity := 2.0*(0.3+1.45)/(0.4*0.4)
		var velocity := gravity*0.4
		y = -1.45 if te < 0.0 else -1.45+velocity*te-0.5*gravity*te*te
		vy = 0.0 if te < 0.0 else velocity-gravity*te
		air = true
		turn = -0.6*(1.0-_ease_out(clampf(te/0.55,0.0,1.0)))
		sy = 1.0+0.16*clampf(vy/7.0,0.0,1.0)
		if te > 0.4 and y <= 0.0:
			y = 0.0
			air = false
			_phase = "pose"
			_land_time = page_clock
			preview.trigger("land",7.0)
			preview.set_dance("lobby_pose")
			_look.clear()
	elif _phase == "pop":
		if _phase_time < 0.085:
			sy = 1.0-0.15*sin(PI*0.5*_phase_time/0.085)
			y = -0.015*_phase_time/0.085
		else:
			if not bool(_look.get("swapped",false)):
				_swap_look()
				preview.trigger("jump")
			var x := (_phase_time-0.085)/0.34
			var h := 0.2 if _look.get("cause","") == "outfit" else 0.13
			if x < 1.0:
				y = 4.0*h*x*(1.0-x)
				vy = 4.0*h*(1.0-2.0*x)/0.34
				sy = 1.0+0.1*clampf(vy/2.2,0.0,1.0)-0.05*clampf(-vy/2.2,0.0,1.0)
				turn = (TAU if _look.get("cause","") == "outfit" else -TAU if _look.get("cause","") == "hair" else 0.0)*_ease(x)
				air = true
			elif not bool(_look.get("landed",false)):
				_look.landed = true
				_land_time = page_clock
				preview.trigger("land",6.0)
				preview.trigger("admire" if _look.get("cause","") == "outfit" else "hairflip" if _look.get("cause","") == "hair" else "wink")
			if x > 1.35:
				_phase = "pose"
				_look.clear()
	if _phase == "pose":
		sy = 1.0-0.13*exp(-(page_clock-_land_time)*6.5)*sin((page_clock-_land_time)*15.0)
		if not _look_next.is_empty():
			_start_look(_look_next)
			_look_next = {}
	preview.position = Vector3(0,stage_y+0.007+y,0)
	preview.scale = Vector3(1.0/sqrt(sy),sy,1.0/sqrt(sy))
	preview.rotation.y = -0.45+yaw+turn
	preview.animate(dt,{"speed":0.0,"grounded":not air,"form":form,"velocity":Vector3(0,vy,0),"tank":1.0})

func _swap_look() -> void:
	if _look.is_empty():
		return
	preview.configure(_look.color,String(_look.weapon),_look.style)
	preview.set_dance("lobby_pose")
	_look.swapped = true

func _update_alley(dt: float) -> void:
	var shimmer := 1.0+0.02*sin(clock*120.0)*sin(clock*7.3)
	var burst := sin(clock*0.37)*sin(clock*0.91+1.3)>0.55
	var buzz := (1.0 if _hash(floorf(clock*22.0))>0.45 else 0.08) if burst else 1.0
	_materials[4].set_shader_parameter("uI",Vector3(7.0*shimmer,7.5*(1.0+0.03*sin(clock*1.7)),buzz))
	_materials[0].set_shader_parameter("uI",shimmer*(0.93+0.07*buzz))
	_materials[1].set_shader_parameter("uI",1.05*(1.0+0.03*sin(clock*1.7)))
	for entry in [{"name":"neonA","color":_team_a,"power":16.0*shimmer*(0.93+0.07*buzz)},{"name":"neonB","color":_team_b,"power":26.0*(1.0+0.03*sin(clock*1.7))}]:
		var light := _lights.get("alley_"+entry.name) as Light3D
		if light != null:
			var col: Color = entry.color.srgb_to_linear()
			light.light_color = (col/maxf(maxf(col.r,col.g),maxf(col.b,0.001))).linear_to_srgb()
			light.light_energy = entry.power/PI
	var bulbs := (_nodes.get("lobbySet:bulbs") as MultiMeshInstance3D).multimesh
	var glows := (_nodes.get("lobbySet:glows") as MultiMeshInstance3D).multimesh
	var bi := 0
	for i in _glows.size():
		var row: Dictionary = _glows[i]
		var position := _vector(row.pos)
		if row.get("tag") is Dictionary:
			var s: Dictionary = row.tag.s
			var fraction := (float(row.tag.k)+0.5)/float(s.n)
			position = _vector(s.a).lerp(_vector(s.b),fraction)
			position.y -= float(s.sag)*4.0*fraction*(1.0-fraction)
			var sway := sin(clock*1.3+float(s.a.z)*0.7)*0.035*sin(PI*fraction)
			position.z += sway
			position.y -= 0.045+absf(sway)*0.2
			bulbs.set_instance_transform(bi,Transform3D(Basis.IDENTITY,position))
			bi += 1
		glows.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*float(row.r)),position))
		glows.set_instance_color(i,_color(row.color))
	_next_drip -= dt
	if _next_drip <= 0.0:
		_next_drip = 1.4+_hash(floorf(clock*10.0))*1.8
		for drip in _drips:
			if not bool(drip.on):
				drip.p = _vector(data.dynamics.drip_sources[int(_hash(floorf(clock*3.0))*data.dynamics.drip_sources.size())])
				drip.v = 0.0
				drip.on = true
				break
	var drip_mesh := (_nodes.get("lobbySet:drips") as MultiMeshInstance3D).multimesh
	var count := 0
	for drip in _drips:
		if not bool(drip.on): continue
		drip.v += 9.8*dt
		drip.p.y -= float(drip.v)*dt
		if drip.p.y <= 0.0:
			_ripples[_ripple_index%6] = Vector4(drip.p.x,drip.p.z,clock,1.0)
			_ripple_index += 1
			drip.on = false
		else:
			drip_mesh.set_instance_transform(count,Transform3D(Basis.IDENTITY.scaled(Vector3(1,1+float(drip.v)*0.25,1)),drip.p))
			count += 1
	drip_mesh.visible_instance_count = count
	_materials[6].set_shader_parameter("uRip",_ripples)
	var moth := _nodes.get("lobbySet:moth") as Node3D
	var centre := _vector(data.dynamics.moth_center)
	var angle := clock*2.3
	moth.position = centre+Vector3(sin(angle*1.7)*0.22+sin(clock*9.1)*0.03,sin(angle*1.3+1.0)*0.12+sin(clock*11.3)*0.02,cos(angle*1.1)*0.25)
	moth.rotation = Vector3(0,angle*1.7+PI*0.5,0.3*sin(clock*5.0))
	moth.scale = Vector3(0.6+0.4*absf(sin(clock*57.0)),1,1)
	_update_headlights(dt)
	if page == "hub":
		preview.position = _vector(data.hub_spot.pos)
		preview.rotation.y = float(data.hub_spot.yaw)+spin
		preview.scale = Vector3.ONE
		preview.animate(dt,{"speed":0.0,"grounded":true,"form":"kid","tank":1.0})

func _update_headlights(dt: float) -> void:
	_next_sweep -= dt
	if _sweep_time < 0.0 and _next_sweep <= 0.0:
		_sweep_time = 0.0
		_sweep_direction = 1.0 if _hash(floorf(clock))>0.5 else -1.0
	if _sweep_time < 0.0: return
	_sweep_time += dt
	var x := _sweep_direction*(-26.0+52.0*_sweep_time/3.2)
	var z := float(data.alley.street.z0)-(4.5 if _sweep_direction>0.0 else 8.5)
	var k := 0.9*minf(1.0,_sweep_time*3.0)*minf(1.0,(3.2-_sweep_time)*3.0)
	for i in 2:
		_glows[int(data.dynamics.headlight_glow)+i].pos = [x-_sweep_direction*1.5*i,0.7,z]
		var color := Color("fff1d8").srgb_to_linear()*k*1.2
		_glows[int(data.dynamics.headlight_glow)+i].color = [color.r,color.g,color.b]
	var light := _lights.get("alley_sweep") as Light3D
	if light != null:
		light.position = Vector3(x,0.8,z)
		light.look_at(Vector3(x*0.3+_sweep_direction*4.0,1,-27),Vector3.UP)
		var vis := maxf(0.0,1.0-absf(x)/26.0)
		light.light_energy = 260.0*vis*vis*k/PI
	if _sweep_time >= 3.2:
		_sweep_time = -1.0
		_next_sweep = 7.0+_hash(floorf(clock*2.0))*7.0
		if light != null: light.light_energy = 0.0
		for i in 2: _glows[int(data.dynamics.headlight_glow)+i].color = [0.0,0.0,0.0]

func _update_camera(_dt: float) -> void:
	if camera == null: return
	if page in ["hub","lobby"]:
		var shot: Dictionary = data.hub_camera if page == "hub" else data.camera
		camera.set_perspective(float(shot.fov),float(shot.near),float(shot.far))
		camera.position = _vector(shot.pos)
		camera.look_at(_vector(shot.target),Vector3.UP)
		return
	var view := get_viewport().get_visible_rect().size
	var w := maxf(1.0,view.x)
	var h := maxf(1.0,view.y)
	var u := minf(w*0.01,h*0.017778)
	var left := _ui_rect.position.x if _ui_rect.has_area() else 3.6*u+minf(52*u,0.54*w)+w*0.012
	var right := _ui_rect.end.x if _ui_rect.has_area() else w*0.985
	var free_width := maxf(w*0.18,right-left)
	var locker := page == "locker"
	var fov := 23.0 if locker else 25.0
	var focus_y := 0.86 if locker else 0.76
	var k := minf((0.56 if locker else 0.6)*h/1.62,(0.98 if locker else 0.84)*free_width/(2.0*(0.64+0.075)))
	var tan_h := tan(deg_to_rad(fov)*0.5)
	var distance := h/(2.0*k*tan_h)
	var e := _ease_out(page_clock/1.45)
	var yaw := 0.36*(1.0-e)+0.03*sin(page_clock*0.41)*e
	var pitch := (-0.07 if locker else -0.1)-0.05*(1.0-e)+0.012*sin(page_clock*0.29+1.3)*e
	distance *= 1.0+0.3*(1.0-e)+0.012*sin(page_clock*0.23+2.1)*e
	var sx := (left+right)*0.5
	var sy := (0.8 if locker else 0.735)*h-focus_y*k
	if page == "results":
		focus_y = 1.2
		distance = 9.6
		fov = 22.0
		yaw = -0.3*(1.0-e)
		pitch = -0.075
		sx = w*0.6
		sy = h*0.35
		tan_h = tan(deg_to_rad(fov)*0.5)
	var focus := Vector3(0,focus_y,0)
	camera.position = focus+Vector3(distance*sin(yaw)*cos(pitch),-distance*sin(pitch),distance*cos(yaw)*cos(pitch))
	camera.look_at(focus,Vector3.UP)
	var near := maxf(0.05,distance-12.0)
	var half_height := near*tan_h
	var offset := Vector2((1.0-2.0*sx/w)*half_height*w/h,(2.0*sy/h-1.0)*half_height)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(2.0*half_height,offset,near,distance+14.0)

func set_quality(value: String) -> void:
	quality = value if value in ["low","medium","high","ultra"] else "high"
	if _nodes.has("lobbySet:steam"):
		_nodes["lobbySet:steam"].visible = quality != "low"
	for name in ["alley_vend","alley_sweep"]:
		if _lights.has(name): _lights[name].visible = quality != "low"
	if quality != "low" and not OS.has_feature("mobile") and _reflection == null:
		_create_reflection()
	if _reflection != null:
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED if quality == "low" else SubViewport.UPDATE_ALWAYS

func _create_reflection() -> void:
	_reflection = SubViewport.new()
	_reflection.name = "OriginalWetFloorReflection"
	_reflection.world_3d = get_world_3d()
	_reflection.transparent_bg = true
	_reflection.use_hdr_2d = true
	_reflection.size = Vector2i(512,288)
	add_child(_reflection)
	_reflection_camera = Camera3D.new()
	_reflection_camera.cull_mask = 0xFFFFF & ~REFLECTION_EXCLUDE
	_reflection.add_child(_reflection_camera)
	_reflection_camera.current = true
	var env := _alley_environment.duplicate() as Environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	_reflection_camera.environment = env
	_materials[6].set_shader_parameter("tRefl",_reflection.get_texture())

func _update_reflection() -> void:
	if _reflection == null: return
	var enabled := page in ["hub","lobby"] and quality != "low" and camera.global_position.y > 0.02
	_reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	_materials[6].set_shader_parameter("uReflOn",1.0 if enabled else 0.0)
	if not enabled: return
	var size := get_viewport().get_visible_rect().size*(0.34 if quality == "medium" else 0.5)
	_reflection.size = Vector2i(maxi(64,int(size.x)),maxi(64,int(size.y)))
	_reflection_camera.set_perspective(camera.fov,camera.near,camera.far)
	var forward := -camera.global_basis.z
	var up := camera.global_basis.y
	forward.y *= -1.0
	up.y *= -1.0
	var position := camera.global_position
	position.y *= -1.0
	_reflection_camera.global_transform = Transform3D(Basis(forward.cross(up).normalized(),up,-forward),position)
	var bias := Projection(Vector4(0.5,0,0,0),Vector4(0,-0.5,0,0),Vector4(0,0,0.5,0),Vector4(0.5,0.5,0.5,1))
	_materials[6].set_shader_parameter("uReflMat",bias*_reflection_camera.get_camera_projection()*Projection(_reflection_camera.global_transform.affine_inverse()))
	_materials[6].set_shader_parameter("uReflRes",Vector2(_reflection.size))

static func _vector(value: Variant) -> Vector3:
	return Vector3(value.x,value.y,value.z) if value is Dictionary else Vector3(value[0],value[1],value[2])

static func _color(value: Array) -> Color:
	return Color(value[0],value[1],value[2])

static func _hash(value: float) -> float:
	return fposmod(sin(value*127.1+311.7)*43758.5453123,1.0)

static func _ease(value: float) -> float:
	var x := clampf(value,0.0,1.0)
	return x*x*x*(x*(x*6.0-15.0)+10.0)

static func _ease_out(value: float) -> float:
	return 1.0-pow(1.0-clampf(value,0.0,1.0),3.0)

static func _back_out(value: float, k: float) -> float:
	var x := clampf(value,0.0,1.0)-1.0
	return 1.0+x*x*((k+1.0)*x+k)
