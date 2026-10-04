extends "res://tools/locomotion_physics_observer.gd"
## Separate telemetry revision. Both callbacks only read the real app. Late
## process timestamps are neither Avatar.present timestamps nor GPU presents.
var process_receiver:Callable
var physics_receiver:Callable
var latest_process:Dictionary={}
var upper_indices:=PackedInt32Array()

func configure(app:Node,player:Node3D,callback:Callable)->void:
	physics_receiver=callback
	super.configure(app,player,Callable(self,"_receive_physics"))
	process_priority=1000
	upper_indices.clear()
	var hips:int=rig.find_bone("hips")
	for bone:int in rig.get_bone_count():
		if rig.get_bone_parent(bone)==hips and rig.get_bone_name(bone) not in ["thighL","thighR"]:upper_indices.append(bone)

func configure_process(callback:Callable)->void:
	process_receiver=callback

func _receive_physics(observation:Dictionary)->void:
	observation["pose_observation"]=pose_observation()
	var presentation:RefCounted=avatar.get("_presentation")
	observation["helper_capture_reset"]=presentation.get("profile").get("packet_reset",null) if presentation!=null else null
	if physics_receiver.is_valid():physics_receiver.call(observation)

func _process(delta:float)->void:
	if not enabled or not is_instance_valid(actor):return
	var now:int=Time.get_ticks_usec()
	var cam:Camera3D=game.get("camera")
	var aim_cam:Camera3D=game.get("camera_rig").get("aim_camera")
	var presentation:RefCounted=avatar.get("_presentation")
	latest_process={"process_frame":Engine.get_process_frames(),"tick":Engine.get_physics_frames(),"wall_us":now,"process_game_dt_s":delta,
		"alpha":Engine.get_physics_interpolation_fraction(),"match_clock":game.get("match_clock"),"presentation_mode":avatar.get("presentation_mode"),
		"presentation_active":avatar.get("presentation_active"),"shown_root":_v(avatar.global_position),"actor_root":_v(actor.global_position),
		"root_observation":render_root_observation(Engine.get_physics_interpolation_fraction()),
		"camera_transform":transform_packet(cam.global_transform),"camera_fov":cam.fov,"aim_camera_transform":transform_packet(aim_cam.global_transform),"aim_camera_fov":aim_cam.fov,
		"helper_render_samples":presentation.get("render_samples") if presentation!=null else null,"helper_rendered":presentation.get("rendered") if presentation!=null else null,
		"actual_presentation_timestamp_us":null,"gpu_display_presentation_timestamp_us":null}
	if process_receiver.is_valid():process_receiver.call(latest_process)

func render_root_observation(alpha:float)->Dictionary:
	var presentation:RefCounted=avatar.get("_presentation")
	var active:bool=bool(avatar.get("presentation_active")) and presentation!=null and bool(presentation.get("valid"))
	var coherent:bool=active and avatar.get("presentation_mode") in ["coherent","coherent-pelvis"]
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

func pose_observation()->Dictionary:
	var hips:Transform3D=rig.get_bone_global_pose(rig.find_bone("hips"))
	var boundary:Array=[]
	for bone:int in upper_indices:
		var pose:Transform3D=rig.get_bone_global_pose(bone)
		boundary.append({"name":rig.get_bone_name(bone),"index":bone,"rig_space_transform":json_value(pose),"world_transform":json_value(rig.global_transform*pose)})
	return {"hips_rig_space_transform":json_value(hips),"hips_world_transform":json_value(rig.global_transform*hips),
		"rig_world_transform":json_value(rig.global_transform),"upper_boundary":boundary,"upper_boundary_count":boundary.size()}

func runtime_helper_observation()->Dictionary:
	var presentation:RefCounted=avatar.get("_presentation")
	if presentation==null:return {"available":false,"current_render_diagnostics":false}
	var names:Dictionary={}
	for property:Dictionary in presentation.get_property_list():names[String(property.name)]=true
	var result:Dictionary={"available":true,"helper_instance_id":presentation.get_instance_id(),"mode":avatar.get("presentation_mode"),"valid":presentation.get("valid"),"rendered":presentation.get("rendered"),
		"physics_samples":presentation.get("physics_samples"),"render_samples":presentation.get("render_samples"),"field_availability":{},
		"current_render_diagnostics":bool(avatar.get("presentation_active")) and bool(presentation.get("valid")) and bool(presentation.get("rendered")) and names.has("last_leg_diagnostics")}
	for field:String in ["profile","last_leg_diagnostics","expected_world_feet","actual_world_feet","last_pelvis_diagnostics","maximum_target_diagnostic"]:
		result.field_availability[field]=names.has(field)
		if names.has(field):result[field]=json_value(presentation.get(field))
	return result

static func json_value(value:Variant)->Variant:
	match typeof(value):
		TYPE_VECTOR2:return [value.x,value.y]
		TYPE_VECTOR3:return [value.x,value.y,value.z]
		TYPE_VECTOR4,TYPE_QUATERNION:return [value.x,value.y,value.z,value.w]
		TYPE_TRANSFORM3D:return [_v(value.basis.x),_v(value.basis.y),_v(value.basis.z),_v(value.origin)]
		TYPE_BASIS:return [_v(value.x),_v(value.y),_v(value.z)]
		TYPE_DICTIONARY:
			var result:Dictionary={}
			for key:Variant in value:result[str(key)]=json_value(value[key])
			return result
		TYPE_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_VECTOR4_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_STRING_ARRAY:
			var result:Array=[]
			for element:Variant in value:result.append(json_value(element))
			return result
		TYPE_OBJECT:return {"unserialized_object_class":value.get_class()} if value!=null else null
	return value
