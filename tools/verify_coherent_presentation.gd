extends SceneTree
## Imported-rig mutation/restore contract. This is separate from real input and
## visual quality acceptance; it intentionally exercises repeated render samples.
var checks:int=0
var failures:Array[String]=[]
var output:String="res://shots/coherent-presentation-contract"
var max_foot_error:float=0.0
var reach_clamps:int=0
var rendered_samples:int=0
var module_samples:int=0
var maximum_target_diagnostic:Dictionary={}
var maximum_world_length_error:float=0.0

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--coherent-output="):output=arg.trim_prefix("--coherent-output=")
	_run.call_deferred()

func _check(label:String,passed:bool)->void:
	checks+=1
	if passed:return
	failures.append(label)
	if failures.size()<12:push_error("COHERENT_CONTRACT "+label)

func _pose(rig:Skeleton3D)->Array:
	var result:Array=[]
	for bone:int in rig.get_bone_count():
		result.append([rig.get_bone_pose_position(bone),rig.get_bone_pose_rotation(bone),rig.get_bone_pose_scale(bone)])
	return result

func _feet(rig:Skeleton3D)->Array[Vector3]:
	return [rig.global_transform*rig.get_bone_global_pose(rig.find_bone("footL")).origin,rig.global_transform*rig.get_bone_global_pose(rig.find_bone("footR")).origin]

