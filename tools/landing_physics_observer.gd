extends "res://tools/locomotion_physics_observer.gd"
## Supplement the frozen read-only post-game observer with landing gates.
## No controller/actor tick, animation advance, pose/contact write, or solver call.

var landing_receiver: Callable
var setup_epoch: int = 0
var landing_samples: int = 0
var have_edge_sample: bool = false
var previous_grounded: bool = false
var previous_jump: bool = false
var previous_velocity := Vector3.ZERO
var previous_position := Vector3.ZERO
var previous_landing_apply_count: int = -1

func configure(app: Node, player: Node3D, callback: Callable) -> void:
	landing_receiver = callback
	super.configure(app, player, Callable(self, "_after_production_tick"))
	have_edge_sample = false

func mark_setup_reset() -> void:
	# These are observer histories only. A production spawn_at is setup, not a
	# gameplay takeoff/landing, and must not count as a grounded edge.
	setup_epoch += 1
	have_edge_sample = false
	previous_jump = false
	have_contact_sample = false

func _after_production_tick(packet: Dictionary) -> void:
	landing_samples += 1
	var grounded: bool = bool(packet.grounded)
	var velocity: Vector3 = actor.get("velocity")
	var command: Dictionary = actor.get("_prev")
	var jump: bool = bool(command.get("jump", false))
	var edge: String = "none"
	if have_edge_sample and grounded != previous_grounded:
		edge = "land" if grounded else "takeoff"
	var foot: RefCounted = avatar.get("_foot_plant")
	var tree: AnimationTree = avatar.get("_tree")
	var action_node: AnimationNodeOneShot = avatar.get("_action_node")
	var action_clip: AnimationNodeAnimation = avatar.get("_action_clip")
	var motion: RefCounted = avatar.get("_motion")
	var action_active: bool = bool(tree.get("parameters/Action/active"))
	var filter_enabled: bool = action_node.filter_enabled
	var full_body: bool = action_active and not filter_enabled
	var hips_index: int = rig.find_bone("hips")
	var hips_frame: Transform3D = rig.global_transform * rig.get_bone_global_pose(hips_index)
	var source_motion: RefCounted = actor.get("_source_motion")
	var source_ground: RefCounted = source_motion.get("ground")
	var gait_eligible: bool = bool(avatar.get("motion_matching")) and motion != null and grounded
	gait_eligible = gait_eligible and String(avatar.get("_form")) == "kid" and not full_body and avatar.get("_dance").is_empty()
	packet["sample_id"] = landing_samples
	packet["setup_epoch"] = setup_epoch
	packet["first_after_setup"] = not have_edge_sample
	packet["grounded_edge"] = edge
	packet["previous_grounded"] = previous_grounded if have_edge_sample else null
	packet["previous_velocity"] = _v(previous_velocity) if have_edge_sample else []
	packet["previous_root"] = _v(previous_position) if have_edge_sample else []
	packet["jump_command_rising"] = jump and not previous_jump
	packet["land_time"] = actor.get("land_time")
	packet["land_speed"] = actor.get("land_speed")
	packet["hard_land"] = actor.get("_hard_land")
	packet["jump_buffer"] = actor.get("_jump_buffer")
	packet["coyote_time"] = actor.get("_coyote")
	packet["smooth_y"] = actor.get("smooth_y")
	packet["smooth_y_velocity"] = actor.get("smooth_y_velocity")
	packet["hips_world"] = _v(hips_frame.origin)
	packet["hips_world_transform"] = transform_packet(hips_frame)
	packet["hips_local_position"] = _v(rig.get_bone_pose_position(hips_index))
	packet["hips_local_rotation"] = _q(rig.get_bone_pose_rotation(hips_index))
	packet["hips_local_scale"] = _v(rig.get_bone_pose_scale(hips_index))
	packet["current_action"] = avatar.get("current_action")
	packet["action_active"] = action_active
	packet["action_filter_enabled"] = filter_enabled
	packet["action_full_body"] = full_body
	packet["action_clip"] = String(action_clip.animation)
	packet["action_request"] = tree.get("parameters/Action/request")
	packet["air_blend"] = avatar.get("_air_weight")
	packet["aim_blend"] = avatar.get("_aim_weight")
	packet["avatar_form"] = avatar.get("_form")
	packet["avatar_form_time"] = avatar.get("_form_time")
	packet["motion_rate"] = avatar.get("motion_state").get("rate", 1.0)
	packet["matched_pose"] = avatar.get("motion_state").get("pose", -1)
	packet["motion_script"] = motion.get_script().resource_path if motion != null else ""
	packet["desired_velocity"] = _v(actor.get("desired_velocity"))
	packet["desired_facing"] = _v(actor.get("desired_facing"))
	packet["look_yaw"] = game.get("_yaw")
	packet["source_physics_active"] = actor.get("source_physics") != null
	packet["source_landed"] = source_motion.get("landed")
	packet["source_land_speed"] = source_motion.get("land_speed")
	packet["source_air_time"] = source_motion.get("air_time")
	packet["source_ground"] = {"hit": source_ground.get("hit"), "y": source_ground.get("y"), "block": source_ground.get("block"), "face": source_ground.get("face")}
	packet["footplant"] = {"was_enabled": foot.get("_was_enabled"), "eligible_from_avatar_gates": gait_eligible,
		"contact": packet.contacts.contact, "weight": packet.contacts.weight, "anchor": packet.contacts.anchor,
		"hip_drop": foot.get("_hip_drop"), "last_root": _v(foot.get("_last_root")), "last_contact_error": foot.get("last_contact_error"),
		"reach_mode": avatar.get("footplant_reach_mode")}
	packet["landing_response"] = _landing_packet()
	previous_grounded = grounded
	previous_jump = jump
	previous_velocity = velocity
	previous_position = actor.global_position
	have_edge_sample = true
	latest = packet
	if landing_receiver.is_valid(): landing_receiver.call(packet)

