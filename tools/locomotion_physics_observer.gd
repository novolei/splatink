extends Node
## Read-only observation after InkGame's ordinary physics tick. Never restores,
## presents, advances animation, changes a pose, or changes contact state.
const LOWER_NAMES := ["hips","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
var enabled:bool=false
var game:Node
var actor:Node3D
var avatar:Node3D
var rig:Skeleton3D
var receiver:Callable
var episodes:=PackedInt32Array([0,0])
var previous_anchors:=PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var previous_contact:Array[bool]=[false,false]
var have_contact_sample:bool=false
var latest:Dictionary={}

func configure(app:Node,player:Node3D,callback:Callable)->void:
	game=app;actor=player;avatar=actor.get("avatar");rig=avatar.get("_skeleton")
	receiver=callback
	# The real game owns all actor ticks at the default physics priority.
	# This observer runs after them; render sampling remains frame_post_draw.
	process_physics_priority=1000
	enabled=true

func _physics_process(delta:float)->void:
	if not enabled or not is_instance_valid(actor) or not is_instance_valid(rig):return
	var foot:RefCounted=avatar.get("_foot_plant")
	var active:Array=foot.get("_contact")
	var anchors:PackedVector3Array=foot.get("_anchor")
	for leg:int in 2:
		if (not have_contact_sample and (bool(active[leg]) or float(foot.get("_weight")[leg])>0.0)) or (have_contact_sample and ((bool(active[leg]) and not previous_contact[leg]) or anchors[leg]!=previous_anchors[leg])):
			episodes[leg]+=1
		previous_contact[leg]=bool(active[leg]);previous_anchors[leg]=anchors[leg]
	have_contact_sample=true
	var packets:Array=[]
	for name:String in LOWER_NAMES:
		var bone:int=rig.find_bone(name)
		packets.append({"name":name,"index":bone,"position":_v(rig.get_bone_pose_position(bone)),"rotation":_q(rig.get_bone_pose_rotation(bone)),"scale":_v(rig.get_bone_pose_scale(bone))})
	var capture:Dictionary=capture_observation()
	var command:Dictionary=actor.get("_prev")
	var motion:Dictionary=avatar.get("motion_state")
	var contact:Dictionary=contact_observation()
	var feet:Array=[]
	var foot_rotations:Array=[]
	var foot_errors:Array=[]
	for leg:int in 2:
		var world:Transform3D=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("footL" if leg==0 else "footR"))
		feet.append(_v(world.origin))
		foot_rotations.append(_q(world.basis.orthonormalized().get_rotation_quaternion()))
		var anchor:Array=contact.anchor[leg]
		foot_errors.append(_v(world.origin-Vector3(float(anchor[0]),float(anchor[1]),float(anchor[2]))))
	var velocity:Vector3=actor.get("velocity")
	latest={"tick":Engine.get_physics_frames(),"wall_us":Time.get_ticks_usec(),"match_clock":game.get("match_clock"),"physics_game_dt":delta,
		"actor_root_transform":transform_packet(actor.global_transform),"avatar_root_transform":transform_packet(avatar.global_transform),
		"avatar_local_transform":transform_packet(avatar.transform),"rig_transform":transform_packet(rig.global_transform),"velocity":_v(velocity),"speed":Vector2(velocity.x,velocity.z).length(),"lower_exact_components":packets,
		"capture":capture,"contacts":contact,"feet":feet,"feet_rotations":foot_rotations,"contact_error_vectors":foot_errors,"muzzle":muzzle_observation(),
		"aim_point":_v(actor.get("aim_point")),"aim_dir":_v(actor.get("aim_dir")),"aim_yaw":actor.get("aim_yaw"),"aim_pitch":actor.get("aim_pitch"),
		"actual_command":{"move":_v(command.get("move",Vector3.ZERO)),"fire":bool(command.get("fire",false)),"jump":bool(command.get("jump",false)),"swim":bool(command.get("swim",false)),"aim_yaw":command.get("aim_yaw",0.0),"aim_pitch":command.get("aim_pitch",0.0)},
		"native_queries":motion.get("native_queries",0),"motion_queries":motion.get("queries",0),"motion_transitions":motion.get("transitions",0),
		"clip":motion.get("clip",""),"motion_time":motion.get("time",0.0),"grounded":actor.call("is_grounded"),"form":actor.get("form"),"presentation_active":avatar.get("presentation_active")}
	if receiver.is_valid():receiver.call(latest)