func _run()->void:
	var script:Script=load("res://scripts/characters/ink_avatar.gd") as Script
	var actor:=Node3D.new()
	root.add_child(actor)
	var avatar:Node3D=script.new()
	actor.add_child(avatar)
	avatar.set_process(false)
	_check("explicit coherent and native opt-ins",avatar.get("presentation_mode")=="coherent" and bool(avatar.get("_native_motion_active")))
	if not failures.is_empty():_finish();return
	avatar.call("configure",Color("ff8a14"),"shooter",{"hair":1,"hat":0,"brows":1,"outfit":4,"skin":3,"eyes":2})
	avatar.set_process(false)
	var rig:Skeleton3D=avatar.get("_skeleton")
	_check("original 87 joints",rig.get_bone_count()==87)
	var leg_ids:PackedInt32Array=avatar.get("_presentation_leg_indices")
	var previous_feet:Array[Vector3]=[]
	for tick:int in 180:
		avatar.call("restore_presentation")
		var direction:=Vector3.ZERO if tick<20 or tick>145 else Vector3.BACK if tick<80 else Vector3.RIGHT if tick<115 else Vector3.FORWARD
		actor.position+=direction*(5.5/60.0)
		actor.rotation.y=.5*sin(float(tick)*.025)
		var state:Dictionary={"velocity":direction*5.5,"speed":direction.length()*5.5,"desired_velocity":direction*5.5,"desired_facing":actor.global_basis.z,"grounded":true,"form":"kid","is_local":true,"presentation_tick":true}
		avatar.call("animate",1.0/60.0,state)
		var before:Array=_pose(rig)
		var modules:Array=[]
		for module:Skeleton3D in avatar.get("_modules"):modules.append(_pose(module))
		var tick_root:=avatar.global_transform
		var actor_root:=actor.global_transform
		var tick_feet:=_feet(rig)
		var before_match:Dictionary=avatar.get("motion_state").duplicate(true)
		var before_time:float=avatar.get("_time")
		var before_foot:RefCounted=avatar.get("_foot_plant")
		var foot_state:Array=[before_foot.get("_anchor").duplicate(),before_foot.get("_weight").duplicate(),before_foot.get("_contact").duplicate(),before_foot.get("_planes").duplicate(),before_foot.get("_hip_drop"),before_foot.get("contact_samples")]
		var before_muzzle:Vector3=avatar.call("get_muzzle")
		var before_aim:Vector3=avatar.call("get_aim_muzzle",.4)
		for alpha:float in [0.0,.13,.37,.71,1.0,.5,.5]:
			_check("render active",bool(avatar.call("present",alpha)))
			rendered_samples+=1
			_check("physics root exact",actor.global_transform==actor_root)
			_check("root basis current exact",avatar.global_basis==tick_root.basis)
			_check("camera target current authority",(avatar.call("presentation_position") as Vector3).distance_to(tick_root.origin)<.000001)
			_check("native clocks unchanged",avatar.get("motion_state")==before_match and avatar.get("_time")==before_time)
			_check("FootPlant state unchanged",foot_state==[before_foot.get("_anchor"),before_foot.get("_weight"),before_foot.get("_contact"),before_foot.get("_planes"),before_foot.get("_hip_drop"),before_foot.get("contact_samples")])
			_check("gameplay sockets unchanged",(avatar.call("get_muzzle") as Vector3).distance_to(before_muzzle)<.000002 and (avatar.call("get_aim_muzzle",.4) as Vector3).distance_to(before_aim)<.000002)
			for bone:int in rig.get_bone_count():
				if leg_ids.has(bone):continue
				_check("nonleg components exact",before[bone]==[rig.get_bone_pose_position(bone),rig.get_bone_pose_rotation(bone),rig.get_bone_pose_scale(bone)])
			if not previous_feet.is_empty():
				var shown_feet:=_feet(rig)
				for leg:int in 2:max_foot_error=maxf(max_foot_error,shown_feet[leg].distance_to(previous_feet[leg].lerp(tick_feet[leg],alpha)))
			reach_clamps+=int(avatar.get("presentation_profile").get("reach_clamps",0))
			maximum_world_length_error=maxf(maximum_world_length_error,float(avatar.get("presentation_profile").get("world_bone_length_error_m",0.0)))
			var diagnostic:Dictionary=avatar.get("_presentation").get("maximum_target_diagnostic")
			if float(diagnostic.get("expected_world_error_m",0.0))>float(maximum_target_diagnostic.get("expected_world_error_m",-1.0)):maximum_target_diagnostic=diagnostic.duplicate(true)
		avatar.call("restore_presentation")
		_check("all 87 components restored exactly",before==_pose(rig))
		_check("avatar local root restored exactly",avatar.global_transform==tick_root)
		for i:int in modules.size():
			module_samples+=1
			_check("module components restored exactly",modules[i]==_pose(avatar.get("_modules")[i]))
		previous_feet=tick_feet
	# Teleport while a moving packet is displayed: compare against an independent
	# authoritative local packet, never against the result of reset itself.
	for tick:int in 5:
		avatar.call("restore_presentation")
		actor.position+=Vector3(0,0,.1)
		avatar.call("animate",1.0/60.0,{"velocity":Vector3(0,0,6),"speed":6.0,"grounded":true,"form":"kid","is_local":true,"presentation_tick":true})
	var expected_local:Transform3D=avatar.transform
	avatar.call("present",.13)
	actor.position+=Vector3(23,2,-31)
	avatar.position.y=.34
	expected_local.origin.y=.34
	var expected_spawn:Transform3D=actor.global_transform*expected_local
	avatar.call("reset_presentation")
	_check("moving teleport restores authoritative local XZ",avatar.position.x==expected_local.origin.x and avatar.position.z==expected_local.origin.z)
	_check("moving teleport preserves caller Y",avatar.position.y==expected_local.origin.y)
	_check("moving teleport preserves authoritative basis",avatar.basis==expected_local.basis)
	for alpha:float in [0.0,.13,.5,1.0]:
		avatar.call("present",alpha)
		_check("moving teleport packets use independent authority",avatar.global_transform.is_equal_approx(expected_spawn))
	avatar.call("restore_presentation")
	# Rebuilds must clear old rig references; gates must not interpolate air/forms.
	for weapon:String in script.get_script_constant_map().WEAPONS:
		avatar.call("configure",Color("ff8a14"),weapon,{"hair":1,"hat":1,"outfit":2,"eyes":4})
		avatar.set_process(false)
		for mode:Dictionary in [{"form":"kid","grounded":true,"is_local":true},{"form":"kid","grounded":false,"is_local":true},{"form":"squid","grounded":true,"is_local":true},{"form":"kid","grounded":true,"is_local":false}]:
			avatar.call("restore_presentation")
			mode["presentation_tick"]=true
			# Avatar caps a single dt at .1 s. Advance real 60-Hz steps to cover the
			# .45 s form-settle gate rather than assuming one large dt completes it.
			for settle_tick:int in 30:avatar.call("animate",1.0/60.0,mode)
			var eligible:bool=mode.form=="kid" and mode.grounded and mode.is_local
			_check("state eligibility gate %s %s actual=%s native=%s form_time=%s ticks=%s"%[weapon,str(mode),str(avatar.get("presentation_active")),str(avatar.get("_native_motion_active")),str(avatar.get("_form_time")),str(avatar.get("_presentation_ticks"))],bool(avatar.get("presentation_active"))==eligible)
		avatar.call("animate",.5,{"form":"kid","grounded":true,"is_local":true,"presentation_tick":true})
		avatar.call("present",.3)
		actor.position+=Vector3(23,2,-31)
		avatar.call("reset_presentation")
		var spawned:=avatar.global_transform
		for alpha:float in [0.0,.25,.75,1.0]:
			avatar.call("present",alpha)
			_check("teleport resets packets",avatar.global_transform.is_equal_approx(spawned))
		avatar.call("restore_presentation")
	avatar.call("present",.31)
	avatar.set("presentation_interpolation",false)
	_check("disable restores and invalidates packet",not avatar.get("presentation_active") and not avatar.get("_presentation").get("valid"))
	avatar.call("animate",1.0/60.0,{"form":"kid","grounded":false,"is_local":false,"presentation_tick":true})
	avatar.set("presentation_interpolation",true)
	avatar.set_process(false)
	_check("reenable waits for physics eligibility",not avatar.get("presentation_active") and not bool(avatar.call("present",.5)))
	avatar.call("animate",1.0/60.0,{"form":"kid","grounded":true,"is_local":true,"presentation_tick":true})
	_check("eligible physics reactivates fresh packet",bool(avatar.get("presentation_active")) and bool(avatar.call("present",.5)))
	avatar.call("restore_presentation")
	actor.queue_free()
	await process_frame
	_finish()

func _finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures,"render_samples":rendered_samples,"module_restore_samples":module_samples,"maximum_world_fk_interpolation_error_m":max_foot_error,"maximum_world_bone_length_error_m":maximum_world_length_error,"maximum_target_diagnostic":maximum_target_diagnostic,"reach_clamps":reach_clamps,"accepted_for_production":false,"scope":"imported rig exact restoration and authority contract; separate real-input validation required"}
	var file:=FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("COHERENT_CONTRACT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
