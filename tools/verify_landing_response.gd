extends SceneTree
## Source-derived body/scalar semantics and imported87 FK contract; not a
## complete web landing pose oracle or production displayed-frame acceptance.
var checks := 0
var failures := 0
var quality_failures := 0
var reachable_samples := 0
var reach_limited_samples := 0
var maximum_scalar_error := 0.0
var maximum_foot_error := 0.0
var maximum_reachable_foot_error := 0.0
var maximum_rotation_error := 0.0
var maximum_leg_length_error := 0.0
var maximum_pelvis_correction := 0.0
var maximum_correction_rate := 0.0
var maximum_filtered_rate := 0.0
var maximum_filter_oracle_error := 0.0
var maximum_source_filter_difference := 0.0
var corrected_frames := 0
var samples:Array = []
var filter_samples:Array = []
var coverage:Dictionary = {"scalar":false,"body_slew":false,"original87":false,"reachable_feet":false}

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func():push_error("LANDING watchdog");quit(1))
	_run.call_deferred()

func _check(label:String, passed:bool, detail:Variant=null) -> void:
	checks += 1
	if not passed:
		failures += 1
		if failures <= 12:push_error("LANDING " + label + " " + str(detail))

func _oracle(t:float, frequency:float, damping:float, impulse:float) -> Vector2:
	var w := TAU*frequency
	var decay := damping*w
	var wd := w*sqrt(1.0-damping*damping)
	var a := impulse/wd*exp(-decay*t)
	return Vector2(a*sin(wd*t),a*(wd*cos(wd*t)-decay*sin(wd*t)))

func _heavy(t:float, a:float) -> float:
	var hold_end := .07+.13*a
	var end := .3+.38*a
	var envelope := 0.0
	if t > 0.0 and t < end:
		if t < .035:
			var u := t/.035
			envelope = u*u*(3.0-2.0*u)
		elif t <= hold_end:envelope = 1.0
		else:
			var u := (t-hold_end)/(end-hold_end)
			envelope = 1.0-u*u*(3.0-2.0*u)
	var strength := clampf((a-.3)/(.75-.3),0,1)
	return envelope*strength*strength*(3.0-2.0*strength)

func _run() -> void:
	var helper:Script = load("res://scripts/animation/ink_landing_response.gd")
	_check("late_loaded_helper",helper != null)
	if helper == null:_finish();return
	for speed:float in [3.0,8.0,14.0]:
		var a := clampf((speed-2.5)/13.0,.12,1.0)
		for dt:float in [1.0/30.0,1.0/60.0,1.0/144.0,.1,6.0/30.0,6.0/60.0,6.0/144.0]:
			var response = helper.new()
			_check("trigger_accepted",response.trigger(speed) and absf(response.amplitude-a)<1e-12)
			var time := 0.0
			for target:float in [.02,.1,.3,.6,.8]:
				while time < target-1e-12:
					var h := minf(dt,target-time)
					var previous:Vector2 = response.filtered_pelvis
					response.step(h,true)
					_check_filter_step(response,previous,h,{"speed":speed,"step_s":dt,"age_s":time+h})
					time += h
				var expected:Array[Vector2] = [_oracle(target,3.4,.42,-3*a),_oracle(target,2.2,.4,2.2*a),_oracle(target,3.2,.4,3.5*a)]
				var actual:Array[Vector2] = [response.pelvis,response.lean_pitch,response.head_pitch]
				for channel:int in 3:
					var error := actual[channel].distance_to(expected[channel])
					maximum_scalar_error = maxf(maximum_scalar_error,error)
					_check("closed_form_scalar",error<.000003 and actual[channel].is_finite(),{"speed":speed,"dt":dt,"t":target,"channel":channel,"error":error})
				_check("source_heavy_window",absf(response.heavy_weight-_heavy(target,a))<.0000002)
			_check("point8_near_settled",response.heavy_weight==0.0 and absf(response.pelvis.x)<.001 and absf(response.lean_pitch.x)<.002 and absf(response.head_pitch.x)<.001)
			var tail_previous:Vector2 = response.filtered_pelvis
			response.step(3.0,true)
			_check_filter_step(response,tail_previous,3.0,{"speed":speed,"step_s":dt,"tail":true})
			_check("tail_sleep_exact",not response.active and response.pelvis==Vector2.ZERO and response.lean_pitch==Vector2.ZERO and response.head_pitch==Vector2.ZERO and response.filtered_pelvis==Vector2.ZERO and response.last_filter_diagnostics.is_empty())
	var repeat = helper.new()
	repeat.trigger(14.0)
	repeat.step(.1)
	var old_amp:float = repeat.amplitude
	var old_velocity:float = repeat.pelvis.y
	var old_filtered:Vector2 = repeat.filtered_pelvis
	repeat.trigger(3.0)
	_check("repeat_within_point25_keeps_max_amp",repeat.age==0.0 and repeat.amplitude==old_amp and absf(repeat.pelvis.y-(old_velocity-.36))<.000001)
	_check("repeat_does_not_teleport_filtered_body",repeat.filtered_pelvis==old_filtered)
	repeat.step(.3)
	repeat.trigger(3.0)
	_check("repeat_after_point25_uses_new_amp",repeat.age==0.0 and absf(repeat.amplitude-.12)<1e-12)
	repeat.step(.02,false)
	_check("disabled_clears_state",not repeat.active and repeat.amplitude==0.0 and repeat.pelvis==Vector2.ZERO and repeat.lean_pitch==Vector2.ZERO and repeat.head_pitch==Vector2.ZERO and repeat.filtered_pelvis==Vector2.ZERO and repeat.last_filter_diagnostics.is_empty())
	_check("invalid_speed_ignored",not repeat.trigger(NAN) and not repeat.trigger(INF) and not repeat.active)
	coverage.scalar = true
	coverage.body_slew = not filter_samples.is_empty()
	await _rig_contract(helper)
	_finish()

