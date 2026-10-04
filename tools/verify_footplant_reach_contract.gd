extends SceneTree
## Scoped parity/invariant contract. Real-input motion quality is a separate gate.
var checks:int=0
var failures:Array[String]=[]
var output:String="res://shots/footplant-reach-contract"
var total_calls:int=0
var maximum_nonhip_translation_error:float=0.0
var maximum_scale_error:float=0.0

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--reach-output="):output=arg.trim_prefix("--reach-output=")
	_run.call_deferred()

func _check(label:String,passed:bool)->void:
	checks+=1
	if passed:return
	failures.append(label)
	if failures.size()<8:push_error("FOOTPLANT_REACH_CONTRACT "+label)

func _pose(rig:Skeleton3D)->Array:
	var result:Array=[]
	for bone:int in rig.get_bone_count():result.append([rig.get_bone_pose_position(bone),rig.get_bone_pose_rotation(bone),rig.get_bone_pose_scale(bone)])
	return result

func _copy_pose(source:Skeleton3D,target:Skeleton3D)->void:
	target.global_transform=source.global_transform
	for bone:int in source.get_bone_count():
		target.set_bone_pose_position(bone,source.get_bone_pose_position(bone))
		target.set_bone_pose_rotation(bone,source.get_bone_pose_rotation(bone))
		target.set_bone_pose_scale(bone,source.get_bone_pose_scale(bone))

func _make_rig(source:Skeleton3D,parent:Node3D)->Skeleton3D:
	var rig:=Skeleton3D.new()
	parent.add_child(rig)
	for bone:int in source.get_bone_count():rig.add_bone(String(source.get_bone_name(bone)))
	for bone:int in source.get_bone_count():
		rig.set_bone_parent(bone,source.get_bone_parent(bone))
		rig.set_bone_rest(bone,source.get_bone_rest(bone))
	_copy_pose(source,rig)
	return rig

func _state(plant:RefCounted)->Array:
	return [plant.get("_anchor").duplicate(),plant.get("_orientation").duplicate(),plant.get("_contact").duplicate(),plant.get("_weight").duplicate(),plant.get("_was_enabled"),plant.get("_last_root"),plant.get("_hip_drop"),plant.get("_planes").duplicate(),plant.get("contact_samples"),plant.get("max_contact_error"),plant.get("last_contact_error")]

func _run()->void:
	var actor:=Node3D.new()
	root.add_child(actor)
	var avatar:Node3D=load("res://scripts/characters/ink_avatar.gd").new()
	actor.add_child(avatar)
	avatar.set_process(false)
	_check("native provider actually active",bool(avatar.get("_native_motion_active")))
	_check("presentation disabled",avatar.get("presentation_mode")=="off")
	if not failures.is_empty():_finish();return
	var source:Skeleton3D=avatar.get("_skeleton")
	_check("original 87 bone rig",source.get_bone_count()==87)
	var rigs:Array[Skeleton3D]=[_make_rig(source,actor),_make_rig(source,actor),_make_rig(source,actor)]
	var legacy_script:Script=load("res://scripts/animation/ink_foot_plant.gd")
	var candidate_script:Script=load("res://scripts/animation/experiments/ink_foot_plant_continuous_reach.gd")
	for weapon:String in ["shooter","roller","charger","blaster","dualies","slosher","splatling"]:
		avatar.call("configure",Color("ff8a14"),weapon,{"hair":1,"hat":0,"outfit":4})
		avatar.set_process(false)
		var legacy:RefCounted=legacy_script.new()
		var trace:RefCounted=candidate_script.new()
		var continuous:RefCounted=candidate_script.new()
		trace.set("continuous_reach",false)
		continuous.set("continuous_reach",true)
		var providers:Array[RefCounted]=[legacy,trace,continuous]
		for i:int in 3:providers[i].call("configure",rigs[i])
		for tick:int in 180:
			var dt:float=.1 if tick%47==0 else 1.0/60.0
			var direction:=Vector3.ZERO if tick<15 or tick>145 else Vector3.BACK if tick<70 else Vector3.RIGHT if tick<110 else Vector3.FORWARD
			actor.position+=direction*5.5*dt
			if tick==125:actor.position+=Vector3(7,2,-11)
			avatar.call("animate",dt,{"velocity":direction*5.5,"speed":direction.length()*5.5,"desired_velocity":direction*5.5,"grounded":true,"form":"kid","is_local":true,"presentation_tick":true})
			source=avatar.get("_skeleton")
			var before:Array=_pose(source)
			var root_before:=actor.global_transform
			var motion:RefCounted=avatar.get("_motion")
			var motion_before:Dictionary=avatar.get("motion_state").duplicate(true)
			var external:Array[Dictionary]=[]
			if tick>=155 and tick<165:
				for side:String in ["L","R"]:
					var foot:Transform3D=source.global_transform*source.get_bone_global_pose(source.find_bone("foot"+side))
					external.append({"position":foot.origin,"rotation":foot.basis.orthonormalized().get_rotation_quaternion(),"planted":tick%2==0})
			var enabled:bool=not (tick>=90 and tick<96)
			trace.set("collect_reach_diagnostics",tick%2==0)
			for i:int in 3:
				_copy_pose(source,rigs[i])
				var plant:RefCounted=providers[i]
				if i>0:
					plant.set("raw_pose_hip_y",source.get_bone_pose_position(source.find_bone("hips")).y)
					plant.set("raw_pose_hip_y_available",true)
				plant.call("apply",rigs[i],dt,motion,avatar.global_position,Callable(),enabled,external)
				total_calls+=1
				if i>0:_check("per-call raw source token consumed",plant.get("raw_pose_hip_y_available")==false)
			_check("trace raw components exactly match original",_pose(rigs[0])==_pose(rigs[1]))
			_check("trace all original state exactly match original",_state(legacy)==_state(trace))
			_check("physics actor Root untouched",actor.global_transform==root_before)
			_check("matcher clocks and provider unchanged",avatar.get("motion_state")==motion_before)
			var candidate:Array=_pose(rigs[2])
			var hips:int=source.find_bone("hips")
			for bone:int in source.get_bone_count():
				maximum_scale_error=maxf(maximum_scale_error,(candidate[bone][2] as Vector3).distance_to(before[bone][2]))
				_check("all raw scales exact",candidate[bone][2]==before[bone][2])
				if String(source.get_bone_name(bone)) not in ["thighL","shinL","footL","thighR","shinR","footR"]:
					_check("non-solver raw rotations exact",candidate[bone][1]==before[bone][1])
				if bone==hips:
					_check("hips local XZ exact",candidate[bone][0].x==before[bone][0].x and candidate[bone][0].z==before[bone][0].z)
					continue
				maximum_nonhip_translation_error=maxf(maximum_nonhip_translation_error,(candidate[bone][0] as Vector3).distance_to(before[bone][0]))
				_check("all nonhips raw translations exact",candidate[bone][0]==before[bone][0])
	actor.queue_free()
	await process_frame
	_finish()

func _finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures,"apply_calls_across_three_providers":total_calls,"maximum_nonhip_local_translation_error_m":maximum_nonhip_translation_error,"maximum_raw_scale_error":maximum_scale_error,"accepted_for_production":false,"scope":"Original imported rig; alternating rich/minimal trace exact arithmetic/state, raw token consumption, and continuous local-link invariants. Direct synthetic provider inputs only; separate real-input quality required."}
	var file:=FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FOOTPLANT_REACH_CONTRACT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
