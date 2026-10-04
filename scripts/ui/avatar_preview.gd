class_name SplatAvatarPreview
extends SubViewportContainer
## Live, independent 3D wardrobe preview. It shares no gameplay world or actor state.

var style: Dictionary = {}
var weapon_id: String = "shooter"
var avatar: Node3D
var _viewport: SubViewport
var _stage: Node3D
var _yaw: float = 0.0
var thumbnail: bool = false
var portrait_kind:String="bust"
var _posed: bool = false
var source_environment:Environment
var _camera:Camera3D
var _rim:DirectionalLight3D

static func make(profile: Dictionary, weapon: String, controller:Node=null) -> SplatAvatarPreview:
	var preview := SplatAvatarPreview.new()
	preview.style = profile.duplicate()
	preview.weapon_id = weapon
	if is_instance_valid(controller) and controller.get("lobby") is Node:
		preview.source_environment=controller.get("lobby").get("_studio_environment") as Environment
	return preview

func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(160, 160) if thumbnail else Vector2i(500, 500)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if thumbnail else SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0, 0, 0, 0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_energy = 0.0
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.tonemap_exposure = 1.0
	if source_environment!=null and source_environment.sky!=null:
		settings.sky=source_environment.sky
		settings.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
		settings.ambient_light_energy=.6
		settings.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.environment = settings
	if RenderingServer.get_current_rendering_method()!="gl_compatibility":
		var grade:=InkGrade.new()
		grade.configure({"grade":{"uSat":1.0,"uVib":0.0,"uContrast":1.0,"uLift":0.0,"uShadowTint":[1.0,1.0,1.0],"uHighTint":[1.0,1.0,1.0],"uExposure":1.0,"uVignette":0.0}})
		var compositor:=Compositor.new();compositor.compositor_effects=[grade];environment.compositor=compositor
	_stage.add_child(environment)
	_light(Vector3(-3.4,6.2,4.6),Color("fff0de"),2.75)
	_rim=_light(Vector3(3.8,3.6,-4.4),Color.WHITE,3.4)
	_light(Vector3(-4.4,2.8,-3.6),Color("d4e8ff"),1.9)
	_light(Vector3(4.6,1.4,3.8),Color("e3ecff"),.5)
	var camera := Camera3D.new()
	_camera=camera
	camera.position = Vector3(2.2, 1.45, 3.5)
	camera.fov = 32
	_stage.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var avatar_script: Script = load("res://scripts/characters/ink_avatar.gd") as Script
	if avatar_script != null:
		avatar = avatar_script.new() as Node3D
		_stage.add_child(avatar)
		apply_style(style)
		if thumbnail:
			if avatar.has_method("set_dance"):avatar.call("set_dance","lobby_pose" if portrait_kind=="body" else "menu_idle")
			if avatar.has_method("animate"):
				for step:int in 14:avatar.call("animate",1.0/30,{"speed":0.0,"form":"kid","grounded":true,"firing":false,"charge":0.0,"tank":1.0})
			_frame_portrait()
			_posed=true
	gui_input.connect(_rotate)
	if thumbnail:set_process(false)

func _light(point:Vector3,color:Color,power:float)->DirectionalLight3D:
	var light:=DirectionalLight3D.new();_stage.add_child(light)
	light.position=point;light.light_color=color;light.light_energy=power/PI
	light.look_at(Vector3(0,.8,0))
	return light

func _frame_portrait()->void:
	var head:Vector3=avatar.call("get_head_position") if avatar.has_method("get_head_position") else Vector3(0,1.35,0)
	var target:Vector3=Vector3(head.x,head.y-.3,head.z)
	var span:float=1.2;var yaw:float=-.4;var pitch:float=-.06
	if portrait_kind=="body":target=Vector3(0,.72,0);span=1.74;yaw=-.3;pitch=-.07
	elif portrait_kind=="head":target.y=head.y-.08;span=.64
	elif portrait_kind=="face":target.y=head.y-.1;span=.5;pitch=-.02
	var distance:float=span*.5/tan(deg_to_rad(18)*.5)
	_camera.fov=18;_camera.position=target+Vector3(sin(yaw)*cos(pitch),-sin(pitch),cos(yaw)*cos(pitch))*distance
	_camera.look_at(target);_camera.near=maxf(.05,distance-3);_camera.far=distance+3

func apply_style(value: Dictionary) -> void:
	style = value.duplicate()
	if is_instance_valid(avatar) and avatar.has_method("configure"):
		avatar.call("configure", SplatUiTheme.ORANGE, weapon_id, style)
		if avatar.has_method("configure_lighting"):avatar.call("configure_lighting",{"hemiSky":"#dce8ff","hemiGround":"#2c2442","hemiIntensity":.8,"envK":.6,"source_pmrem":source_environment.sky.get_meta("source_pmrem",null) if source_environment!=null and source_environment.sky!=null else null})
		if _rim!=null:
			var tint:Color=SplatUiTheme.ORANGE.srgb_to_linear()
			var peak:float=maxf(tint.r,maxf(tint.g,tint.b));tint=Color(tint.r/peak,tint.g/peak,tint.b/peak).lerp(Color.WHITE,.18)
			_rim.light_color=tint.linear_to_srgb()
		_posed = false
		if thumbnail: _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	if is_visible_in_tree() and is_instance_valid(avatar):
		if thumbnail and _posed: return
		avatar.rotation.y = _yaw
		if avatar.has_method("animate"):
			avatar.call("animate", delta, {"speed": 0.0, "form": "kid", "grounded": true, "firing": false, "charge": 0.0, "tank": 1.0})
		_posed = true

func _rotate(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw += event.relative.x * 0.01
	elif event is InputEventScreenDrag:
		_yaw += event.relative.x * 0.01
