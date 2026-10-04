extends Node3D
## Independent authored-path laboratory. No Actor/controller/database is modified.
const Avatar=preload("res://scripts/characters/ink_avatar.gd")
const Prototype=preload("res://scripts/animation/experiments/motorica_locomotion_prototype.gd")
var entries:Array[Dictionary]=[]
var playing:bool=true
var phase:float=0.0
var start_time:float=0.0
var end_time:float=0.0
var clip_id:String="motorica_Run_Turns_StartStop_L_variation_1"
var window_id:String=""
var family:String="shooter"
var camera:Camera3D
var label:Label
var start_root:=Transform3D.IDENTITY
var last_sample_valid:bool=false

func _ready() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--motorica-clip="):clip_id="motorica_"+arg.trim_prefix("--motorica-clip=").trim_prefix("motorica_")
		if arg.begins_with("--motorica-window="):window_id=arg.trim_prefix("--motorica-window=")
		if arg.begins_with("--motorica-family="):family=arg.trim_prefix("--motorica-family=")
	if not family in Avatar.WEAPONS:
		push_error("Unknown Motorica weapon family: "+family)
		return
	_build_room()
	for index:int in Prototype.MODES.size():
		var mode:String=Prototype.MODES[index]
		var anchor:=Node3D.new()
		anchor.position.x=(float(index)-.5)*3.2
		add_child(anchor)
		var visual:=Node3D.new()
		anchor.add_child(visual)
		var avatar:=Avatar.new()
		avatar.force_lod=0
		visual.add_child(avatar)
		avatar.presentation_interpolation=false
		avatar.set_process(false)
		avatar.configure(Color("ff8a14") if index==0 else Color("19c2b0"),family,{"hair":1,"outfit":2,"eyes":4,"skin":1,"hat":1})
		avatar.configure_lighting({"hemiSky":"#bddcf4","hemiGround":"#f6d0a1","hemiIntensity":2.1,"hemiGroundK":.5})
		var prototype:=Prototype.new()
		if not prototype.configure(avatar._skeleton) or not prototype.clips.has(clip_id):
			push_error("Motorica preview missing clip or rig: "+clip_id)
			prototype.dispose()
			continue
		var clip:Dictionary=prototype.clips[clip_id]
		start_time=0.0
		end_time=float(clip.duration)
		if not window_id.is_empty():
			var found:bool=false
			for candidate:Dictionary in clip.candidate_windows:
				if String(candidate.id)==window_id:
					start_time=float(candidate.start)
					end_time=float(candidate.end)
					found=true
			if not found:
				push_error("Unknown Motorica window: "+window_id)
				prototype.dispose()
				return
		start_root=prototype.sample_metadata(clip_id,start_time,mode).root_transform
		entries.append({"avatar":avatar,"prototype":prototype,"visual":visual,"anchor":anchor,"mode":mode,"authority":[],"module_authority":[]})
	phase=start_time
	seek_time(phase)

func _build_room() -> void:
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color(.16,.20,.25)
	settings.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color(.65,.68,.72)
	settings.ambient_light_energy=.4
	environment.environment=settings
	add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.light_color=Color("ffe4c6")
	sun.light_energy=3.5/PI
	sun.shadow_enabled=true
	sun.rotation_degrees=Vector3(-48,-35,0)
	add_child(sun)
	var fill:=DirectionalLight3D.new()
	fill.light_color=Color("bacfff")
	fill.light_energy=1.2/PI
	fill.rotation_degrees=Vector3(-25,150,0)
	add_child(fill)
	var floor_mesh:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(140,140)
	floor_mesh.mesh=plane
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("647581")
	material.roughness=.95
	floor_mesh.material_override=material
	add_child(floor_mesh)
	camera=Camera3D.new()
	camera.current=true
	camera.fov=43.0
	add_child(camera)
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	label=Label.new()
	label.position=Vector2(20,14)
	label.add_theme_font_size_override("font_size",22)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(label)

func _physics_process(delta:float) -> void:
	if playing:
		phase=minf(phase+delta,end_time)
		seek_time(phase)
		if phase>=end_time:playing=false

func seek_fraction(fraction:float) -> void:
	seek_time(lerpf(start_time,end_time,clampf(fraction,0.0,1.0)))

