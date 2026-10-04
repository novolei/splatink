extends SceneTree
## Late-load independent scalar and actual original-body pose contract.
## This does not certify production input, FootPlant, aim or displayed frames.
var checks := 0
var failures := 0
var max_position_error := 0.0
var max_velocity_error := 0.0
var results:Array = []
var coverage:Dictionary = {"scalar":false, "original_87_rig":false}

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("HIT_RECOIL watchdog");quit(1))
	_run.call_deferred()

func _check(label:String, passed:bool, detail:Variant=null) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("HIT_RECOIL " + label + " " + str(detail))

func _oracle(time:float, speed:float=1.32) -> Vector2:
	# Independent zero-displacement scalar analytical solution (x and dx/dt).
	var w := TAU * 3.5
	var b := 0.58 * w
	var wd := w * sqrt(1.0 - 0.58 * 0.58)
	var a := speed / wd * exp(-b * time)
	return Vector2(a * sin(wd * time), a * (wd * cos(wd * time) - b * sin(wd * time)))

func _run() -> void:
	var helper:Script = load("res://scripts/animation/ink_hit_recoil.gd")
	_check("helper_loaded", helper != null)
	if helper == null:
		_finish()
		return
	var w := TAU * 3.5
	var b := .58 * w
	var wd := w * sqrt(1.0 - .58 * .58)
	var peak_time := atan(wd / b) / wd
	var analytic_peak := _oracle(peak_time).x
	_check("36_damage_peak_25_to_35mm", analytic_peak >= .025 and analytic_peak <= .035, analytic_peak)
	for dt:float in [1.0/30.0, 1.0/60.0, 1.0/144.0, .1, 6.0/30.0, 6.0/60.0, 6.0/144.0]:
		var recoil = helper.new()
		_check("impulse_accepted", recoil.trigger({"x":0.0, "z":1.0, "amp":.6}))
		var time := 0.0
		for target:float in [peak_time, .1, .2, .3, .4, .6]:
			while time < target - 1e-12:
				var h := minf(dt, target - time)
				recoil.step(h)
				time += h
			var expected := _oracle(target)
			var position_error:float = (recoil.offset as Vector2).distance_to(Vector2(0.0, -expected.x))
			var velocity_error:float = (recoil.velocity as Vector2).distance_to(Vector2(0.0, -expected.y))
			max_position_error = maxf(max_position_error, position_error)
			max_velocity_error = maxf(max_velocity_error, velocity_error)
			# Vector2 storage is float32 in the production engine; finite ulp budget.
			_check("analytical_position", position_error <= 0.0000002, {"dt":dt,"time":target,"error_m":position_error})
			_check("analytical_velocity", velocity_error <= 0.000002, {"dt":dt,"time":target,"error_mps":velocity_error})
			_check("ordinary_hit_finite_bounded", recoil.offset.is_finite() and recoil.velocity.is_finite() and recoil.offset.length() <= .0450001 and recoil.velocity.length() <= 1.800001)
		results.append({"step_s":dt, "end_time_s":time, "offset_m":_v2(recoil.offset), "velocity_mps":_v2(recoil.velocity), "offset_clamps":recoil.offset_clamp_count,"velocity_clamps":recoil.velocity_clamp_count})
		_check("ordinary_hit_unclamped", recoil.offset_clamp_count == 0 and recoil.velocity_clamp_count == 0)
	var whole = helper.new()
	whole.trigger({"x":1.0,"z":0.0,"amp":.6})
	whole.step(.6)
	_check("large_dt_keeps_full_elapsed", absf(whole.offset.x + _oracle(.6).x) <= .0000002 and int(whole.last_diagnostics.get("substeps",0)) >= 6, whole.last_diagnostics)
	var dense = helper.new()
	dense.trigger({"x":0,"z":1,"amp":.6})
	var sampled_peak := 0.0
	for frame:int in 240:
		dense.step(1.0/1200.0)
		sampled_peak = maxf(sampled_peak, dense.offset.length())
	_check("dense_peak_matches_analytical", absf(sampled_peak - analytic_peak) < .000005, sampled_peak)
	var diagonal = helper.new()
	diagonal.trigger({"x":2.0,"z":-2.0,"amp":.6})
	_check("away_direction_normalized", (diagonal.velocity as Vector2).distance_to(Vector2(-1,1).normalized()*1.32) < .0000002)
	var before_offset:Vector2 = diagonal.offset
	var before_velocity:Vector2 = diagonal.velocity
	for invalid_dt:float in [0.0,-.1,NAN,INF]:
		diagonal.step(invalid_dt)
		_check("invalid_dt_preserves_finite_state", diagonal.offset == before_offset and diagonal.velocity == before_velocity)
	var invalid = helper.new()
	for arg:Dictionary in [{"x":0,"z":0,"amp":.6},{"x":1,"z":0,"amp":0},{"x":1,"z":0,"amp":-1},{"x":NAN,"z":0,"amp":.6},{"x":1,"z":0,"amp":INF},{"x":null,"z":1,"amp":.6}]:
		_check("invalid_zero_input_ignored", not invalid.trigger(arg) and not invalid.active and invalid.offset == Vector2.ZERO and invalid.velocity == Vector2.ZERO)
	var repeated = helper.new()
	for frame:int in 120:
		repeated.trigger({"x":0,"z":1,"amp":1.2})
		repeated.step(1.0/144.0)
		_check("repeated_hits_finite_bounded", repeated.offset.is_finite() and repeated.velocity.is_finite() and repeated.offset.length() <= .0450001 and repeated.velocity.length() <= 1.800001)
	_check("repeated_velocity_cap_observed", repeated.velocity_clamp_count > 0)
	_check("repeated_offset_cap_observed", repeated.offset_clamp_count > 0)
	repeated.step(0.0, false)
	_check("hidden_form_resets_exactly", not repeated.active and repeated.offset == Vector2.ZERO and repeated.velocity == Vector2.ZERO)
	repeated.trigger({"x":1,"z":0,"amp":.6})
	repeated.reset()
	_check("explicit_reset_exact", not repeated.active and repeated.offset == Vector2.ZERO and repeated.velocity == Vector2.ZERO)
	var settled = helper.new()
	settled.trigger({"x":1,"z":0,"amp":.6})
	settled.step(2.0)
	_check("settled_returns_idle", not settled.active and settled.offset == Vector2.ZERO and settled.velocity == Vector2.ZERO)
	coverage.scalar = true
	await _rig_contract(helper)
	results.append({"analytic_peak_m":analytic_peak,"analytic_peak_time_s":peak_time,"sampled_1200hz_peak_m":sampled_peak,"repeat_offset_clamps":repeated.offset_clamp_count,"repeat_velocity_clamps":repeated.velocity_clamp_count})
	_finish()

