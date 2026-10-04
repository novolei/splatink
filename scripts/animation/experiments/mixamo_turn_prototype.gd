class_name MixamoTurnPrototype
extends RefCounted
## Isolated one-shot experiment. This class is never referenced by production MM.
## AnimationPlayer samples exported rest-corrected tracks at their original time.
## Preview yaw belongs to a separate visual root; apply() never moves that root.
const DATA_PATH := "res://assets/animation/experiments/mixamo/turns.json"
const NAMES := ["hips","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
const SOLE_POINTS := [Vector3(0,-.085,-.065),Vector3(0,-.085,.11)]
var data:Dictionary = {}
var clips:Dictionary = {}
var skeleton:Skeleton3D
var player:AnimationPlayer
var indices := PackedInt32Array()
var upper_boundaries := PackedInt32Array()
var last_report:Dictionary = {}
var _legs:Array[Dictionary] = []

func configure(rig:Skeleton3D) -> bool:
	dispose()
	skeleton = rig
	var parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or rig.get_bone_count()!=87:return false
	data = parsed
	indices.clear()
	upper_boundaries.clear()
	_legs.clear()
	clips.clear()
	for bone:String in NAMES:
		var index:int = rig.find_bone(bone)
		if index<0:return false
		indices.append(index)
	# Hips has three upper/garment children. Nine-bone preview can compensate
	# these boundaries to preserve upper GLOBAL poses; its upper LOCAL poses then
	# differ. Eight-bone mode changes neither upper local nor upper global poses.
	for index:int in rig.get_bone_count():
		if rig.get_bone_parent(index)==indices[0] and not index in indices:upper_boundaries.append(index)
	for side:String in ["L","R"]:
		var up:int = rig.find_bone("thigh"+side)
		var low:int = rig.find_bone("shin"+side)
		var foot:int = rig.find_bone("foot"+side)
		var a:Vector3 = rig.get_bone_rest(low).origin
		var b:Vector3 = rig.get_bone_rest(foot).origin
		_legs.append({"up":up,"low":low,"foot":foot,"parent":rig.get_bone_parent(up),"a":a.length(),"b":b.length(),"up_frame":_rest_frame(a),"low_frame":_rest_frame(b)})
	player = AnimationPlayer.new()
	player.name = "MixamoExperimentalOneShots"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.get_parent().add_child(player)
	player.root_node = NodePath("..")
	var library:=AnimationLibrary.new()
	for clip:Dictionary in data.clips:
		clips[String(clip.id)] = clip
		_register_animation(library,clip)
		for variant:Dictionary in clip.variants.values():_register_animation(library,variant)
	player.add_animation_library("",library)
	return true

func _register_animation(library:AnimationLibrary,clip:Dictionary) -> void:
	var animation:Animation = load("res://assets/animation/experiments/mixamo/"+String(clip.id)+".tres") as Animation
	if animation==null:return
	animation = animation.duplicate(true) as Animation
	for track:int in animation.get_track_count():
		var old:NodePath = animation.track_get_path(track)
		animation.track_set_path(track,NodePath(String(skeleton.name)+":"+String(old.get_subname(0))))
	library.add_animation(StringName(clip.id),animation)

func sample_metadata(id:String,time:float,mode:String) -> Dictionary:
	if not clips.has(id):return {}
	var base:Dictionary = clips[id]
	var clip:Dictionary = base if mode=="source_baseline" else base.variants.get(mode,{})
	if clip.is_empty():return {}
	var t:float = clampf(time,0.0,float(clip.duration))
	var value:float = t*float(data.fps)
	var first:int = clampi(floori(value),0,(clip.frames as Array).size()-1)
	var second:int = mini(first+1,(clip.frames as Array).size()-1)
	var fraction:float = value-float(first)
	var a:Dictionary = clip.frames[first]
	var b:Dictionary = clip.frames[second]
	var yaw:float = lerpf(float(a.root_yaw),float(b.root_yaw),fraction)
	var result:Dictionary = {"id":clip.id,"time":t,"duration":clip.duration,"root_yaw":yaw,"frame":first,"fraction":fraction,"weights":[0.0,0.0],"anchors":[Vector3.ZERO,Vector3.ZERO],"points":[0,0],"candidates":[false,false]}
	if a.has("contact_weight"):
		for side:int in 2:
			result.weights[side] = lerpf(float(a.contact_weight[side]),float(b.contact_weight[side]),fraction)
			# The zero-weight exterior sample has no anchor. Do not interpolate a
			# real constraint towards (0,0,0) when acquiring/releasing its window.
			var anchor_frame:Dictionary = a if bool(a.contact_candidate[side]) else b
			result.anchors[side] = _vec(anchor_frame.sole_anchor[side])
			result.points[side] = int(anchor_frame.sole_point[side])
			result.candidates[side] = bool(a.contact_candidate[side]) or bool(b.contact_candidate[side])
	return result

func apply(id:String,time:float,mode:String,preserve_upper:bool=true,refine_current_hips:bool=true) -> Dictionary:
	var metadata:Dictionary = sample_metadata(id,time,mode)
	if metadata.is_empty() or player==null or not player.has_animation(StringName(metadata.id)):return {}
	var fixed:bool = mode=="fixed_authority_leg8"
	var before:Array[Transform3D] = []
	if preserve_upper and not fixed:
		for index:int in upper_boundaries:before.append(skeleton.get_bone_global_pose(index))
	player.play(StringName(metadata.id))
	player.seek(float(metadata.time),true)
	if preserve_upper and not fixed:
		for item:int in upper_boundaries.size():skeleton.set_bone_global_pose(upper_boundaries[item],before[item])
	# Fixed-eight offline clips were baked on REST hips. Production upper holds
	# retain their own animated hips, so optional experiment IK solves the same
	# exported constraints against that actual parent without moving the hips.
	var reach_clamp:float = 0.0
	if fixed and refine_current_hips:
		for side:int in 2:
			var weight:float = float(metadata.weights[side])
			if weight<=0.0:continue
			var leg:Dictionary = _legs[side]
			var foot:Transform3D = skeleton.get_bone_global_pose(int(leg.foot))
			var point:Vector3 = SOLE_POINTS[int(metadata.points[side])]
			var endpoint:Vector3 = foot.origin.lerp((metadata.anchors[side] as Vector3)-foot.basis*point,weight)
			reach_clamp = maxf(reach_clamp,_solve(leg,endpoint,foot.basis.orthonormalized()))
	var maximum_error:float = 0.0
	var full_contacts:int = 0
	for side:int in 2:
		if float(metadata.weights[side])<.999:continue
		var leg:Dictionary = _legs[side]
		var actual:Vector3 = skeleton.get_bone_global_pose(int(leg.foot))*SOLE_POINTS[int(metadata.points[side])]
		if not fixed:actual=Basis(Vector3.UP,float(metadata.root_yaw))*actual
		maximum_error = maxf(maximum_error,actual.distance_to(metadata.anchors[side]))
		full_contacts += 1
	last_report = {"mode":mode,"time":metadata.time,"original_duration":metadata.duration,"source_yaw_radians":metadata.root_yaw,"hips_written":not fixed,"compensated_upper_boundaries":upper_boundaries.size() if preserve_upper and not fixed else 0,"full_contacts":full_contacts,"actual_fk_sole_error_m":maximum_error,"reach_clamp_m":reach_clamp,"contact_labels":"inferred; proxy heel/ball points","source_yaw_preview_context":not fixed,"synthesized_contact_refinement":fixed and refine_current_hips}
	return last_report

func _solve(leg:Dictionary,target:Vector3,end_rotation:Basis) -> float:
	var parent:Transform3D = skeleton.get_bone_global_pose(int(leg.parent))
	var origin:Vector3 = parent*skeleton.get_bone_pose_position(int(leg.up))
	var vector:Vector3 = target-origin
	var distance:float = vector.length()
	if distance<.000001:return 0.0
	var direction:Vector3 = vector/distance
	var a:float = float(leg.a)
	var b:float = float(leg.b)
	var limited:float = clampf(distance,absf(a-b)+.001,(a+b)*.9995)
	var cos_a:float = clampf((a*a+limited*limited-b*b)/(2.0*a*limited),-1.0,1.0)
	var animated:Vector3 = skeleton.get_bone_global_pose(int(leg.low)).origin-origin
	var original_up:Basis=skeleton.get_bone_global_pose(int(leg.up)).basis.orthonormalized()
	var original_low:Basis=skeleton.get_bone_global_pose(int(leg.low)).basis.orthonormalized()
	var raw_endpoint:Vector3=skeleton.get_bone_global_pose(int(leg.foot)).origin-origin
	var raw_direction:Vector3=raw_endpoint.normalized()
	# Compute the authored knee's signed bend plane against ITS OWN ankle.
	# Projecting that knee against a new constrained ankle can put the knee on
	# either side of the new line even though the authored leg never changes side.
	# Transport its original plane with the endpoint swing instead.
	var plane:Vector3=animated-raw_direction*animated.dot(raw_direction)
	if plane.length_squared()<.00000001:
		var forward:Vector3=end_rotation*Vector3.BACK
		plane=forward-raw_direction*forward.dot(raw_direction)
		if plane.length_squared()<.00000001:
			var lateral:Vector3=original_up*Vector3.RIGHT
			plane=lateral-raw_direction*lateral.dot(raw_direction)
	plane=Quaternion(raw_direction,direction)*plane.normalized()
	plane-=direction*plane.dot(direction)
	plane = plane.normalized()
	var knee:Vector3 = origin+direction*a*cos_a+plane*a*sqrt(maxf(0.0,1.0-cos_a*cos_a))
	var endpoint:Vector3 = origin+direction*limited
	var axis:Vector3 = (knee-origin).normalized()
	var low_axis:Vector3 = (endpoint-knee).normalized()
	# A bend plane determines joint POSITIONS, not the authored twist about the
	# segment. Rebuilding a full frame from n x direction rotated the thigh by
	# nearly pi when a small near-straight plane changed sign during release.
	# Shortest arcs change only the segment direction and preserve its raw twist.
	var raw_axis:Vector3=original_up*skeleton.get_bone_rest(int(leg.low)).origin.normalized()
	var raw_low_axis:Vector3=original_low*skeleton.get_bone_rest(int(leg.foot)).origin.normalized()
	var up:Basis=Basis(Quaternion(raw_axis.normalized(),axis))*original_up
	var low:Basis=Basis(Quaternion(raw_low_axis.normalized(),low_axis))*original_low
	skeleton.set_bone_pose_rotation(int(leg.up),(parent.basis.orthonormalized().inverse()*up).get_rotation_quaternion().normalized())
	skeleton.set_bone_pose_rotation(int(leg.low),(up.inverse()*low).get_rotation_quaternion().normalized())
	skeleton.set_bone_pose_rotation(int(leg.foot),(low.inverse()*end_rotation).get_rotation_quaternion().normalized())
	return absf(distance-limited)

static func _rest_frame(value:Vector3) -> Basis:
	var direction:Vector3 = value.normalized()
	var h:Vector3 = (Vector3.RIGHT-direction*Vector3.RIGHT.dot(direction)).normalized()
	return Basis(direction,h,direction.cross(h)).transposed()

static func _vec(value:Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func dispose() -> void:
	if is_instance_valid(player):player.free()
	player=null
	skeleton=null
