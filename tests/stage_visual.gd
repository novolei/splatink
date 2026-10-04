extends SceneTree
const Stage = preload("res://scripts/world/ink_stage.gd")
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
var stage: InkStage
var avatar: InkAvatar
var elapsed := 0.0
var output := "res://shots/tidewater_visual.png"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var id := "tidewater"
	var time := "day"
	var quality:="high"
	var no_avatar:=false
	var component:="full"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):id=arg.trim_prefix("--map=")
		if arg.begins_with("--time="):time=arg.trim_prefix("--time=")
		if arg.begins_with("--quality="):quality=arg.trim_prefix("--quality=")
		if arg=="--no-avatar":no_avatar=true
		if arg.begins_with("--component="):component=arg.trim_prefix("--component=")
	output="res://shots/"+id+"_"+time+("_comparison.png" if no_avatar else "_visual.png")
	if component!="full":output=output.trim_suffix(".png")+"_"+component+".png"
	stage=Stage.new();root.add_child(stage);stage.build(id,time,[Color("ff3f9e"),Color("18d48c")],quality)
	if component!="full":
		for target:ShaderMaterial in [stage.material,stage.grate_material]:
			target.set_shader_parameter("lamp_count",0)
			if component=="sun":
				target.set_shader_parameter("hemi_sky",Vector3.ZERO);target.set_shader_parameter("hemi_ground",Vector3.ZERO)
				target.set_shader_parameter("source_env_intensity",0.0)
			if component=="albedo":
				var debug_shader:=Shader.new()
				debug_shader.code=target.shader.code.replace("#include \"res://assets/shaders/source_surface_physical.gdshaderinc\"","").replace("ambient_light_disabled;","ambient_light_disabled,unshaded;")
				target.shader=debug_shader
		if component=="indirect":stage.get_node("SourceSun").light_energy=0.0
	avatar=Avatar.new();stage.add_child(avatar)
	avatar.configure(Color("ff8a14"),"shooter",{"hair":0,"skin":0,"outfit":0,"eyes":0,"hat":0,"brows":0})
	avatar.configure_lighting(stage.lighting_theme)
	avatar.visible=not no_avatar
	var pos := Stage.vec3(stage.layout.spawnPads[0])
	avatar.position=pos;avatar.position.y=stage.ground_height(pos.x,pos.z)+.02
	var camera := Camera3D.new();camera.near=.1;camera.far=6500;camera.fov=62;stage.add_child(camera);camera.current=true
	var direction:Vector3=(-pos*Vector3(1,0,1)).normalized()
	camera.position=avatar.position-direction*4.5+Vector3.UP*2.1
	camera.look_at(avatar.position+direction*10+Vector3.UP*.8)
	print("VISUAL_CAMERA ",avatar.position," ",camera.position," ",camera.global_basis)
	await create_timer(3).timeout
	# Match the original's deterministic 60-frame reference capture.
	stage.clock=59.0/60.0;stage.update(0.0)
	stage.environment_detail.set_process(false);stage.environment_detail.clock=1.0;stage.environment_detail._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("VISUAL_CAPTURE "+JSON.stringify({"map":id,"error":result,"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"fps":Performance.get_monitor(Performance.TIME_FPS)}))
	quit(result)
func _process(dt: float) -> bool:
	elapsed+=dt
	if avatar:avatar.animate(dt,{"form":"kid","speed":0.0,"grounded":true,"tank":1.0,"is_local":true})
	return false
