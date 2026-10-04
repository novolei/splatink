extends SceneTree
## Actual source scalar spring-bank reference plus native visual integration.
const Hit = preload("res://scripts/animation/ink_hit_response.gd")
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Catch = preload("res://scripts/animation/ink_catch_step.gd")
var checks:=0
var failures:=0
var maximum_error:=0.0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("HIT_CONTRACT watchdog");quit(1))
	call_deferred("_run")
func _check(label:String,passed:bool,detail:Variant=null) -> void:
	checks+=1
	if not passed:
		failures+=1
		push_error("HIT_CONTRACT "+label+" "+str(detail))
func _run() -> void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/hit_reference.json"))
	# Ear motion additionally depends on the source's full head acceleration;
	# check its authored impulses in the visual checks, not this scalar-only test.
	var verified_channels:PackedInt32Array=PackedInt32Array([0,1,2,3,4,5,6,7,8,9,10,13])
	for reference:Dictionary in fixture.cases:
		var response:=Hit.new()
		var kid:bool=reference.form=="kid"
		var dry_squid:bool=reference.form=="squid"
		for frame:int in reference.samples.size():
			var expected:Dictionary=reference.samples[frame]
			for event:Dictionary in reference.events:
				if int(event.frame)==frame:
					var source_x:float=expected.direction[0]
					response.random_source=func():return .5+source_x/1.2
					response.trigger(event.arg,kid)
			response.step(1.0/float(reference.fps),dry_squid,kid)
			var error:=0.0
			for channel:int in verified_channels:
				for component:int in 2:
					error=maxf(error,absf(response.values[channel*2+component]-float(expected.values[channel][component])))
			maximum_error=maxf(maximum_error,error)
			_check("%s_%s_frame_%d"%[reference.name,reference.fps,frame],error<.00002,{"max_error":error})
			_check("%s_%s_accumulation_%d"%[reference.name,reference.fps,frame],absf(response.accumulated-float(expected.accumulated))<.000001 and response.step_offset.distance_to(Vector2(float(expected.stepOffset[0]),float(expected.stepOffset[1])))<.000001)
			var source_head:Dictionary=expected.head
			var parameters:Array=source_head.parameters
			var expected_head:=Quaternion(float(source_head.rotation[0]),float(source_head.rotation[1]),float(source_head.rotation[2]),float(source_head.rotation[3]))
			var parent_head:=Quaternion(float(source_head.parent[0]),float(source_head.parent[1]),float(source_head.parent[2]),float(source_head.parent[3]))
			var head:=Hit.solve_head(_v(parameters[0]),_v(parameters[1]),_v(parameters[2]),parent_head)
			# Hidden kid bones retain the previous pose while its springs pause.
			if kid:_check("%s_%s_original_head_%d"%[reference.name,reference.fps,frame],_angle(head,expected_head)<.00001,_angle(head,expected_head))
			for source_foot:Dictionary in expected.feet:
				if not bool(source_foot.swing):continue
				var foot:Dictionary=source_foot.duplicate()
				foot.pw=_v(source_foot.contact)
				foot.from=_v(source_foot.from)
				foot.to=_v(source_foot.to)
				var posed:=Catch.pose_foot(foot,float(expected.run_weight))
				_check("%s_%s_original_settle_arc_%d"%[reference.name,reference.fps,frame],(posed.position as Vector3).distance_to(_v(source_foot.contact))<.00001 and absf(float(posed.yaw)-float(source_foot.yaw))<.00001 and absf(float(posed.pitch)-float(source_foot.pitch))<.00001)
	for source:Dictionary in fixture.settle:
		var foot:Dictionary={"pw":_v(source.from),"yaw":float(source.fromYaw)}
		Catch.start_settle(foot,_v(source.to),float(source.toYaw),float(source.error))
		_check("original_settle_duration_and_lift_%s"%source.error,absf(float(foot.duration)-float(source.duration))<.000001 and absf(float(foot.lift)-float(source.lift))<.000001 and is_equal_approx(float(foot.toe),float(source.toe)) and is_equal_approx(float(foot.land),float(source.land)))
	var world:=Node3D.new()
	root.add_child(world)
	var avatar:=Avatar.new()
	avatar.force_lod=0
	world.add_child(avatar)
	await process_frame
	avatar.configure(Color("ff8a14"),"shooter",{})
	_check("three_original_head_parameter_nodes",avatar._head_parameters.size()==3 and avatar._head_parameters[0]!=null and avatar._head_parameters[1]!=null and avatar._head_parameters[2]!=null)
	for frame:int in 90:avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":0.0})
	avatar.trigger("hit",{"x":1,"z":0,"amp":.6})
	_check("side_hit_has_no_front_pitch",is_zero_approx(avatar._hit.values[Hit.Channel.PITCH*2+1]))
	_check("side_hit_source_roll_impulse",absf(avatar._hit.values[Hit.Channel.ROLL*2+1]-3.9)<.000001)
	_check("side_hit_source_asymmetric_ears",absf(avatar._hit.values[Hit.Channel.EAR_LEFT*2+1]-4.2)<.000001 and absf(avatar._hit.values[Hit.Channel.EAR_RIGHT*2+1]-.6)<.000001)
	var rig:Skeleton3D=avatar._skeleton
	var head_track:=NodePath("Skeleton3D:head")
	var source_clip:Animation=avatar._animation.get_animation(avatar._action_clip.animation)
	for track:int in source_clip.get_track_count():
		var path:=source_clip.track_get_path(track)
		if path.get_subname_count()>0 and String(path.get_subname(0))=="spine":
			head_track=path
			break
	_check("hit_body_clip_not_double_added",not avatar._action_node.is_path_filtered(head_track))
	var roll_peak:=0.0
	for frame:int in 45:
		avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":0.0})
		roll_peak=maxf(roll_peak,absf(avatar._hit.sample(Hit.Channel.ROLL)))
		var finite:=true
		for bone:int in rig.get_bone_count():finite=finite and rig.get_bone_pose_rotation(bone).is_finite() and rig.get_bone_pose_position(bone).is_finite()
		_check("side_hit_actual_pose_finite_%d"%frame,finite)
	_check("side_hit_visible_spring_deflection",roll_peak>.05,roll_peak)
	avatar.trigger("shoot")
	_check("later_shoot_restores_upper_body_filter",avatar._action_node.is_path_filtered(head_track))
	for hit:int in 3:
		avatar.trigger("hit",{"x":1,"z":1,"amp":1.2})
		for frame:int in 4:avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":0.0})
	_check("repeated_hit_source_stagger_starts_settle",avatar._hit.stagger_revision>0 and avatar._catch_step.active)
	var touched_before:int=avatar._catch_step.touchdown_count
	for frame:int in 120:
		avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":0.0})
	_check("repeated_hit_actual_feet_complete_settle",avatar._catch_step.touchdown_count>touched_before and not avatar._catch_step.active,avatar._catch_step.touchdown_count)
	_check("repeated_hit_source_lift_visible",avatar._catch_step.maximum_lift>.025,avatar._catch_step.maximum_lift)
	print("HIT_CONTRACT "+JSON.stringify({"passed":failures==0,"checks":checks,"failures":failures,"maximum_source_spring_error":maximum_error}))
	quit(0 if failures==0 else 1)

func _v(value:Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _angle(a:Quaternion,b:Quaternion) -> float:
	# acos(dot) loses tiny angles when the quaternions are stored in float32.
	# The relative quaternion's vector retains that rotation information.
	var delta:=(b.inverse()*a).normalized()
	return 2.0*atan2(Vector3(delta.x,delta.y,delta.z).length(),absf(delta.w))