func seek_time(time:float) -> void:
	last_sample_valid=false
	phase=clampf(time,start_time,end_time)
	var center:=Vector3.ZERO
	var maximum_slide:float=0.0
	var source_speed:float=0.0
	var completed:int=0
	for entry:Dictionary in entries:
		var avatar:InkAvatar=entry.avatar
		var prototype:MotoricaLocomotionPrototype=entry.prototype
		var rig:Skeleton3D=avatar._skeleton
		var packets:Array[Dictionary]=[]
		packets.assign(entry.authority)
		if packets.size()==rig.get_bone_count():prototype.restore_authority(packets)
		_restore_modules(avatar,entry.module_authority)
		var meta:Dictionary=prototype.sample_metadata(clip_id,phase,String(entry.mode))
		if meta.is_empty():return
		# Author root motion is explicitly on an experiment visual owner only.
		(entry.visual as Node3D).transform=start_root.affine_inverse()*(meta.root_transform as Transform3D)
		avatar.animate(1.0/60.0,{"grounded":true,"form":"kid","speed":0.0,"velocity":Vector3.ZERO,"firing":true,"rolling":family=="roller","aim_pitch":.15,"is_local":true})
		entry.authority=prototype.capture_authority()
		entry.module_authority=_capture_modules(avatar)
		var result:Dictionary=prototype.apply(clip_id,phase,String(entry.mode),true)
		if result.is_empty():return
		_copy_experimental_modules(avatar,prototype)
		maximum_slide=maxf(maximum_slide,float(result.get("actual_fk_proxy_slide_m",0.0)))
		source_speed=(meta.source_root_velocity_mps as Vector3).length()
		center+=(entry.visual as Node3D).global_position
		completed+=1
	if not entries.is_empty():center/=float(entries.size())
	camera.look_at_from_position(center+Vector3(0,2.8,7.8),center+Vector3(0,.8,0),Vector3.UP)
	label.text="Motorica authored-time experiment: %s / %s\nLEFT: pelvis + 8 legs, upper-global compensation     RIGHT: 8 legs, source hips held\n%.3f / %.3f sec | original Root speed %.2f m/s | inferred FK slide %.3f m\nAuthor Root path displayed at leg reference scale. No controller/physics takeover. Space pause, R restart."%[clip_id.trim_prefix("motorica_"),window_id if not window_id.is_empty() else "complete clip",phase,end_time,source_speed,maximum_slide]
	last_sample_valid=completed==2

func _capture_modules(avatar:InkAvatar) -> Array:
	var all:Array=[]
	for rig:Skeleton3D in avatar._modules:
		var packets:Array=[]
		for bone:int in rig.get_bone_count():packets.append({"position":rig.get_bone_pose_position(bone),"rotation":rig.get_bone_pose_rotation(bone),"scale":rig.get_bone_pose_scale(bone)})
		all.append(packets)
	return all

func _restore_modules(avatar:InkAvatar,all:Array) -> void:
	if all.size()!=avatar._modules.size():return
	for item:int in all.size():
		var rig:Skeleton3D=avatar._modules[item]
		var packets:Array=all[item]
		for bone:int in rig.get_bone_count():
			rig.set_bone_pose_position(bone,packets[bone].position)
			rig.set_bone_pose_rotation(bone,packets[bone].rotation)
			rig.set_bone_pose_scale(bone,packets[bone].scale)

func _copy_experimental_modules(avatar:InkAvatar,prototype:MotoricaLocomotionPrototype) -> void:
	# Copy only the changed lower/boundary joints. Keep procedural hair/face intact.
	var changed:PackedInt32Array=prototype.indices.duplicate()
	changed.append_array(prototype.upper_boundaries)
	for module:int in avatar._modules.size():
		var rig:Skeleton3D=avatar._modules[module]
		var map:PackedInt32Array=avatar._pose_maps[module]
		for bone:int in map.size():
			var source:int=map[bone]
			if not source in changed:continue
			rig.set_bone_pose_position(bone,avatar._skeleton.get_bone_pose_position(source)+avatar._module_rest_offsets[module][bone])
			rig.set_bone_pose_rotation(bone,avatar._skeleton.get_bone_pose_rotation(source))
			rig.set_bone_pose_scale(bone,avatar._skeleton.get_bone_pose_scale(source))

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_SPACE:playing=not playing
		if event.keycode==KEY_R:phase=start_time;playing=true;seek_time(phase)

func _exit_tree() -> void:
	for entry:Dictionary in entries:(entry.prototype as MotoricaLocomotionPrototype).dispose()