func _rig_contract(helper:Script) -> void:
	var packed:PackedScene = load("res://assets/characters/body.glb")
	_check("original_body_import_loaded", packed != null)
	if packed == null:return
	var body:Node = packed.instantiate()
	var world := Node3D.new()
	world.transform = Transform3D(Basis.from_euler(Vector3(.12,.4,-.2)), Vector3(3,2,-4))
	root.add_child(world)
	world.add_child(body)
	await process_frame
	var rig := _find_rig(body)
	_check("actual_original_rig_87", rig != null and rig.get_bone_count() == 87)
	if rig == null or rig.get_bone_count() != 87:
		world.free()
		return
	# Give every stored component nontrivial values, independent of the helper.
	for bone:int in rig.get_bone_count():
		rig.set_bone_pose_position(bone, rig.get_bone_pose_position(bone) + Vector3(.0001*(bone+1),.0002*(bone+1),-.0001*(bone+1)))
		rig.set_bone_pose_rotation(bone, (rig.get_bone_pose_rotation(bone)*Quaternion.from_euler(Vector3(.001*bone,.002*bone,-.001*bone))).normalized())
		rig.set_bone_pose_scale(bone, Vector3(1.01, .99, 1.02))
	var baseline:Array = _pose(rig)
	var world_before := world.transform
	var body_before:Transform3D = (body as Node3D).transform if body is Node3D else Transform3D.IDENTITY
	var rig_before := rig.transform
	var recoil = helper.new()
	var configured:bool = recoil.configure(rig) and recoil.hip_index == rig.find_bone("hips")
	_check("configured_original_hips", configured)
	if not configured:
		world.free()
		return
	var idle_writes:int = recoil.apply_count
	_check("idle_apply_returns_without_writes", not recoil.apply(rig) and recoil.apply_count == idle_writes and _pose(rig) == baseline)
	recoil.trigger({"x":1,"z":-1,"amp":.6})
	_check("impulse_only_no_zero_offset_write", not recoil.apply(rig) and _pose(rig) == baseline)
	recoil.step(.05)
	_check("active_apply_written", recoil.apply(rig) and recoil.apply_count == idle_writes+1)
	var hip:int = recoil.hip_index
	for bone:int in rig.get_bone_count():
		var position := rig.get_bone_pose_position(bone)
		var expected:Vector3 = baseline[bone][0]
		if bone == hip:
			expected.x += recoil.offset.x
			expected.z += recoil.offset.y
		_check("only_hips_xz_%d"%bone, position == expected)
		_check("rotation_exact_%d"%bone, rig.get_bone_pose_rotation(bone) == baseline[bone][1])
		_check("scale_exact_%d"%bone, rig.get_bone_pose_scale(bone) == baseline[bone][2])
	_check("hips_y_exact", rig.get_bone_pose_position(hip).y == (baseline[hip][0] as Vector3).y)
	_check("original_roots_exact", world.transform == world_before and rig.transform == rig_before and (not body is Node3D or (body as Node3D).transform == body_before))
	var applied:Array = _pose(rig)
	recoil.step(.1, false)
	_check("hidden_apply_no_writes", not recoil.apply(rig) and _pose(rig) == applied)
	var wrong_rig := Skeleton3D.new()
	wrong_rig.add_bone("hips")
	world.add_child(wrong_rig)
	recoil.trigger({"x":1,"z":0,"amp":.6})
	recoil.step(.05)
	_check("other_rig_not_written", not recoil.apply(wrong_rig) and wrong_rig.get_bone_pose_position(0) == Vector3.ZERO)
	coverage.original_87_rig = true
	results.append({"actual_bone_count":rig.get_bone_count(),"hip_index":hip,"applied_offset_m":_v2(recoil.offset),"scope":"stored bone locals + Node3D roots; no production input/presented-frame claim"})
	world.free()

