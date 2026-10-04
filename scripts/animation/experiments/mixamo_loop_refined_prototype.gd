extends RefCounted
## Experimental resource sampler. Production Avatar/MM never references this file.
## Cumulative source travel remains metadata; no owner or physics transform writes.
const DIRECTORY := "res://assets/animation/experiments/mixamo_loops_refined/"
const NAMES := ["hips","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
var data:Dictionary={}
var clips:Dictionary={}
var rig:Skeleton3D
var player:AnimationPlayer
var indices:=PackedInt32Array()
var upper_boundaries:=PackedInt32Array()

func configure(skeleton:Skeleton3D)->bool:
	dispose()
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"loops.json"))
	if not parsed is Dictionary or skeleton==null or skeleton.get_bone_count()!=87:return false
	rig=skeleton
	data=parsed
	for name:String in NAMES:
		var index:int=rig.find_bone(name)
		if index<0:dispose();return false
		indices.append(index)
	for bone:int in rig.get_bone_count():
		if rig.get_bone_parent(bone)==indices[0] and not bone in indices:upper_boundaries.append(bone)
	player=AnimationPlayer.new()
	player.name="MixamoRefinedExperimentalLoops"
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.get_parent().add_child(player)
	player.root_node=NodePath("..")
	var library:=AnimationLibrary.new()
	for clip:Dictionary in data.clips:
		var id:String=String(clip.id)
		if not id.is_valid_filename() or clips.has(id):dispose();return false
		var loaded:Animation=load(DIRECTORY+id+".tres") as Animation
		if loaded==null:dispose();return false
		var animation:Animation=loaded.duplicate(true) as Animation
		for track:int in animation.get_track_count():
			var old:NodePath=animation.track_get_path(track)
			animation.track_set_path(track,NodePath(String(rig.name)+":"+String(old.get_subname(0))))
		library.add_animation(StringName(id),animation)
		clips[id]=clip
	player.add_animation_library("",library)
	return true

func metadata(id:String,time:float)->Dictionary:
	if not clips.has(id):return {}
	var clip:Dictionary=clips[id]
	var t:float=fposmod(time,float(clip.duration))
	var frames:Array=clip.frames
	var low:int=0
	var high:int=frames.size()-1
	while high-low>1:
		var middle:int=(low+high)>>1
		if float(frames[middle].time)<=t:low=middle
		else:high=middle
	var a:Dictionary=frames[low]
	var b:Dictionary=frames[high]
	var fraction:float=clampf((t-float(a.time))/maxf(.000000001,float(b.time)-float(a.time)),0.0,1.0)
	# Source contact is discrete, so interpolation brackets must not shorten it.
	var contact:Array[bool]=[false,false]
	for window:Dictionary in clip.windows:
		for cycle:int in [-1,0,1]:
			if t>=float(window.start_s)+float(cycle)*float(clip.duration) and t<float(window.end_s)+float(cycle)*float(clip.duration):contact[int(window.leg)]=true
	return {"id":id,"time":t,"frame":low,"next_frame":high,"fraction":fraction,
		"source_time":lerpf(float(a.source_time),float(b.source_time),fraction),
		"contact_candidate":contact}

func apply(id:String,time:float,preserve_upper:bool=true)->Dictionary:
	var meta:Dictionary=metadata(id,time)
	if meta.is_empty() or player==null:return {}
	var writes_hips:bool=bool(clips[id].writes_hips)
	var upper:Array[Transform3D]=[]
	if writes_hips and preserve_upper:
		for bone:int in upper_boundaries:upper.append(rig.get_bone_global_pose(bone))
	player.play(StringName(id))
	player.seek(float(meta.time),true)
	if writes_hips and preserve_upper:
		for index:int in upper_boundaries.size():rig.set_bone_global_pose(upper_boundaries[index],upper[index])
	return meta

func copy_modules(avatar:Node,writes_hips:bool)->void:
	var changed:PackedInt32Array=indices.duplicate() if writes_hips else indices.slice(1)
	if writes_hips:changed.append_array(upper_boundaries)
	var modules:Array=avatar.get("_modules")
	var maps:Array=avatar.get("_pose_maps")
	var offsets:Array=avatar.get("_module_rest_offsets")
	for item:int in modules.size():
		var module:Skeleton3D=modules[item]
		var mapping:PackedInt32Array=maps[item]
		var positions:PackedVector3Array=offsets[item]
		for bone:int in mapping.size():
			var source:int=mapping[bone]
			if not source in changed:continue
			module.set_bone_pose_position(bone,rig.get_bone_pose_position(source)+positions[bone])
			module.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(source))
			module.set_bone_pose_scale(bone,rig.get_bone_pose_scale(source))

func dispose()->void:
	if is_instance_valid(player):
		player.stop()
		if player.get_parent()!=null:player.get_parent().remove_child(player)
		player.free()
	player=null
	rig=null
	data.clear()
	clips.clear()
	indices.clear()
	upper_boundaries.clear()