func _has_property(object: Object, key: String) -> bool:
	for item: Dictionary in object.get_property_list():
		if String(item.name) == key: return true
	return false

func _landing_packet() -> Dictionary:
	# Only observe the helper. These targets/actuals belong to its earlier apply,
	# at the declared inertial order, before recoil/stance; packet.feet is final FK.
	if not _has_property(avatar, "_landing_response"):
		return {"available": false, "diagnostic_detail": "uncovered"}
	var helper: RefCounted = avatar.get("_landing_response")
	if helper == null:
		return {"available": false, "diagnostic_detail": "uncovered"}
	var helper_stage: String = "before_inertial_before_hit_and_stance"
	if _has_property(avatar, "landing_response_stage"):
		var declared_stage: Variant = avatar.get("landing_response_stage")
		if declared_stage is String and not declared_stage.is_empty(): helper_stage = declared_stage
	var result: Dictionary = {"available": true, "sample_stage": helper_stage,
		"coordinate_space": "primary_skeleton_rig", "pelvis_coordinate_space": "hips_local_yz",
		"final_fk_field": "feet", "diagnostic_detail": "optional_read_only"}
	var fields: Dictionary = {}
	for item: Dictionary in helper.get_property_list(): fields[String(item.name)] = true
	for key: String in ["active", "age", "amplitude", "heavy_weight", "trigger_count", "apply_count",
		"requested_pelvis", "applied_pelvis", "correction_feasible", "pelvis_correction_y",
		"correction_requested_y", "applied_hip_pitch", "last_foot_error", "last_foot_rotation_error",
		"last_reach_clamp_count", "pelvis", "lean_pitch", "head_pitch", "filtered_pelvis", "filter_count", "reset_epoch"]:
		if fields.has(key): result[key] = _json_value(helper.get(key))
	if fields.has("last_filter_diagnostics"):
		result["last_filter_diagnostics"] = _json_value(helper.get("last_filter_diagnostics"))
	if fields.has("last_diagnostics"):
		var diagnostics: Dictionary = helper.get("last_diagnostics")
		result["has_apply_diagnostics"] = not diagnostics.is_empty()
		result["last_diagnostics"] = _json_value(diagnostics)
	if result.has("apply_count"):
		var count: int = int(result.apply_count)
		result["applied_since_previous_observation"] = count > previous_landing_apply_count if previous_landing_apply_count >= 0 else null
		previous_landing_apply_count = count
	return result

func _json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2: return [value.x, value.y]
		TYPE_VECTOR3: return [value.x, value.y, value.z]
		TYPE_QUATERNION: return [value.x, value.y, value.z, value.w]
		TYPE_ARRAY:
			var array: Array = []
			for element: Variant in value: array.append(_json_value(element))
			return array
		TYPE_DICTIONARY:
			var dictionary: Dictionary = {}
			for key: Variant in value: dictionary[key] = _json_value(value[key])
			return dictionary
	return value