func _pose(rig:Skeleton3D) -> Array:
	var rows:Array = []
	for bone:int in rig.get_bone_count():rows.append([rig.get_bone_pose_position(bone),rig.get_bone_pose_rotation(bone),rig.get_bone_pose_scale(bone)])
	return rows

func _find_rig(node:Node) -> Skeleton3D:
	if node is Skeleton3D:return node
	for child:Node in node.get_children():
		var found := _find_rig(child)
		if found != null:return found
	return null

func _v2(value:Vector2) -> Array:return [value.x,value.y]

func _finish() -> void:
	_check("required_coverage", coverage.scalar == true and coverage.original_87_rig == true, coverage)
	var output := "res://shots/pc-hit-recoil-contract-v1.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--hit-recoil-output="):output = arg.trim_prefix("--hit-recoil-output=")
	var report := {"diagnostic_version":1,"checks":checks,"failures":failures,"coverage":coverage,"max_position_error_m":max_position_error,"max_velocity_error_mps":max_velocity_error,"samples":results,"limitations":["Fixture certifies helper scalar and stored original87 local pose semantics only.","Root/main input, downstream FootPlant/aim, visible muzzle and actual displayed timing require separate real-chain capture.","Saturated repeated hits use radial projection; cross-rate equality is certified for the unclamped ordinary impulse only."]}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("HIT_RECOIL output failed: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("HIT_RECOIL ", checks, " checks / ", failures, " failures -> ", output)
	quit(1 if failures > 0 else 0)
