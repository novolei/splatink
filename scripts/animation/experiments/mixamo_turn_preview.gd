extends Node3D
## Independent 4 x 3 turn laboratory; normal game/controller never load this scene.
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Prototype = preload("res://scripts/animation/experiments/mixamo_turn_prototype.gd")
const MODES := ["source_baseline","source_yaw_pelvis9","fixed_authority_leg8"]
var entries:Array[Dictionary] = []
var playing:bool = true
var phase:float = 0.0
var camera:Camera3D

func _ready() -> void:
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
	var floor_box:=BoxMesh.new()
	floor_box.size=Vector3(13,.08,10)
	floor_mesh.mesh=floor_box
	floor_mesh.position.y=-.04
	var floor_material:=StandardMaterial3D.new()
	floor_material.albedo_color=Color("647581")
	floor_material.roughness=.95
	floor_mesh.material_override=floor_material
	add_child(floor_mesh)
	camera=Camera3D.new()
	camera.position=Vector3(0,8.2,12.5)
	camera.look_at_from_position(camera.position,Vector3(0,.3,0),Vector3.UP)
	camera.fov=45
	camera.current=true
	add_child(camera)
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(Prototype.DATA_PATH))
	if not parsed is Dictionary:return
	var source:Dictionary=parsed
	for row:int in MODES.size():
		for column:int in (source.clips as Array).size():
			var clip:Dictionary=source.clips[column]
			var anchor:=Node3D.new()
			anchor.name="Turn_%d_%d"%[row,column]
			anchor.position=Vector3((float(column)-1.5)*3.0,0,(float(row)-1.0)*2.9)
			add_child(anchor)
			var visual:=Node3D.new()
			anchor.add_child(visual)
			var avatar:=Avatar.new()
			avatar.force_lod=0
			visual.add_child(avatar)
			avatar.presentation_interpolation=false
			avatar.set_process(false)
			avatar.configure(Color("ff8a14") if row!=2 else Color("19c2b0"),Avatar.WEAPONS[column],{"hair":column,"outfit":column+2,"eyes":column,"skin":column%3,"hat":0})
			avatar.configure_lighting({"hemiSky":"#bddcf4","hemiGround":"#f6d0a1","hemiIntensity":2.1,"hemiGroundK":.5})
			var prototype:=Prototype.new()
			if not prototype.configure(avatar._skeleton):continue
			var label:=Label3D.new()
			label.text=String(clip.id).trim_prefix("mixamo_").replace("_"," ")+"\n"+MODES[row]+"\n%.3fs / %.1f deg"%[float(clip.duration),rad_to_deg(float(clip.actual_turn_radians))]
			label.position=Vector3(0,2.05,0)
			label.font_size=27
			label.pixel_size=.006
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			anchor.add_child(label)
			entries.append({"anchor":anchor,"visual":visual,"avatar":avatar,"prototype":prototype,"clip":clip,"mode":MODES[row],"authority":[]})
	seek_fraction(0.0)

func _physics_process(delta:float) -> void:
	if playing:
		phase=fmod(phase+delta,2.4)
		# Original seconds, separate end hold per clip. No playback time warp.
		for entry:Dictionary in entries:_sample(entry,minf(phase,float((entry.clip as Dictionary).duration)))

func seek_fraction(fraction:float) -> void:
	for entry:Dictionary in entries:
		var clip:Dictionary=entry.clip
		var time:float=clampf(fraction,0.0,1.0)*float(clip.duration)
		_sample(entry,time)

func _sample(entry:Dictionary,time:float) -> void:
	var prototype:MixamoTurnPrototype=entry.prototype
	var avatar:InkAvatar=entry.avatar
	var clip:Dictionary=entry.clip
	var meta:Dictionary=prototype.sample_metadata(String(clip.id),time,String(entry.mode))
	(entry.visual as Node3D).rotation.y=float(meta.root_yaw) if String(entry.mode)!="fixed_authority_leg8" else 0.0
	var rig:Skeleton3D=avatar._skeleton
	var authority:Array=entry.authority
	if authority.size()==rig.get_bone_count():
		for bone:int in rig.get_bone_count():
			rig.set_bone_pose_position(bone,authority[bone].position)
			rig.set_bone_pose_rotation(bone,authority[bone].rotation)
			rig.set_bone_pose_scale(bone,authority[bone].scale)
	avatar.animate(1.0/60.0,{"grounded":true,"form":"kid","speed":0.0,"firing":true,"rolling":avatar.weapon_id=="roller","aim_pitch":.15,"is_local":true})
	authority.clear()
	for bone:int in rig.get_bone_count():authority.append({"position":rig.get_bone_pose_position(bone),"rotation":rig.get_bone_pose_rotation(bone),"scale":rig.get_bone_pose_scale(bone)})
	entry.authority=authority
	prototype.apply(String(clip.id),time,String(entry.mode),true,true)

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:playing=not playing

func _exit_tree() -> void:
	for entry:Dictionary in entries:(entry.prototype as MixamoTurnPrototype).dispose()
