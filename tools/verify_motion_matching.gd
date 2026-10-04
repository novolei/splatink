extends SceneTree
## Root runs this via its serialized wrapper; watchdog catches script/runtime failures.
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Actor = preload("res://scripts/game/ink_actor.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("MOTION_CONTRACT watchdog"); quit(1))
	call_deferred("_run")
func _check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("MOTION_CONTRACT "+label+" "+str(detail))
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var avatar := Avatar.new()
	avatar.force_lod = 1
	world.add_child(avatar)
	await process_frame
	_check("real 1638 pose database",avatar.motion_state.get("database_poses",0)==1638)
	_check("63D pose velocity trajectory features",avatar.motion_state.get("feature_dimensions",0)==63)
	var scenarios := [{"velocity":Vector3.ZERO,"expect":"idle"},{"velocity":Vector3(0,0,5.5),"expect":"run"},{"velocity":Vector3(-4,0,0),"expect":"strafe_left"},{"velocity":Vector3(4,0,0),"expect":"strafe_right"},{"velocity":Vector3(0,0,-3),"expect":"backpedal"},{"velocity":Vector3.ZERO,"expect":"idle"}]
	var largest_pos := 0.0
	var largest_rotation := 0.0
	var start := Time.get_ticks_usec()
	for weapon in Avatar.WEAPONS:
		avatar.configure(Color("ff8a14"),weapon,{"hair":3,"outfit":6,"eyes":2})
		for scenario in scenarios:
			for i in 36:
				var v: Vector3 = scenario.velocity
				avatar.animate(1.0/60.0,{"speed":v.length(),"velocity":v,"desired_velocity":v,"desired_facing":Vector3.BACK,"grounded":true,"form":"kid","is_local":true})
				largest_pos = maxf(largest_pos,avatar._inertializer.max_position_delta)
				largest_rotation = maxf(largest_rotation,avatar._inertializer.max_rotation_delta)
			_check("matched direction "+weapon+" "+scenario.expect,String(avatar.motion_state.clip).ends_with("_"+String(scenario.expect)),avatar.motion_state)
		_check("actual query used "+weapon,avatar.motion_state.queries>5)
		_check("actual pose transition "+weapon,avatar.motion_state.transitions>2)
		_check("clip family respects weapon "+weapon,String(avatar.motion_state.clip).begins_with(weapon+"_"))
		avatar.trigger("shoot")
		for i in (60 if weapon=="roller" else 10): avatar.animate(1.0/60.0,{"speed":5.5,"velocity":Vector3(0,0,5.5),"firing":true,"rolling":weapon=="roller","grounded":true})
		_check("filtered action retained "+weapon,avatar._tree.get("parameters/Aim/blend_amount")>0.5)
		avatar.trigger("jump")
		avatar.animate(1.0/30.0,{"grounded":false,"velocity":Vector3(0,5,3),"form":"kid"})
		_check("air layer retained "+weapon,avatar._tree.get("parameters/Air/blend_amount")>0.1)
		for i in 9: avatar.animate(1.0/30.0,{"speed":8.0,"grounded":true,"form":"swim","velocity":Vector3(0,0,8)})
		_check("squid retained "+weapon,avatar._squid.visible)
		avatar.animate(1.0/30.0,{"grounded":true,"form":"kid"})
		avatar.set_dance("")
	var matcher := avatar._motion
	var target := 55
	for d in matcher._query.size(): matcher._query[d] = matcher._features[target*matcher._query.size()+d]
	_check("exact pose query zero distance",matcher._cost(target,INF)<0.000001)
	matcher._query[0] += 4.0
	_check("pose position affects match cost",matcher._cost(target,INF)>0.01)
	_check("inertial positions finite",is_finite(largest_pos),largest_pos)
	_check("inertial quaternion finite",is_finite(largest_rotation),largest_rotation)
	# At the instant a sampled clip changes, its inertialized output must retain
	# the last displayed pose. A dt-sized offset-clock lead broke this invariant.
	var transition_rig:=Skeleton3D.new()
	transition_rig.add_bone("hips")
	transition_rig.set_bone_pose(0,Transform3D(Basis(Vector3.UP,.23).scaled(Vector3(1.1,.95,1.0)),Vector3(.04,.52,-.03)))
	var held_position:=transition_rig.get_bone_pose_position(0)
	var held_rotation:=transition_rig.get_bone_pose_rotation(0)
	var held_scale:=transition_rig.get_bone_pose_scale(0)
	var transition_inertia:=InkInertializer.new()
	transition_inertia.configure(transition_rig)
	transition_rig.set_bone_pose(0,Transform3D(Basis(Vector3.RIGHT,-.8).scaled(Vector3(.9,1.05,1.0)),Vector3(-.08,.43,.11)))
	transition_inertia.apply(transition_rig,1.0/60.0,true,matcher,true)
	_check("new sampled clip retains last position at transition",transition_rig.get_bone_pose_position(0).distance_to(held_position)<0.000001)
	_check("new sampled clip retains last rotation at transition",InkInertializer._log_rotation(transition_rig.get_bone_pose_rotation(0)*held_rotation.inverse()).length()<0.00001)
	_check("new sampled clip retains last scale at transition",transition_rig.get_bone_pose_scale(0).distance_to(held_scale)<0.000001)
	transition_rig.free()
	# Separate visible locomotion measurements exclude weapon swaps, air/squid and full-body choreography.
	var runner := Avatar.new()
	runner.force_lod = 1
	runner.profile_animation = true
	world.add_child(runner)
	await process_frame
	var rig := runner._skeleton
	runner._foot_plant.collect_debug = true
	var observed := ["hips","spine","head","thighL","shinL","footL","thighR","shinR","footR"]
	var previous: Array[Quaternion] = []
	for name in observed: previous.append(rig.get_bone_pose_rotation(rig.find_bone(name)))
	var visible_step := 0.0
	var visible_position_step := 0.0
	var previous_hip := rig.get_bone_pose_position(rig.find_bone("hips"))
	var worst: Dictionary = {}
	for frame in 360:
		var v := Vector3.ZERO
		if frame>=45 and frame<140: v = Vector3(0,0,5.5)
		elif frame>=170 and frame<240: v = Vector3(0,0,-5.5)
		elif frame>=270 and frame<315: v = Vector3(4,0,0)
		if frame>=170 and frame<195: runner.rotation.y = lerpf(0.0,PI,float(frame-170)/25.0)
		runner.position += v/60.0
		runner.animate(1.0/60.0,{"speed":v.length(),"velocity":v,"desired_velocity":v,"desired_facing":runner.global_basis.z,"grounded":true,"form":"kid","is_local":true})
		if frame>=268 and frame<=278:
			print("MOTION_STOP_TRACE ",JSON.stringify({"frame":frame,"clip":runner.motion_state,"hips":rig.get_bone_pose_position(rig.find_bone("hips")),"kid_scale":runner._kid.scale,"legs":runner._foot_plant.last_debug}))
		for i in observed.size():
			var q := rig.get_bone_pose_rotation(rig.find_bone(observed[i]))
			if frame>20:
				var angle := InkInertializer._log_rotation(q*previous[i].inverse()).length()
				if angle>visible_step:
					visible_step = angle
					worst = {"frame":frame,"bone":observed[i],"rad":angle,"match":runner.motion_state,"contacts":runner._foot_plant._contact.duplicate(),"weights":runner._foot_plant._weight.duplicate(),"velocity":v,"pre_ik_rotation_delta":runner._inertializer.max_rotation_delta,"pre_ik_position_delta":runner._inertializer.max_position_delta,"hip_drop":runner._foot_plant._hip_drop}
			previous[i] = q
		var hip := rig.get_bone_pose_position(rig.find_bone("hips"))
		if frame>20: visible_position_step = maxf(visible_position_step,hip.distance_to(previous_hip))
		previous_hip = hip
	_check("visible 180 turn no quaternion discontinuity",visible_step<1.2,visible_step)
	_check("start stop pelvis continuity",visible_position_step<0.10,visible_position_step)
	_check("actual world foot contacts",runner._foot_plant.contact_samples>20,runner._foot_plant.contact_samples)
	_check("planted foot world error under 3cm",runner._foot_plant.max_contact_error<0.03,runner._foot_plant.max_contact_error)
	print("MOTION_VISIBLE 180turn_max_rad=",visible_step," hip_step_m=",visible_position_step," world_contacts=",runner._foot_plant.contact_samples," max_contact_error_m=",runner._foot_plant.max_contact_error)
	print("MOTION_WORST ",JSON.stringify(worst))
	_realistic_trace(world)
	avatar.motion_matching = false
	var first_local_pose:=-1
	for slot:int in 3:
		var startup_matcher:=InkMotionMatcher.new()
		startup_matcher.configure(avatar._skeleton,"shooter",slot)
		startup_matcher.step(1.0/60.0,avatar._skeleton,Vector3.ZERO,Vector3.ZERO,Vector3.BACK,true,true)
		if slot==0:first_local_pose=startup_matcher.matched_pose
		_check("local initial query independent of allocation slot %d"%slot,startup_matcher.query_count==1 and startup_matcher.matched_pose==first_local_pose,startup_matcher.debug_state())
	avatar.animate(1.0/30.0,{"speed":5.0,"velocity":Vector3(0,0,5),"grounded":true})
	_check("legacy blend fallback",avatar._tree.get("parameters/MotionSelection/blend_amount")==0.0)
	print("MOTION_CONTRACT ",checks," checks; ",failures," failures; script_us=",Time.get_ticks_usec()-start," max_position_step=",largest_pos," max_rotation_step=",largest_rotation)
	quit(1 if failures else 0)

func _realistic_trace(world: Node3D) -> void:
	# Exercise the actual source acceleration, braking, reversal and facing code.
	# The abrupt velocity trace above remains a separate animation stress case.
	var motor := Actor.new()
	world.add_child(motor)
	var runner := Avatar.new()
	runner.force_lod = 1
	runner.profile_animation = true
	motor.add_child(runner)
	var rig := runner._skeleton
	runner._foot_plant.collect_debug = true
	var observed := ["hips","spine","head","thighL","shinL","footL","thighR","shinR","footR"]
	var previous: Array[Quaternion] = []
	for name in observed: previous.append(rig.get_bone_pose_rotation(rig.find_bone(name)))
	var angular_step := 0.0
	var hip_step := 0.0
	var previous_hip := rig.get_bone_pose_position(rig.find_bone("hips"))
	var worst: Dictionary = {}
	var timing_samples: Dictionary = {}
	for frame in 360:
		var direction := Vector3.ZERO
		if frame>=45 and frame<140: direction = Vector3.BACK
		elif frame>=170 and frame<240: direction = Vector3.FORWARD
		elif frame>=270 and frame<315: direction = Vector3.RIGHT
		motor.velocity = motor.horizontal_velocity(direction,5.5,false,false,true,1.0/60.0)
		motor._face(1.0/60.0,direction,false)
		motor.position += motor.velocity/60.0
		runner.animate(1.0/60.0,{"speed":motor.velocity.length(),"velocity":motor.velocity,"desired_velocity":direction*5.5,"desired_facing":direction if not direction.is_zero_approx() else motor.global_basis.z,"grounded":true,"form":"kid","is_local":true})
		if frame>=175 and frame<=182:
			print("MOTION_RELEASE_TRACE ",JSON.stringify({"frame":frame,"velocity":motor.velocity,"root_yaw":motor.rotation.y,"match":runner.motion_state,"contacts":runner._foot_plant._contact,"weights":runner._foot_plant._weight,"legs":runner._foot_plant.last_debug}))
		if frame>20:
			for label in runner.animation_profile:
				if not timing_samples.has(label): timing_samples[label] = []
				(timing_samples[label] as Array).append(runner.animation_profile[label])
		for i in observed.size():
			var q := rig.get_bone_pose_rotation(rig.find_bone(observed[i]))
			if frame>20:
				var angle := InkInertializer._log_rotation(q*previous[i].inverse()).length()
				if angle>angular_step:
					angular_step = angle
					worst = {"frame":frame,"bone":observed[i],"rad":angle,"velocity":motor.velocity,"root_yaw":motor.rotation.y,"match":runner.motion_state,"contacts":runner._foot_plant._contact.duplicate(),"weights":runner._foot_plant._weight.duplicate(),"pre_ik_rotation_delta":runner._inertializer.max_rotation_delta,"legs":runner._foot_plant.last_debug.duplicate(true)}
			previous[i] = q
		var hip := rig.get_bone_pose_position(rig.find_bone("hips"))
		if frame>20: hip_step = maxf(hip_step,hip.distance_to(previous_hip))
		previous_hip = hip
	_check("actual physics visible rotation below 20 degrees per frame",angular_step<0.35,angular_step)
	_check("actual physics pelvis continuity below 8cm",hip_step<0.08,hip_step)
	_check("actual physics world foot contacts",runner._foot_plant.contact_samples>20,runner._foot_plant.contact_samples)
	_check("actual physics planted error below 3cm",runner._foot_plant.max_contact_error<0.03,runner._foot_plant.max_contact_error)
	print("MOTION_REALISTIC max_rad=",angular_step," hip_step_m=",hip_step," world_contacts=",runner._foot_plant.contact_samples," max_contact_error_m=",runner._foot_plant.max_contact_error)
	print("MOTION_REALISTIC_WORST ",JSON.stringify(worst))
	var profile: Dictionary = {}
	for label in timing_samples:
		var values: Array = timing_samples[label]
		values.sort()
		profile[label] = {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)],"max":values[-1]}
	print("AVATAR_PROFILE_US ",JSON.stringify(profile))