func _check_filter_step(response:Variant,previous:Vector2,dt:float,context:Dictionary) -> void:
	var actual:Vector2 = response.filtered_pelvis
	var rate:float = actual.distance_to(previous)/dt
	maximum_filtered_rate = maxf(maximum_filtered_rate,rate)
	_check("body_filtered_slew_finite_bounded",actual.is_finite() and actual.distance_to(previous)<=.6*dt+.0000002,{"context":context,"delta_m":actual.distance_to(previous),"dt_s":dt})
	if response.active != true:
		_check("natural_sleep_only_at_filtered_zero",actual==Vector2.ZERO and response.last_filter_diagnostics.is_empty())
		return
	var d:Dictionary = response.last_filter_diagnostics
	_check("body_filter_diagnostics_available",not d.is_empty() and int(d.get("diagnostic_version",0))==4)
	if d.is_empty():return
	var raw := Vector2(clampf(response.pelvis.x,-.2,.08)-absf(response.lean_pitch.x)*.06-.11*response.amplitude*response.heavy_weight,-.02*response.amplitude*response.heavy_weight)
	var settled:bool = response.age>.8 and response.heavy_weight==0.0 and maxf(response.pelvis.length(),maxf(response.lean_pitch.length(),response.head_pitch.length()))<.00001
	var goal := Vector2.ZERO if settled else raw*.5
	var distance := goal.distance_to(previous)
	var expected := goal if distance<=.6*dt else previous+(goal-previous)*(.6*dt/distance)
	var error := actual.distance_to(expected)
	maximum_filter_oracle_error = maxf(maximum_filter_oracle_error,error)
	maximum_source_filter_difference = maxf(maximum_source_filter_difference,actual.distance_to(raw))
	var recorded_raw:Vector2 = d.source_requested_pelvis_yz_m
	_check("body_filter_raw_source_formula",response.requested_pelvis.distance_to(raw)<.0000002 and recorded_raw.distance_to(raw)<.0000002)
	_check("body_filter_independent_vector_step",error<.0000002,{"context":context,"error_m":error})
	_check("body_filter_step_fields_current",d.previous_pelvis_yz_m==previous and d.filtered_pelvis_yz_m==actual and d.delta_pelvis_yz_m==actual-previous and d.goal_pelvis_yz_m==goal and d.source_settled==settled and d.dt_s==dt and d.body_displacement_gain==.5 and d.rate_cap_mps==.6 and d.filter_count==response.filter_count and d.reset_epoch==response.reset_epoch)
	filter_samples.append({"context":context,"filter_count":response.filter_count,"reset_epoch":response.reset_epoch,"dt_s":dt,"rate_cap_mps":d.rate_cap_mps,"previous_yz_m":[previous.x,previous.y],"source_requested_yz_m":[raw.x,raw.y],"goal_yz_m":[goal.x,goal.y],"filtered_yz_m":[actual.x,actual.y],"source_settled":settled,"filter_oracle_error_m":error,"filtered_rate_mps":rate})

