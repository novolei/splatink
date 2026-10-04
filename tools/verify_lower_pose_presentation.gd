extends SceneTree
## Root runs this through the serialized engine wrapper. Presentation never advances
## the source animation/IK clocks; both the control and presented avatars use native MM.
const Avatar=preload("res://scripts/characters/ink_avatar.gd")
const Actor=preload("res://scripts/game/ink_actor.gd")
const NativeMatcher=preload("res://scripts/animation/native_motion_matcher.gd")
const LEGS:=["thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
var checks:=0
var failures:=0
var capture_us:Array[int]=[]
var restore_us:Array[int]=[]
var render_us:Array[int]=[]
var render_contact_samples:=0
var render_contact_error:=0.0
var held_packet_samples:=0
var changed_swing_samples:=0
var swing_writes:=0
var held_slots:=0
var maximum_tick_angle:=0.0
var maximum_render_angle:=0.0
var maximum_upper_error:=0.0
var worst:Dictionary={}

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("LOWER_PRESENTATION watchdog");quit(1))
	call_deferred("_run")

func _check(label:String,passed:bool,detail:Variant=null)->void:
	checks+=1
	if not passed:
		failures+=1
		if failures<=24:push_error("LOWER_PRESENTATION "+label+" "+str(detail))

func _run()->void:
	_check("real native query API",NativeMatcher.available())
	if not NativeMatcher.available():quit(1);return
	var world:=Node3D.new()
	root.add_child(world)
	var control_motor:=Actor.new()
	var shown_motor:=Actor.new()
	world.add_child(control_motor)
	world.add_child(shown_motor)
	var control:=Avatar.new()
	var shown:=Avatar.new()
	control.native_locomotion_mm=true
	shown.native_locomotion_mm=true
	control.force_lod=1
	shown.force_lod=1
	shown._presentation_lower_only=true
	control_motor.add_child(control)
	shown_motor.add_child(shown)
	# CLI may enable both avatars during _ready. The control is always unpresented.
	control.presentation_interpolation=false
	shown.presentation_interpolation=true
	control.set_process(false)
	shown.set_process(false)
	await process_frame
	_check("lower mode selected",shown.presentation_mode=="lower")
	_check("one captured body rig",shown._presentation._rigs.size()==1)
	_check("exactly eight captured joints",(shown._presentation._rigs[0].indices as PackedInt32Array).size()==8)
	_check("no module/node/material interpolation",shown._presentation._nodes.is_empty() and shown._presentation._materials.is_empty())
	_check("owner root interpolation disabled",not shown._presentation._interpolate_root)
	for bone:int in shown._presentation._rigs[0].indices:
		_check("only leg channels captured",String(shown._skeleton.get_bone_name(bone)) in LEGS)
	var rig:Skeleton3D=shown._skeleton
	var previous_tick:Array[Quaternion]=[]
	var previous_render:Array[Quaternion]=[]
	for name:String in LEGS:
		previous_tick.append(rig.get_bone_pose_rotation(rig.find_bone(name)))
		previous_render.append(previous_tick[-1])
	for frame:int in 360:
		var dt:float=1.0/60.0
		var direction:=Vector3.ZERO
		if frame>=45 and frame<140:direction=Vector3.BACK
		elif frame>=170 and frame<240:direction=Vector3.FORWARD
		elif frame>=270 and frame<315:direction=Vector3.RIGHT
		control_motor.velocity=control_motor.horizontal_velocity(direction,5.5,false,false,true,dt)
		control_motor._face(dt,direction,false)
		control_motor.position+=control_motor.velocity*dt
		shown.restore_presentation()
		shown_motor.global_transform=control_motor.global_transform
		shown_motor.velocity=control_motor.velocity
		var state:Dictionary={"speed":control_motor.velocity.length(),"velocity":control_motor.velocity,"desired_velocity":direction*5.5,"desired_facing":direction if not direction.is_zero_approx() else control_motor.global_basis.z,"grounded":true,"form":"kid","is_local":true,"presentation_tick":true}
		control.animate(dt,state)
		shown.animate(dt,state)
		_check("native providers retained",control._motion is NativeMatcher and shown._motion is NativeMatcher)
		_check("native query and clip schedule identical",control._motion.query_count==shown._motion.query_count and control._motion.matched_pose==shown._motion.matched_pose and control._motion.sample_time==shown._motion.sample_time)
		for bone:int in rig.get_bone_count():
			_check("raw control pose frame %d bone %d"%[frame,bone],_raw_bone(control._skeleton,bone)==_raw_bone(rig,bone))
		for i:int in LEGS.size():
			var q:=rig.get_bone_pose_rotation(rig.find_bone(LEGS[i]))
			if frame>20:maximum_tick_angle=maxf(maximum_tick_angle,InkInertializer._log_rotation(q*previous_tick[i].inverse()).length())
			previous_tick[i]=q
		var tick_components:Array[Dictionary]=[]
		var tick_globals:Array[Transform3D]=[]
		for bone:int in rig.get_bone_count():
			tick_components.append(_raw_bone(rig,bone))
			tick_globals.append(rig.get_bone_global_pose(bone))
		var clocks:=_clocks(shown)
		var nodes:=_node_packets(shown)
		var sent:=_material_packets(shown)
		var modules:=_module_packets(shown)
		var before_root:=shown.global_transform
		var before_motor:=shown_motor.global_transform
		var before_muzzle:=shown.get_muzzle()
		var before_aim:=shown.get_aim_muzzle(.4)
		var before_head:=shown.get_head_position()
		# Separate schedules exercise actual sub-tick FK under an unchanged current
		# root/hips. World-contact checks read the presented rig, not IK telemetry.
		for hz:int in [120,144,240]:
			var count:int=ceili(float(hz)/60.0)
			for sample:int in count+1:
				var fraction:float=float(sample)/float(count)
				_check("lower rendering active",shown.present(fraction))
				render_us.append(int(shown.presentation_profile.get("render_us",0)))
				swing_writes+=int(shown.presentation_profile.get("bone_writes",0))
				held_slots+=int(shown.presentation_profile.get("held_bones",0))
				_check("render changes no root",shown.global_transform==before_root and shown_motor.global_transform==before_motor)
				_check("render changes no clocks",_clocks(shown)==clocks)
				_check("render changes no nodes or materials",_node_packets(shown)==nodes and _material_packets(shown)==sent)
				if hz==144 and sample==1:_check("hair and brow raw packets remain unchanged",_module_packets(shown)==modules)
				_check("world muzzle/head/aim remain authoritative",shown.get_muzzle()==before_muzzle and shown.get_aim_muzzle(.4)==before_aim and shown.get_head_position()==before_head)
				_check("camera presentation position remains tick",shown.presentation_position()==before_root.origin)
				for bone:int in rig.get_bone_count():
					if String(rig.get_bone_name(bone)) in LEGS:continue
					var pose:=rig.get_bone_global_pose(bone)
					maximum_upper_error=maxf(maximum_upper_error,pose.origin.distance_to(tick_globals[bone].origin))
					_check("upper global and raw packet unchanged",pose==tick_globals[bone] and _raw_bone(rig,bone)==tick_components[bone])
				for leg:int in 2:
					var contact:bool=bool(shown._foot_plant._contact[leg])
					if contact:
						for offset:int in 4:
							var index:int=rig.find_bone(LEGS[leg*4+offset])
							_check("contact leg holds exact tick packet",_raw_bone(rig,index)==tick_components[index])
							held_packet_samples+=1
						if float(shown._foot_plant._weight[leg])>.999:
							var ankle:=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("footL" if leg==0 else "footR")).origin
							var error:float=ankle.distance_to(shown._foot_plant._anchor[leg])
							if error>render_contact_error:worst={"frame":frame,"hz":hz,"fraction":fraction,"leg":leg,"error":error,"ankle":ankle,"anchor":shown._foot_plant._anchor[leg],"weight":shown._foot_plant._weight[leg]}
							render_contact_error=maxf(render_contact_error,error)
							render_contact_samples+=1
					else:
						for offset:int in 4:
							var index:int=rig.find_bone(LEGS[leg*4+offset])
							if _raw_bone(rig,index)!=tick_components[index]:changed_swing_samples+=1
				# A monotone 144Hz schedule is the continuity measurement. Other
				# schedules restart alpha at zero and are not adjacent render frames.
				if hz==144:
					for i:int in LEGS.size():
						var q:=rig.get_bone_pose_rotation(rig.find_bone(LEGS[i]))
						if frame>20:maximum_render_angle=maxf(maximum_render_angle,InkInertializer._log_rotation(q*previous_render[i].inverse()).length())
						previous_render[i]=q
		shown.present(.5)
		shown.present(.5)
		_check("same fraction causes no new bone uploads",int(shown.presentation_profile.get("bone_writes",-1))==0)
		_check("lower mode never writes scene nodes",int(shown.presentation_profile.get("node_writes",-1))==0)
		shown.restore_presentation()
		for bone:int in rig.get_bone_count():_check("exact raw restore",_raw_bone(rig,bone)==tick_components[bone])
		capture_us.append(int(shown.presentation_profile.get("capture_us",0)))
		restore_us.append(int(shown.presentation_profile.get("restore_us",0)))
	_check("strict tick angular continuity retained",maximum_tick_angle<.35,maximum_tick_angle)
	_check("strict render angular continuity",maximum_render_angle<.35,maximum_render_angle)
	_check("render world contacts are actually sampled",render_contact_samples>20,render_contact_samples)
	_check("presented planted ankle stays below3cm",render_contact_error<.03,worst)
	_check("upper global poses exactly unchanged",maximum_upper_error==0.0,maximum_upper_error)
	_check("stance and swing policies are both exercised",held_packet_samples>20 and changed_swing_samples>20,{"held":held_packet_samples,"swing":changed_swing_samples})
	_reconfigure_contract(shown,shown_motor)
	world.queue_free()
	await process_frame
	print("LOWER_PRESENTATION_PROFILE ",JSON.stringify({"capture":_stats(capture_us),"restore":_stats(restore_us),"render":_stats(render_us),"swing_bone_writes":swing_writes,"held_bone_slots":held_slots,"changed_swing_samples":changed_swing_samples,"render_contacts":render_contact_samples,"render_contact_error_m":render_contact_error,"upper_global_error_m":maximum_upper_error,"tick_max_rad":maximum_tick_angle,"render_max_rad":maximum_render_angle,"worst":worst}))
	print("LOWER_PRESENTATION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func _reconfigure_contract(shown:InkAvatar,motor:InkActor)->void:
	for weapon:String in Avatar.WEAPONS:
		shown.configure(Color("ff8a14"),weapon,{"hair":3,"hat":2,"brows":1,"outfit":6,"eyes":4,"skin":3})
		for frame:int in 36:shown.animate(1.0/60.0,{"grounded":true,"form":"kid","presentation_tick":true,"is_local":true,"firing":true,"charge":.4})
		_check("lower weapon rebuild "+weapon,shown.presentation_active and shown._presentation._rigs.size()==1 and shown.present(.5))
		var muzzle:=shown.get_muzzle()
		shown.present(.25)
		_check("equipped aiming unaffected "+weapon,shown.get_muzzle()==muzzle)
		for state:Dictionary in [{"grounded":false,"form":"kid"},{"grounded":true,"form":"squid"},{"grounded":true,"form":"swim"},{"grounded":true,"form":"climb"},{"grounded":true,"form":"kid","superJump":true}]:
			state["presentation_tick"]=true
			shown.animate(1.0/60.0,state)
			_check("non-locomotion exits immediately",not shown.presentation_active and not shown._presentation.rendered and not shown.present(.5),state)
		for frame:int in 36:shown.animate(1.0/60.0,{"grounded":true,"form":"kid","presentation_tick":true,"is_local":true})
		_check("kid locomotion re-enters",shown.presentation_active)
		shown.present(.1)
		motor.position+=Vector3(27,4,-31)
		shown.reset_presentation()
		var spawn:=shown.global_transform
		var packet:Array[Dictionary]=[]
		for bone:int in shown._skeleton.get_bone_count():packet.append(_raw_bone(shown._skeleton,bone))
		for fraction:float in [0.0,.25,.5,.75,1.0]:
			shown.present(fraction)
			_check("teleport keeps current root",shown.global_transform==spawn)
			for bone:int in shown._skeleton.get_bone_count():_check("teleport discards previous pose",_raw_bone(shown._skeleton,bone)==packet[bone])
		shown.restore_presentation()
	shown.trigger("dodge",{"x":1.0,"z":0.0,"t":.3})
	shown.animate(1.0/60.0,{"grounded":true,"form":"kid","presentation_tick":true})
	_check("full body action exits immediately",not shown.presentation_active)
	shown.presentation_interpolation=false
	_check("default off remains exact",not shown.presentation_active and not shown._presentation.rendered)

func _raw_bone(rig:Skeleton3D,bone:int)->Dictionary:
	return {"position":rig.get_bone_pose_position(bone),"rotation":rig.get_bone_pose_rotation(bone),"scale":rig.get_bone_pose_scale(bone)}

func _clocks(avatar:InkAvatar)->Dictionary:
	return {"time":avatar._time,"inertia":avatar._inertializer._age,"query_count":avatar._motion.query_count,"query_timer":avatar._motion._query_timer,"sample_time":avatar._motion.sample_time,"matched":avatar._motion.matched_pose,"hit_time":avatar._hit.stagger_time,"hit_values":avatar._hit.values.duplicate(),"contacts":avatar._foot_plant._contact.duplicate(),"weights":avatar._foot_plant._weight.duplicate(),"anchors":avatar._foot_plant._anchor.duplicate(),"planes":avatar._foot_plant._planes.duplicate(),"catch_cooldown":avatar._catch_step._cooldown}

func _node_packets(avatar:InkAvatar)->Array[Transform3D]:
	var result:Array[Transform3D]=[]
	for node:Node3D in [avatar,avatar._kid,avatar._body,avatar._weapon_r,avatar._weapon_l,avatar._weapon,avatar._left_weapon,avatar._tank_fill,avatar._squid,avatar._bomb]+avatar._face_nodes:
		if is_instance_valid(node):result.append(node.transform)
	return result

func _material_packets(avatar:InkAvatar)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for entry:Dictionary in avatar._material_entries:result.append((entry.sent as Dictionary).duplicate(true))
	return result

func _module_packets(avatar:InkAvatar)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for rig:Skeleton3D in avatar._modules:
		for bone:int in rig.get_bone_count():result.append(_raw_bone(rig,bone))
	return result

func _stats(values:Array[int])->Dictionary:
	if values.is_empty():return {}
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*.95)],"max":values[-1]}
