extends "res://tools/locomotion_pelvis_physics_observer.gd"
## Physics reach telemetry revision. Getter-only in every observation stage.
## Actual Skeleton measurements stay separate from provider-declared before/after.
var reach_process_receiver:Callable
var bone_layout:Array=[]
var source_link_indices:=PackedInt32Array()
var _property_names_cache:Dictionary={}
var _reach_provider_id:int=0
var _reach_provider_ref:WeakRef
var _reach_json_call:int=-1
var _reach_json_valid:bool=false
var _reach_json:Dictionary={}

func configure(app:Node,player:Node3D,callback:Callable)->void:
	_property_names_cache.clear()
	_reach_provider_id=0
	_reach_provider_ref=null
	_invalidate_reach_json()
	super.configure(app,player,callback)
	bone_layout.clear()
	source_link_indices.clear()
	for bone:int in rig.get_bone_count():
		var parent:int=rig.get_bone_parent(bone)
		var rest:Transform3D=rig.get_bone_rest(bone)
		bone_layout.append({"index":bone,"name":rig.get_bone_name(bone),"parent_index":parent,
			"rest_local_position":_v(rest.origin),"rest_local_scale":_v(rest.basis.get_scale())})
	for name:String in ["hips","spine","hemF","hemB","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]:
		var bone:int=rig.find_bone(name)
		if bone>=0:source_link_indices.append(bone)

func configure_process(callback:Callable)->void:
	reach_process_receiver=callback
	super.configure_process(Callable(self,"_receive_reach_process"))

func _receive_physics(observation:Dictionary)->void:
	observation["reach_observation"]=reach_observation()
	observation["actual_body_pose"]=actual_body_pose_observation()
	observation["actor_reach_policies"]=actor_reach_policy_observation()
	super._receive_physics(observation)

func _receive_reach_process(observation:Dictionary)->void:
	observation["reach_observation"]=reach_observation()
	if reach_process_receiver.is_valid():reach_process_receiver.call(observation)

func _property_names(value:Object)->Dictionary:
	if value==null or not is_instance_valid(value):return {}
	var object_id:int=value.get_instance_id()
	if _property_names_cache.has(object_id):
		var cached:Dictionary=_property_names_cache[object_id]
		if cached.object_ref.get_ref()==value:return cached.names
		_property_names_cache.erase(object_id)
	var result:Dictionary={}
	for property:Dictionary in value.get_property_list():result[String(property.name)]=true
	_property_names_cache[object_id]={"object_ref":weakref(value),"names":result}
	return result

func _invalidate_reach_json()->void:
	_reach_json_valid=false
	_reach_json_call=-1
	# Replace, never clear a Dictionary retained by earlier observation rows.
	_reach_json={}

func _sync_reach_provider(foot:RefCounted)->void:
	var object_id:int=foot.get_instance_id() if foot!=null else 0
	var same_provider:bool=object_id==_reach_provider_id
	if foot==null:
		same_provider=same_provider and _reach_provider_ref==null
	else:
		same_provider=same_provider and _reach_provider_ref!=null and _reach_provider_ref.get_ref()==foot
	if same_provider:return
	_property_names_cache.erase(_reach_provider_id)
	_invalidate_reach_json()
	_reach_provider_id=object_id
	_reach_provider_ref=weakref(foot) if foot!=null else null

func _reach_diagnostic_json(diagnostic:Dictionary,call_value:Variant)->Dictionary:
	# Provider apply() increments apply_calls and assigns a NEW diagnostic for
	# every call, including reset/minimal gates. Its synchronous finish completes
	# before our post-game observations; no later stage mutates that call's data.
	# The converted tree is independent of the provider and is never modified.
	# A next call replaces our reference, leaving earlier rows' trees untouched.
	var cacheable:bool=not diagnostic.is_empty() and call_value is int and diagnostic.get("apply_calls") is int and diagnostic.apply_calls==call_value
	if not cacheable:
		_invalidate_reach_json()
		return json_value(diagnostic)
	if _reach_json_valid and _reach_json_call==call_value:return _reach_json
	var converted:Dictionary=json_value(diagnostic)
	_reach_json=converted
	_reach_json_call=call_value
	_reach_json_valid=true
	return _reach_json

func reach_observation()->Dictionary:
	var foot:RefCounted=avatar.get("_foot_plant")
	_sync_reach_provider(foot)
	var names:Dictionary=_property_names(foot)
	var avatar_names:Dictionary=_property_names(avatar)
	var result:Dictionary={"observation_tick":Engine.get_physics_frames(),"observed_wall_us":Time.get_ticks_usec(),
		"available":foot!=null,"diagnostic_available":false,"field_availability":{},
		"diagnostic_tick_matches_observation":null,"last_reach_diagnostics":{}}
	for field:String in ["_hip_drop","apply_calls","continuous_reach","raw_pose_hip_y","raw_pose_hip_y_available","measure_apply_time","pose_step_us"]:
		result.field_availability[field]=names.has(field)
		result[field]=json_value(foot.get(field)) if names.has(field) else null
	for field:String in ["footplant_reach_mode","footplant_continuous_reach","_footplant_reach_active","_native_motion_active","presentation_mode"]:
		result.field_availability[field]=avatar_names.has(field)
		result[field]=json_value(avatar.get(field)) if avatar_names.has(field) else null
	result.field_availability["last_reach_diagnostics"]=names.has("last_reach_diagnostics")
	if names.has("last_reach_diagnostics"):
		var diagnostic:Variant=foot.get("last_reach_diagnostics")
		if diagnostic is Dictionary:
			result.last_reach_diagnostics=_reach_diagnostic_json(diagnostic,result.apply_calls)
			result.diagnostic_available=not diagnostic.is_empty()
			if diagnostic.get("tick") is int:result.diagnostic_tick_matches_observation=diagnostic.tick==Engine.get_physics_frames()
		else:_invalidate_reach_json()
	else:_invalidate_reach_json()
	return result

func actor_reach_policy_observation()->Array:
	var result:Array=[]
	for peer:Node3D in game.get("actors"):
		var peer_avatar:Node3D=peer.get("avatar")
		var foot:RefCounted=peer_avatar.get("_foot_plant")
		var foot_names:Dictionary=_property_names(foot)
		var avatar_names:Dictionary=_property_names(peer_avatar)
		var packet:Dictionary={"actor_instance_id":peer.get_instance_id(),"is_local_player":peer==actor,
			"grounded":peer.call("is_grounded"),"form":peer.get("form"),"fields_available":{}}
		for field:String in ["footplant_reach_mode","footplant_continuous_reach","_footplant_reach_active","_native_motion_active","presentation_mode","presentation_active"]:
			packet.fields_available[field]=avatar_names.has(field)
			packet[field]=peer_avatar.get(field) if avatar_names.has(field) else null
		for field:String in ["continuous_reach","apply_calls"]:
			packet.fields_available[field]=foot_names.has(field)
			packet[field]=foot.get(field) if foot_names.has(field) else null
		packet.fields_available["last_reach_diagnostics"]=foot_names.has("last_reach_diagnostics")
		if foot_names.has("last_reach_diagnostics"):
			var diagnostic:Variant=foot.get("last_reach_diagnostics")
			if diagnostic is Dictionary:
				packet["diagnostic_tick"]=diagnostic.get("tick",null)
				packet["diagnostic_gate"]=diagnostic.get("gate",null)
				packet["diagnostic_continuous_reach"]=diagnostic.get("continuous_reach",null)
		result.append(packet)
	return result

func actual_body_pose_observation(include_components:bool=true)->Dictionary:
	var components:Array=[]
	if include_components:
		for bone:int in rig.get_bone_count():
			components.append({"index":bone,"position":_v(rig.get_bone_pose_position(bone)),"scale":_v(rig.get_bone_pose_scale(bone))})
	var hips:int=rig.find_bone("hips")
	var hip_rig:Transform3D=rig.get_bone_global_pose(hips)
	var links:Array=[]
	for bone:int in source_link_indices:
		var parent:int=rig.get_bone_parent(bone)
		var local_position:Vector3=rig.get_bone_pose_position(bone)
		var local_scale:Vector3=rig.get_bone_pose_scale(bone)
		var point:Vector3=rig.get_bone_global_pose(bone).origin
		var parent_point:Vector3=rig.get_bone_global_pose(parent).origin if parent>=0 else Vector3.ZERO
		var rig_vector:Vector3=point-parent_point
		var world_vector:Vector3=rig.global_basis*rig_vector
		links.append({"index":bone,"name":rig.get_bone_name(bone),"parent_index":parent,
			"local_position":_v(local_position),"local_scale":_v(local_scale),"local_link_length_m":local_position.length(),
			"rig_space_link_vector":_v(rig_vector),"rig_space_link_length_m":rig_vector.length(),
			"world_link_vector":_v(world_vector),"world_link_length_m":world_vector.length()})
	return {"tick":Engine.get_physics_frames(),"bone_count":rig.get_bone_count(),"hip_index":hips,
		"hips_local_y":rig.get_bone_pose_position(hips).y,"hips_rig_transform":json_value(hip_rig),
		"hips_world_transform":json_value(rig.global_transform*hip_rig),"rig_world_transform":json_value(rig.global_transform),
		"local_components":components,"all_local_components_recorded":include_components,"source_links":links,
		"measurement_scope":"Actual current Skeleton after ordinary game physics; no pre-FootPlant source pose is injected or inferred"}