func _rig_contract(helper:Script) -> void:
	var packed:PackedScene = load("res://assets/characters/body.glb")
	_check("body_import_available",packed != null)
	if packed == null:return
	var world := Node3D.new()
	world.transform = Transform3D(Basis.from_euler(Vector3(0,.42,0)),Vector3(3,1,-4))
	root.add_child(world)
	var body:Node = packed.instantiate()
	world.add_child(body)
	await process_frame
	var rig := _find_rig(body)
	_check("original87_skeleton",rig != null and rig.get_bone_count()==87)
	if rig == null or rig.get_bone_count()!=87:world.free();return
	var imported:Array = _pose(rig)
	var root_before := world.transform
	var body_before:Transform3D = (body as Node3D).transform if body is Node3D else Transform3D.IDENTITY
	var rig_before := rig.transform
	var response = helper.new()
	var configured:bool = response.configure(rig)
	_check("required_body_and_two_legs",configured)
	if not configured:world.free();return
	_check("idle_no_write_all87_exact",not response.apply(rig) and response.apply_count==0 and _pose(rig)==imported)
	var hip := rig.find_bone("hips")
	var rotating:Array[int] = []
	for name:String in ["hips","spine","chest","neck","head","thighL","shinL","footL","thighR","shinR","footR"]:rotating.append(rig.find_bone(name))
	for pose_name:String in ["imported","bent_knees"]:
		_restore(rig,imported)
		if pose_name=="bent_knees":
			for side:String in ["L","R"]:
				var knee := rig.find_bone("shin"+side)
				rig.set_bone_pose_rotation(knee,(rig.get_bone_pose_rotation(knee)*Quaternion(Vector3.RIGHT,.65)).normalized())
		var baseline:Array = _pose(rig)
		for speed:float in [3.0,8.0,14.0]:
			for dt:float in [1.0/30.0,1.0/60.0,1.0/144.0,6.0/30.0]:
				response.reset()
				response.trigger(speed)
				var time := 0.0
				var previous_correction := 0.0
				var foot_targets:Array[Transform3D] = []
				var length_targets:Array[Vector2] = []
				_restore(rig,baseline)
				for side:String in ["L","R"]:
					foot_targets.append(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("foot"+side)))
					length_targets.append(_leg_lengths(rig,side))
				while time < .8-1e-12:
					var h := minf(dt,.8-time)
					var previous_filtered:Vector2 = response.filtered_pelvis
					response.step(h,true)
					_check_filter_step(response,previous_filtered,h,{"pose":pose_name,"speed":speed,"step_s":dt,"age_s":time+h})
					time += h
					_restore(rig,baseline)
					_check("active_body_applied",response.apply(rig,.7,.8))
					var correction:float = response.pelvis_correction_y
					maximum_pelvis_correction = maxf(maximum_pelvis_correction,absf(correction))
					maximum_correction_rate = maxf(maximum_correction_rate,absf(correction-previous_correction)/h)
					if correction != 0.0:corrected_frames += 1
					_check("body_correction_feasible",response.correction_feasible==true)
					_check("body_correction_finite_bounded_5mm",is_finite(correction) and absf(correction)<=.0050001,correction)
					# Retain the .1m/s + 2um acquisition/release continuity gate
					# for these static original87 cases after adding the body filter.
					# This does not certify arbitrary moving MM poses.
					_check("body_correction_continuity",absf(correction-previous_correction)<=.1*h+.000002,{"previous":previous_correction,"current":correction,"dt":h})
					_check("filtered_applied_correction_explicit",absf(response.applied_pelvis.x-response.filtered_pelvis.x-response.correction_requested_y)<.0000002 and absf(response.applied_pelvis.y-response.filtered_pelvis.y)<.0000002)
					var body_diag:Dictionary = response.last_diagnostics
					var initial_hip:Vector3 = body_diag.initial_hip_position_m
					var filtered_hip:Vector3 = body_diag.filtered_hip_position_m
					var corrected_hip:Vector3 = body_diag.corrected_hip_position_m
					var expected_filtered_hip := initial_hip+Vector3(0,response.filtered_pelvis.x,response.filtered_pelvis.y)
					var expected_corrected_hip := filtered_hip+Vector3(0,response.correction_requested_y,0)
					_check("hip_filter_projection_actual_components",filtered_hip==expected_filtered_hip and corrected_hip==expected_corrected_hip and corrected_hip==rig.get_bone_pose_position(hip) and body_diag.filtered_pelvis_yz_m==response.filtered_pelvis and int(body_diag.diagnostic_version)==4)
					previous_correction = correction
					for bone:int in rig.get_bone_count():
						_check("finite_components",rig.get_bone_pose_position(bone).is_finite() and rig.get_bone_pose_rotation(bone).is_finite() and rig.get_bone_pose_scale(bone).is_finite())
						_check("source_links_unchanged",bone==hip or rig.get_bone_pose_position(bone)==baseline[bone][0])
						_check("scale_exact",rig.get_bone_pose_scale(bone)==baseline[bone][2])
						_check("unrelated_rotation_exact",bone in rotating or rig.get_bone_pose_rotation(bone)==baseline[bone][1])
					_check("original_roots_exact",world.transform==root_before and rig.transform==rig_before and (not body is Node3D or (body as Node3D).transform==body_before))
					for side:int in 2:
						var foot := rig.find_bone("foot"+("L" if side==0 else "R"))
						var actual := rig.global_transform*rig.get_bone_global_pose(foot)
						var error := actual.origin.distance_to(foot_targets[side].origin)
						var rotation_error := _angle(actual.basis.orthonormalized().get_rotation_quaternion(),foot_targets[side].basis.orthonormalized().get_rotation_quaternion())
						var length_error := (_leg_lengths(rig,"L" if side==0 else "R")-length_targets[side]).abs()
						maximum_leg_length_error = maxf(maximum_leg_length_error,maxf(length_error.x,length_error.y))
						_check("actual_world_leg_lengths_1um",maxf(length_error.x,length_error.y)<.000001,length_error)
						var leg:Dictionary = response.last_diagnostics.legs[side]
						var reachable:bool = float(leg.clamp_distance_m)==0.0
						maximum_foot_error = maxf(maximum_foot_error,error)
						maximum_rotation_error = maxf(maximum_rotation_error,rotation_error)
						_check("foot_rotation_preserved",rotation_error<.00001,rotation_error)
						if reachable:
							reachable_samples += 1
							maximum_reachable_foot_error = maxf(maximum_reachable_foot_error,error)
							_check("reachable_foot_target_10um",error<.00001,{"pose":pose_name,"speed":speed,"dt":dt,"time":time,"side":side,"error_m":error})
						else:
							reach_limited_samples += 1
							if error>=.00001:quality_failures += 1
						# Record every clamp; keep all errors available rather than
						# choosing only good frames or relabeling clamps as success.
						samples.append({"pose":pose_name,"speed":speed,"step_s":dt,"age_s":time,"side":side,"heavy_weight":response.heavy_weight,"requested_pelvis_yz_m":[response.requested_pelvis.x,response.requested_pelvis.y],"filtered_pelvis_yz_m":[response.filtered_pelvis.x,response.filtered_pelvis.y],"filter_count":response.filter_count,"reset_epoch":response.reset_epoch,"body_target_rate_cap_mps":response.body_target_rate_cap_mps,"pelvis_yz_m":[response.applied_pelvis.x,response.applied_pelvis.y],"pelvis_correction_y_m":correction,"correction_requested_y_m":response.correction_requested_y,"correction_feasible":response.correction_feasible,"baseline_distance_m":leg.baseline_distance_m,"baseline_clamp_distance_m":leg.baseline_clamp_distance_m,"pre_correction_distance_m":leg.pre_correction_distance_m,"reachable":reachable,"clamp_distance_m":leg.clamp_distance_m,"foot_error_m":error,"rotation_error_rad":rotation_error})
	response.reset()
	_restore(rig,imported)
	_check("reset_idle_no_write_all87_exact",not response.apply(rig) and _pose(rig)==imported and response.filtered_pelvis==Vector2.ZERO and response.last_filter_diagnostics.is_empty())
	coverage.original87 = true
	coverage.reachable_feet = reachable_samples>0
	world.free()

