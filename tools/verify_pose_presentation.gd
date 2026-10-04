extends SceneTree
## Root runs headless logic and a separate eight-avatar GPU profile serially.
const Avatar=preload("res://scripts/characters/ink_avatar.gd")
const Actor=preload("res://scripts/game/ink_actor.gd")
var checks:=0
var failures:=0
var render_costs:Array[int]=[]
var restore_costs:Array[int]=[]
var capture_costs:Array[int]=[]
var maximum_pose_error:=0.0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("POSE_PRESENTATION watchdog");quit(1))
	call_deferred("_run")

func _check(label:String,passed:bool,detail:Variant=null) -> void:
	checks+=1
	if not passed:
		failures+=1
		push_error("POSE_PRESENTATION "+label+" "+str(detail))

func _run() -> void:
	var world:=Node3D.new()
	root.add_child(world)
	var original_motor:=Actor.new()
	var presented_motor:=Actor.new()
	world.add_child(original_motor)
	world.add_child(presented_motor)
	var original:=Avatar.new()
	var presented:=Avatar.new()
	original_motor.add_child(original)
	presented_motor.add_child(presented)
	original.force_lod=1
	presented.force_lod=1
	_check("presentation default disabled",not original.presentation_interpolation)
	presented.presentation_interpolation=true
	presented.set_process(false)
	await process_frame
	# Render rates exercise different fractional sample schedules without changing
	# the physical 60-Hz input, matcher query count, FK/IK or spring simulation.
	var rig:Skeleton3D=original._skeleton
	for frame:int in 180:
		var dt:float=1.0/60.0
		var direction:=Vector3.ZERO
		if frame>=20 and frame<80:direction=Vector3.BACK
		elif frame>=80 and frame<135:direction=Vector3.RIGHT
		original_motor.velocity=original_motor.horizontal_velocity(direction,5.5,false,false,true,dt)
		original_motor._face(dt,direction,false)
		original_motor.position+=original_motor.velocity*dt
		presented.restore_presentation()
		presented_motor.global_transform=original_motor.global_transform
		presented_motor.velocity=original_motor.velocity
		var state:Dictionary={"velocity":original_motor.velocity,"speed":original_motor.velocity.length(),"desired_velocity":direction*5.5,"desired_facing":original_motor.global_basis.z,"grounded":true,"form":"kid","is_local":true,"presentation_tick":true}
		if frame==45:
			original.trigger("hit",{"x":.4,"z":.8,"amp":.85})
			presented.trigger("hit",{"x":.4,"z":.8,"amp":.85})
		original.animate(dt,state)
		presented.animate(dt,state)
		_check("authoritative matcher state frame %d"%frame,original.motion_state==presented.motion_state)
		if frame==0:
			_check("full body authority capture",(presented._presentation._rigs[0].current as Array).size()==rig.get_bone_count())
			_check("only used body joints render",(presented._presentation._rigs[0].allowed as Dictionary).size()==51,presented._presentation._rigs[0].allowed.size())
		for bone:int in rig.get_bone_count():
			var a:=rig.get_bone_pose(bone)
			var b:=presented._skeleton.get_bone_pose(bone)
			var err:float=a.origin.distance_to(b.origin)
			maximum_pose_error=maxf(maximum_pose_error,err)
			_check("authoritative solved pose frame %d bone %d"%[frame,bone],err<.000002 and a.basis.is_equal_approx(b.basis))
		var before_time:float=presented._time
		var before_age:float=presented._inertializer._age
		var before_match:Dictionary=presented.motion_state.duplicate(true)
		var before_muzzle:Vector3=presented.get_muzzle()
		var before_aim:Vector3=presented.get_aim_muzzle(.4)
		var before_head:Vector3=presented.get_head_position()
		var before_motor:=presented_motor.global_transform
		for render_hz:int in [120,144,240]:
			var render_count:int=ceili(float(render_hz)/60.0)
			for sample:int in render_count:
				var fraction:float=float(sample+1)/float(render_count+1)
				_check("render presentation",presented.present(fraction))
				render_costs.append(int(presented.presentation_profile.get("render_us",0)))
				_check("render leaves physics root",presented_motor.global_transform.is_equal_approx(before_motor))
				_check("render leaves animation clocks",presented._time==before_time and presented._inertializer._age==before_age)
				_check("render leaves matcher",presented.motion_state==before_match)
				_check("render leaves authoritative muzzle",presented.get_muzzle().distance_to(before_muzzle)<.000002)
				_check("render leaves authoritative aiming",presented.get_aim_muzzle(.4).distance_to(before_aim)<.000002)
				_check("render leaves authoritative head",presented.get_head_position().distance_to(before_head)<.000002)
				for i:int in original._head_parameters.size():
					_check("render leaves source head solve inputs",original._head_parameters[i].transform==presented._head_parameters[i].transform)
		# Repeating a fractional pose must perform no redundant skeleton/node
		# writes; restoring and rendering the same fraction must still work.
		presented.present(.5)
		var halfway:=presented._skeleton.get_bone_pose(0)
		presented.present(.5)
		_check("unchanged render uploads no bones",int(presented.presentation_profile.get("bone_writes",-1))==0)
		_check("unchanged render uploads no nodes",int(presented.presentation_profile.get("node_writes",-1))==0)
		presented.restore_presentation()
		presented.present(.5)
		_check("render cache invalidated by restore",presented._skeleton.get_bone_pose(0).is_equal_approx(halfway))
		presented.restore_presentation()
		_check("restore current root",presented.global_transform.is_equal_approx(original.global_transform))
		restore_costs.append(int(presented.presentation_profile.get("restore_us",0)))
		capture_costs.append(int(presented.presentation_profile.get("capture_us",0)))
	# Rebuilds and teleports cannot interpolate from discarded geometry or an old
	# spawn. Cover the actual seven weapon modules, both forms, and a new style.
	for weapon:String in Avatar.WEAPONS:
		presented.configure(Color("ff8a14"),weapon,{"hair":3,"hat":2,"brows":1,"outfit":6,"eyes":4,"skin":3})
		presented.set_process(false)
		for form:String in ["kid","squid","swim","climb"]:
			presented.restore_presentation()
			presented.animate(1.0/60.0,{"presentation_tick":true,"grounded":true,"form":form,"velocity":Vector3(0,0,2),"speed":2.0,"wall_normal":Vector3.FORWARD})
			var physical:=presented.get_muzzle()
			_check("presentation after rebuild/form "+weapon+form,presented.present(.5) and presented.get_muzzle().distance_to(physical)<.000002)
			if not presented._kid.is_visible_in_tree():
				_check("hidden kid uploads no skeleton",int(presented.presentation_profile.get("bone_writes",-1))==0)
			presented.restore_presentation()
	presented.present(.1)
	presented_motor.position+=Vector3(27,4,-31)
	presented.reset_presentation()
	var spawned:=presented.global_transform
	for fraction:float in [0.0,.25,.5,.75,1.0]:
		presented.present(fraction)
		_check("teleport resets both packets",presented.global_transform.is_equal_approx(spawned))
	presented._presentation_local_only=true
	presented.animate(1.0/60.0,{"presentation_tick":true,"form":"kid","is_local":false})
	_check("local scope excludes remote",not presented.presentation_active)
	presented.animate(1.0/60.0,{"presentation_tick":true,"form":"kid","is_local":true})
	_check("local scope includes local",presented.presentation_active)
	presented.presentation_interpolation=false
	_check("disable restores tick state",not presented.presentation_active and not presented._presentation.rendered)
	print("POSE_PRESENTATION_PROFILE ",JSON.stringify({"render":_stats(render_costs),"restore":_stats(restore_costs),"capture":_stats(capture_costs),"bone_writes":presented.presentation_profile.get("bone_writes",0),"node_writes":presented.presentation_profile.get("node_writes",0),"maximum_authoritative_position_error":maximum_pose_error}))
	print("POSE_PRESENTATION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func _stats(values:Array[int]) -> Dictionary:
	if values.is_empty():return {}
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*.95)],"max":values[-1]}
