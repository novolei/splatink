class_name MotoricaLocomotionPrototype
extends RefCounted
## Complete authored-time experimental clips. Never used by the production MM.
## Root trajectory is metadata; AnimationPlayer only writes hips/legs.
const DATA_PATH := "res://assets/animation/experiments/motorica/candidates.json"
const DIRECTORY := "res://assets/animation/experiments/motorica/"
const NAMES := ["hips","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
const MODES := ["source_path_pelvis9","fixed_authority_leg8"]
const SOLE_POINTS := [Vector3(0,-.085,-.065),Vector3(0,-.085,.11)]
var data:Dictionary = {}
var clips:Dictionary = {}
var skeleton:Skeleton3D
var player:AnimationPlayer
var indices := PackedInt32Array()
var upper_boundaries := PackedInt32Array()
var last_report:Dictionary = {}

func configure(rig:Skeleton3D) -> bool:
	dispose()
	var parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or rig==null or rig.get_bone_count()!=87:return false
	skeleton = rig
	data = parsed
	for bone:String in NAMES:
		var index:int = rig.find_bone(bone)
		if index<0:dispose();return false
		indices.append(index)
	for index:int in rig.get_bone_count():
		if rig.get_bone_parent(index)==indices[0] and not index in indices:upper_boundaries.append(index)
	player = AnimationPlayer.new()
	player.name = "MotoricaExperimentalOneShots"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.get_parent().add_child(player)
	player.root_node = NodePath("..")
	var library:=AnimationLibrary.new()
	for clip:Dictionary in data.clips:
		clips[String(clip.id)] = clip
		for mode:String in MODES:
			var variant:Dictionary = clip.variants[mode]
			var loaded:Animation = load(DIRECTORY+String(variant.id)+".tres") as Animation
			if loaded==null:dispose();return false
			var animation:Animation = loaded.duplicate(true) as Animation
			for track:int in animation.get_track_count():
				var old:NodePath = animation.track_get_path(track)
				animation.track_set_path(track,NodePath(String(rig.name)+":"+String(old.get_subname(0))))
			library.add_animation(StringName(variant.id),animation)
	player.add_animation_library("",library)
	return true

func sample_metadata(id:String,time:float,mode:String) -> Dictionary:
	if not clips.has(id) or not mode in MODES:return {}
	var clip:Dictionary = clips[id]
	var variant:Dictionary = clip.variants[mode]
	var t:float = clampf(time,0.0,float(clip.duration))
	var value:float = t*float(data.fps)
	var frames:Array = variant.frames
	var first:int = clampi(floori(value),0,frames.size()-1)
	var second:int = mini(first+1,frames.size()-1)
	var fraction:float = value-float(first)
	var a:Dictionary = frames[first]
	var b:Dictionary = frames[second]
	var yaw:float = lerpf(float(a.root_yaw),float(b.root_yaw),fraction)
	var root_position:Vector3 = _vec(a.target_reference_root_position_m).lerp(_vec(b.target_reference_root_position_m),fraction)
	var result:Dictionary = {"id":variant.id,"time":t,"duration":clip.duration,"frame":first,"fraction":fraction,
		"root_yaw":yaw,"root_position":root_position,"root_transform":Transform3D(Basis(Vector3.UP,yaw),root_position),
		"source_root_position_m":_vec(a.source_root_position_m).lerp(_vec(b.source_root_position_m),fraction),
		"source_root_velocity_mps":_vec(a.source_root_velocity_mps).lerp(_vec(b.source_root_velocity_mps),fraction),
		"target_reference_velocity_mps":_vec(a.target_reference_root_velocity_mps).lerp(_vec(b.target_reference_root_velocity_mps),fraction),
		"candidates":[false,false],"anchors":[Vector3.ZERO,Vector3.ZERO],"points":[0,0]}
	for side:int in 2:
		# Use the same inferred span at both keys. Never drag a real anchor toward
		# zero or across another contact span. These are measurements, not IK.
		var active:bool = bool(a.source_contact_candidate[side]) and bool(b.source_contact_candidate[side])
		var anchor_a:Vector3 = _vec(a.source_contact_span_anchor[side])
		var anchor_b:Vector3 = _vec(b.source_contact_span_anchor[side])
		active = active and anchor_a.distance_squared_to(anchor_b)<.0000000001
		result.candidates[side] = active
		result.anchors[side] = anchor_a
		result.points[side] = int(a.source_contact_proxy_index[side])
	return result

func apply(id:String,time:float,mode:String,preserve_upper:bool=true) -> Dictionary:
	var metadata:Dictionary = sample_metadata(id,time,mode)
	if metadata.is_empty() or player==null:return {}
	var fixed:bool = mode=="fixed_authority_leg8"
	var before:Array[Transform3D] = []
	if preserve_upper and not fixed:
		for index:int in upper_boundaries:before.append(skeleton.get_bone_global_pose(index))
	player.play(StringName(metadata.id))
	player.seek(float(metadata.time),true)
	if preserve_upper and not fixed:
		for item:int in upper_boundaries.size():skeleton.set_bone_global_pose(upper_boundaries[item],before[item])
	var maximum_slide:float = 0.0
	var contacts:int = 0
	var observed:Array = []
	for side:int in 2:
		if not bool(metadata.candidates[side]):continue
		var foot:int = skeleton.find_bone("foot"+("L" if side==0 else "R"))
		var actual:Vector3 = (metadata.root_transform as Transform3D)*(skeleton.get_bone_global_pose(foot)*SOLE_POINTS[int(metadata.points[side])])
		var error:float = actual.distance_to(metadata.anchors[side])
		maximum_slide = maxf(maximum_slide,error)
		contacts += 1
		observed.append({"side":side,"actual_clip_space":actual,"anchor":metadata.anchors[side],"error_m":error})
	last_report = {"mode":mode,"time":metadata.time,"original_duration":metadata.duration,
		"source_yaw_radians":metadata.root_yaw,"hips_written":not fixed,
		"compensated_upper_boundaries":upper_boundaries.size() if preserve_upper and not fixed else 0,
		"inferred_contacts":contacts,"actual_fk_proxy_slide_m":maximum_slide,"observed":observed,
		"contact_correction_applied":false,"root_motion_applied_by_animation":false,
		"contact_labels":"inferred source toe height/speed; measurements only"}
	return last_report

func capture_authority() -> Array[Dictionary]:
	var packets:Array[Dictionary] = []
	for bone:int in skeleton.get_bone_count():
		packets.append({"position":skeleton.get_bone_pose_position(bone),"rotation":skeleton.get_bone_pose_rotation(bone),"scale":skeleton.get_bone_pose_scale(bone)})
	return packets

func restore_authority(packets:Array[Dictionary]) -> void:
	if skeleton==null or packets.size()!=skeleton.get_bone_count():return
	for bone:int in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(bone,packets[bone].position)
		skeleton.set_bone_pose_rotation(bone,packets[bone].rotation)
		skeleton.set_bone_pose_scale(bone,packets[bone].scale)

func _vec(value:Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func dispose() -> void:
	if is_instance_valid(player):
		player.stop()
		if player.get_parent()!=null:player.get_parent().remove_child(player)
		player.free()
	player=null
	skeleton=null
	indices.clear()
	upper_boundaries.clear()
	clips.clear()
	data.clear()