func _pose(rig:Skeleton3D) -> Array:
	var rows:Array = []
	for bone:int in rig.get_bone_count():rows.append([rig.get_bone_pose_position(bone),rig.get_bone_pose_rotation(bone),rig.get_bone_pose_scale(bone)])
	return rows

func _restore(rig:Skeleton3D, rows:Array) -> void:
	for bone:int in rig.get_bone_count():
		rig.set_bone_pose_position(bone,rows[bone][0])
		rig.set_bone_pose_rotation(bone,rows[bone][1])
		rig.set_bone_pose_scale(bone,rows[bone][2])

func _find_rig(node:Node) -> Skeleton3D:
	if node is Skeleton3D:return node
	for child:Node in node.get_children():
		var found := _find_rig(child)
		if found != null:return found
	return null

func _angle(a:Quaternion,b:Quaternion) -> float:
	var q := (a*b.inverse()).normalized()
	return 2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w))

func _leg_lengths(rig:Skeleton3D,side:String) -> Vector2:
	var thigh:Vector3 = rig.global_transform*rig.get_bone_global_pose(rig.find_bone("thigh"+side)).origin
	var knee:Vector3 = rig.global_transform*rig.get_bone_global_pose(rig.find_bone("shin"+side)).origin
	var foot:Vector3 = rig.global_transform*rig.get_bone_global_pose(rig.find_bone("foot"+side)).origin
	return Vector2(thigh.distance_to(knee),knee.distance_to(foot))