func capture_observation()->Dictionary:
	var presentation:RefCounted=avatar.get("_presentation")
	var eligible:bool=bool(avatar.get("presentation_active")) and presentation!=null and bool(presentation.get("valid"))
	var result:Dictionary={"eligible":eligible,"component_bones":0,"component_bone_names":[],"component_mismatches":0,"components_exact":true,
		"maximum_position_error_m":0.0,"maximum_quaternion_component_error":0.0,"maximum_scale_component_error":0.0,
		"root_global_exact":false,"root_local_exact":false,"root_global_position_error_m":0.0,"root_global_basis_error":0.0}
	if not eligible:return result
	var current:Transform3D=presentation.get("_current_root")
	var local:Transform3D=presentation.get("_tick_local_root")
	result.packet_previous_root=transform_packet(presentation.get("_previous_root"))
	result.packet_current_root=transform_packet(current)
	result.packet_local_root=transform_packet(local)
	result.packet_rendered=bool(presentation.get("rendered"))
	result.packet_capture_count=presentation.get("physics_samples")
	result.root_global_exact=avatar.global_transform==current
	result.root_local_exact=avatar.transform==local
	result.root_global_position_error_m=avatar.global_position.distance_to(current.origin)
	result.root_global_basis_error=_basis_error(avatar.global_basis,current.basis)
	for entry:Dictionary in presentation.get("_rigs"):
		if entry.node!=rig:continue
		var indices:PackedInt32Array=entry.indices
		for item:int in indices.size():
			var bone:int=indices[item]
			var position:Vector3=rig.get_bone_pose_position(bone)
			var rotation:Quaternion=rig.get_bone_pose_rotation(bone)
			var scale:Vector3=rig.get_bone_pose_scale(bone)
			var same:bool=position==entry.positions[item] and rotation==entry.rotations[item] and scale==entry.scales[item]
			result.component_bones=int(result.component_bones)+1
			result.component_bone_names.append(rig.get_bone_name(bone))
			if not same:result.component_mismatches=int(result.component_mismatches)+1
			result.maximum_position_error_m=maxf(float(result.maximum_position_error_m),position.distance_to(entry.positions[item]))
			result.maximum_quaternion_component_error=maxf(float(result.maximum_quaternion_component_error),_quaternion_component_error(rotation,entry.rotations[item]))
			result.maximum_scale_component_error=maxf(float(result.maximum_scale_component_error),scale.distance_to(entry.scales[item]))
	result.components_exact=int(result.component_mismatches)==0 and int(result.component_bones)>0
	return result

func contact_observation()->Dictionary:
	var foot:RefCounted=avatar.get("_foot_plant")
	var active:Array=foot.get("_contact")
	var weight:Array=foot.get("_weight")
	var anchors:PackedVector3Array=foot.get("_anchor")
	var orientations:Array=foot.get("_orientation")
	return {"contact":[bool(active[0]),bool(active[1])],"weight":[float(weight[0]),float(weight[1])],
		"anchor":[_v(anchors[0]),_v(anchors[1])],"orientation":[_q(orientations[0]),_q(orientations[1])],"episode":[episodes[0],episodes[1]]}

func muzzle_observation()->Dictionary:
	var marker:Node3D=avatar.get("_muzzle")
	var pivot:Node3D=avatar.get("_weapon_r")
	var authority:Vector3=avatar.call("get_muzzle")
	if not is_instance_valid(marker) or not is_instance_valid(pivot):return {"available":false,"authoritative":_v(authority)}
	# Cancel the attachment's potentially deferred transform by deriving the
	# marker's local transform, then reconstruct from the ACTUAL current hand FK.
	# No presentation muzzle/head cache is used for the visible socket.
	var local_marker:Transform3D=pivot.global_transform.affine_inverse()*marker.global_transform
	var hand:Transform3D=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("handR"))
	var shown:Transform3D=hand*pivot.transform*local_marker
	return {"available":true,"authoritative":_v(authority),"visible_fk":_v(shown.origin),"visible_transform":transform_packet(shown),
		"visible_node":_v(marker.global_position),"visible_node_fk_error_m":marker.global_position.distance_to(shown.origin),
		"visible_authority_distance_m":shown.origin.distance_to(authority)}

func render_root_observation(alpha:float)->Dictionary:
	var presentation:RefCounted=avatar.get("_presentation")
	var active:bool=bool(avatar.get("presentation_active")) and presentation!=null and bool(presentation.get("valid"))
	var coherent:bool=active and avatar.get("presentation_mode")=="coherent"
	var interpolated:bool=active and (coherent or bool(presentation.get("_interpolate_root")))
	var authority:Transform3D=avatar.global_transform
	var expected:Transform3D=avatar.global_transform
	if active:
		authority=presentation.call("authoritative_root",avatar)
		expected=authority
		if interpolated:
			var previous:Transform3D=presentation.get("_previous_root")
			var current:Transform3D=presentation.get("_current_root")
			if coherent:
				expected=current
				expected.origin=previous.origin.lerp(current.origin,clampf(alpha,0.0,1.0))
			else:expected=previous.interpolate_with(current,clampf(alpha,0.0,1.0))
	return {"interpolation_expected":interpolated,"root_origin_only":coherent,"presentation_packet_available":active,
		"authoritative_avatar_root":transform_packet(authority),"shown_root_transform":transform_packet(avatar.global_transform),"expected_shown_root_transform":transform_packet(expected),
		"expected_root_position_error_m":avatar.global_position.distance_to(expected.origin),"expected_root_basis_error":_basis_error(avatar.global_basis,expected.basis),
		"shown_authority_distance_m":avatar.global_position.distance_to(authority.origin)}

static func transform_packet(value:Transform3D)->Dictionary:
	return {"position":_v(value.origin),"rotation":_q(value.basis.orthonormalized().get_rotation_quaternion()),"scale":_v(value.basis.get_scale())}
static func _v(value:Vector3)->Array:return [value.x,value.y,value.z]
static func _q(value:Quaternion)->Array:return [value.x,value.y,value.z,value.w]
static func _basis_error(a:Basis,b:Basis)->float:return maxf((a.x-b.x).length(),maxf((a.y-b.y).length(),(a.z-b.z).length()))
static func _quaternion_component_error(a:Quaternion,b:Quaternion)->float:return maxf(maxf(absf(a.x-b.x),absf(a.y-b.y)),maxf(absf(a.z-b.z),absf(a.w-b.w)))