func _finish() -> void:
	_check("required_nonzero_coverage",coverage.scalar==true and coverage.body_slew==true and coverage.original87==true and coverage.reachable_feet==true,coverage)
	var structural_failures := failures
	_check("all_sampled_foot_targets_preserved_10um",quality_failures==0,{"reach_quality_failures":quality_failures,"reach_limited_samples":reach_limited_samples,"maximum_error_m":maximum_foot_error})
	var output := "res://shots/pc-landing-response-contract-v5.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--landing-output="):output=arg.trim_prefix("--landing-output=")
	var report := {"diagnostic_version":4,"body_displacement_gain":.5,"checks":checks,"failures":failures,"structural_failures":structural_failures,"quality_failures":quality_failures,"coverage":coverage,"reachable_samples":reachable_samples,"reach_limited_samples":reach_limited_samples,"corrected_frames":corrected_frames,"max_pelvis_correction_m":maximum_pelvis_correction,"max_correction_rate_mps":maximum_correction_rate,"pelvis_correction_cap_m":.005,"reach_interior_margin_m":.000002,"correction_continuity_limit_mps":.1,"body_target_rate_cap_mps":.6,"max_filtered_rate_mps":maximum_filtered_rate,"max_filter_oracle_error_m":maximum_filter_oracle_error,"max_source_filter_difference_m":maximum_source_filter_difference,"filter_samples":filter_samples,"max_scalar_error":maximum_scalar_error,"max_foot_error_m":maximum_foot_error,"max_reachable_foot_error_m":maximum_reachable_foot_error,"max_foot_rotation_error_rad":maximum_rotation_error,"max_world_leg_length_error_m":maximum_leg_length_error,"samples":samples,"limitations":["Source-derived partial body port; not source Euler numerical or complete landing matrix parity.","The source body goal is scaled by .5 on the compact rig, then limited to .6m/s in local Y/Z. Source springs/window/pitch remain unchanged.","The filtered displacement rate cap excludes the subsequent reach projection; final applied pelvis is separately recorded.","Discrete filtered trajectories can differ across frame rates; only the original spring scalar oracle has same-time equivalence.","Natural sleep first filters toward zero; explicit hidden/spawn reset clears the visual reaction immediately.","Pelvis local Y is projected into both original ankle reach ranges; raw/filtered/applied differences are explicitly recorded.","5mm correction cap and .1m/s continuity gate cover these static imported/bent source cases, not arbitrary moving MM poses.","Free hand/specific weapon IK/face/squash/hair/ears and full HEAD/HLP stabilization unported.","Reach-limited targets count as quality failures and fail the overall target-preservation gate.","No production Input/main/physics Root authority/FootPlant downstream/aim/displayed-frame quality claim.","Near-settled .8s is a scalar threshold; natural spring tail continues until sleep."]}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("LANDING report failed "+output);quit(1);return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("LANDING ",checks," checks / ",structural_failures," structural failures / ",quality_failures," reach quality failures -> ",output)
	quit(1 if failures>0 else 0)
