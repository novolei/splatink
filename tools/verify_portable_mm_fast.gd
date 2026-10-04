extends SceneTree
## Algorithm/real-Avatar parity contract, not a real-match performance verdict.
## Game scripts load only after this SceneTree entry has initialized autoloads.
## No shared static database arrays are written, even for the tie/pruning cases.

const INPUT_PATHS := [
	"res://scripts/animation/ink_motion_matcher.gd",
	"res://scripts/animation/native_motion_matcher.gd",
	"res://data/motion_matching.json",
	"res://assets/animation/locomotion.features.bin",
	"res://assets/animation/locomotion.poses.bin",
]
const FAMILIES := ["shooter", "roller", "charger", "blaster", "dualies", "slosher", "splatling"]
const MATCHER_FIELDS := [
	"weapon", "clip_index", "sample_time", "playback_rate", "matched_pose",
	"match_cost", "continuation_cost", "query_count", "transition_count", "transitioned",
	"_bucket", "_selected", "_bone_map", "_previous_positions", "_query", "_query_timer",
	"_since_transition", "_last_intent", "_valid", "_slot", "_first_step", "_best_pose", "_best_cost",
]
const AVATAR_FIELDS := [
	"_time", "_shot_time", "_shot_hand", "_aim_weight", "_air_weight", "_form",
	"_form_time", "_form_weight", "_kid_pop", "_flick_time", "_release_time", "_throw_time",
	"_sub_weight", "_rolling", "_ink", "current_action",
]
const TREE_FIELDS := [
	"parameters/MotionTime/seek_request", "parameters/MotionSelection/blend_amount",
	"parameters/Locomotion/blend_position", "parameters/Aim/blend_amount", "parameters/Air/blend_amount",
]

var output: String = "res://shots/portable-mm-fast-contract-v2.json"
var fixed_slot: int = 5
var bench_rounds: int = 7
var checks: int = 0
var failure_count: int = 0
var failures: Array[String] = []
var baseline_script: Script
var fast_script: Script
var world: Node3D
var avatars: Array[Node3D] = []
var data: Dictionary = {}
var fixture_features := PackedFloat32Array()
var input_before: Dictionary = {}
var cost_cases: int = 0
var search_cases: int = 0
var avatar_steps: int = 0
var cooldown_steps: int = 0
var queried_steps: int = 0
var shooting_steps: int = 0
var avatar_cases: Array[Dictionary] = []
var benchmarks: Array[Dictionary] = []
var benchmark_measured_us: int = 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--portable-mm-output="): output = arg.trim_prefix("--portable-mm-output=")
		elif arg.begins_with("--portable-mm-slot="): fixed_slot = int(arg.trim_prefix("--portable-mm-slot="))
		elif arg.begins_with("--portable-mm-bench-rounds="): bench_rounds = clampi(int(arg.trim_prefix("--portable-mm-bench-rounds=")), 1, 15)
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if passed: return
	failure_count += 1
	if failures.size() < 64: failures.append(label)
	if failure_count <= 8: push_error("PORTABLE_MM_FAST_CONTRACT " + label)

func _hash_inputs() -> Dictionary:
	var result: Dictionary = {}
	for path: String in INPUT_PATHS:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		result[path] = {"bytes": bytes.size(), "sha256": hash.finish().hex_encode()}
	return result

func _run() -> void:
	# Native/presentation opt-ins would change this contract's graph semantics.
	for arg: String in OS.get_cmdline_user_args():
		_check("portable fixture has no native/presentation opt-in: " + arg,
			not arg.begins_with("--native-locomotion-mm") and not arg.begins_with("--presentation-interpolation"))
	if failure_count > 0: _finish(); return
	input_before = _hash_inputs()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT_PATHS[2]))
	_check("metadata parses", parsed is Dictionary)
	if not parsed is Dictionary: _finish(); return
	data = parsed
	fixture_features = FileAccess.get_file_as_bytes(String(data.feature_path)).to_float32_array()
	_check("original 63D/1638 source rows", int(data.dimensions) == 63 and int(data.count) == 1638 and fixture_features.size() == 63 * 1638)
	baseline_script = load(INPUT_PATHS[0])
	fast_script = load("res://scripts/animation/ink_motion_matcher_fast.gd")
	var avatar_script: Script = load("res://scripts/characters/ink_avatar.gd")
	_check("late-loaded scripts", baseline_script != null and fast_script != null and avatar_script != null)
	if failure_count > 0: _finish(); return
	world = Node3D.new()
	root.add_child(world)
	for i: int in 2:
		var avatar: Node3D = avatar_script.new()
		avatar.set("native_locomotion_mm", false)
		avatar.set("motion_matching", true)
		avatar.set("presentation_interpolation", false)
		avatar.set("force_lod", 1)
		world.add_child(avatar)
		avatar.set_process(false)
		avatars.append(avatar)
		var rig: Skeleton3D = avatar.get("_skeleton")
		_check("real original rig %d" % i, rig != null and rig.get_bone_count() == 87)
		_check("actual portable graph %d" % i, not bool(avatar.get("_native_motion_active")) and String(avatar.get("presentation_mode")) == "off")
	if failure_count > 0: _finish(); return
	var source: Skeleton3D = avatars[0].get("_skeleton")
	for family: String in FAMILIES:
		_verify_cost_search(family, source)
		if failure_count > 0: _finish(); return
	for hysteresis: bool in [false, true]:
		for local: bool in [true, false]:
			for family: String in FAMILIES:
				_verify_avatar(family, local, hysteresis)
				if failure_count > 0: _finish(); return
	_check("query cooldown really exercised", cooldown_steps > 0 and queried_steps > 0)
	_check("shooting graph really exercised", shooting_steps > 0)
	for family: String in FAMILIES:
		_microbenchmark(family, source)
	# Even after the soft timing budget, each remaining family gets one pair.
	# Missing/runtime-aborted benchmark functions must never produce a pass.
	_verify_benchmark_coverage()
	_finish()

func _provider(script: Script, rig: Skeleton3D, family: String, hysteresis: bool = false) -> RefCounted:
	var matcher: RefCounted = script.new()
	matcher.set("discriminative_hysteresis_enabled", hysteresis)
	_check("configure %s/%s/slot%d" % [script.resource_path.get_file(), family, fixed_slot], bool(matcher.call("configure", rig, family, fixed_slot)))
	return matcher

func _row_query(pose: int) -> PackedFloat32Array:
	var query := PackedFloat32Array()
	query.resize(63)
	for d: int in 63: query[d] = fixture_features[pose * 63 + d]
	return query

func _set_query(matcher: RefCounted, query: PackedFloat32Array) -> void:
	# Instance query only. The immutable production feature/pose cache stays read-only.
	matcher.set("_query", query.duplicate())

func _verify_cost_search(family: String, rig: Skeleton3D) -> void:
	var baseline := _provider(baseline_script, rig, family)
	var fast := _provider(fast_script, rig, family)
	var bucket: Vector2i = baseline.get("_bucket")
	_check("family bucket " + family, bucket == fast.get("_bucket") and bucket.y - bucket.x == 234)
	var first := _row_query(bucket.x)
	var middle := _row_query(bucket.x + 145)
	var perturbed := middle.duplicate()
	perturbed[0] += 0.4
	perturbed[3] -= 0.6
	perturbed[48] += 1.1
	perturbed[62] = 0.75
	var queries: Array[PackedFloat32Array] = [first, middle, perturbed]
	for query_index: int in queries.size():
		_set_query(baseline, queries[query_index])
		_set_query(fast, queries[query_index])
		for pose: int in bucket.y - bucket.x:
			var row: int = bucket.x + pose
			var full: float = baseline.call("_cost", row, INF)
			var trajectory: float = baseline.call("_cost", row, -1.0)
			# Exact trajectory/full-cost boundaries distinguish > from >= pruning.
			var limits: Array[float] = [INF, -1.0, 0.0, 1.0e-12, trajectory, full * 0.5, full, full + 1.0]
			for limit: float in limits:
				var original: float = baseline.call("_cost", row, limit)
				var candidate: float = fast.call("_cost", row, limit)
				cost_cases += 1
				_check("cost exact %s/q%d/pose%d/limit%s" % [family, query_index, row, str(limit)], original == candidate)
		for continuation: int in [bucket.x, bucket.x + 145, bucket.y - 1]:
			baseline.set("matched_pose", continuation)
			fast.set("matched_pose", continuation)
			baseline.call("_search_candidates")
			fast.call("_search_candidates")
			search_cases += 1
			_check("search exact %s/q%d/incumbent%d" % [family, query_index, continuation], _search_state(baseline) == _search_state(fast))
	# Finite huge queries intentionally erase row differences at float64 subtract
	# precision, creating a verified tie without writing any shared source row.
	var tie_query := PackedFloat32Array()
	tie_query.resize(63)
	tie_query.fill(1.0e20)
	_set_query(baseline, tie_query)
	_set_query(fast, tie_query)
	var tie_cost: float = baseline.call("_cost", bucket.x, INF)
	var actual_tie: bool = is_finite(tie_cost)
	for offset: int in bucket.y - bucket.x:
		actual_tie = actual_tie and float(baseline.call("_cost", bucket.x + offset, INF)) == tie_cost
	_check("verified finite all-row tie " + family, actual_tie)
	baseline.set("matched_pose", bucket.y - 1)
	fast.set("matched_pose", bucket.y - 1)
	baseline.call("_search_candidates")
	fast.call("_search_candidates")
	search_cases += 1
	_check("strict tie retains last continuation " + family, int(baseline.get("_best_pose")) == bucket.y - 1 and int(fast.get("_best_pose")) == bucket.y - 1 and _search_state(baseline) == _search_state(fast))

func _search_state(matcher: RefCounted) -> Array:
	return [matcher.get("matched_pose"), matcher.get("continuation_cost"), matcher.get("_best_pose"), matcher.get("_best_cost")]

func _first_property_difference(a: Object, b: Object, fields: Array) -> String:
	for field: String in fields:
		if a.get(field) != b.get(field): return field
	return ""

func _pose_difference(a: Skeleton3D, b: Skeleton3D) -> String:
	for bone: int in a.get_bone_count():
		if a.get_bone_pose_position(bone) != b.get_bone_pose_position(bone): return String(a.get_bone_name(bone)) + "/position"
		if a.get_bone_pose_rotation(bone) != b.get_bone_pose_rotation(bone): return String(a.get_bone_name(bone)) + "/rotation"
		if a.get_bone_pose_scale(bone) != b.get_bone_pose_scale(bone): return String(a.get_bone_name(bone)) + "/scale"
	return ""

func _verify_avatar(family: String, local: bool, hysteresis: bool) -> void:
	var rigs: Array[Skeleton3D] = []
	var providers: Array[RefCounted] = []
	var trees: Array[AnimationTree] = []
	for i: int in 2:
		var avatar: Node3D = avatars[i]
		avatar.transform = Transform3D.IDENTITY
		avatar.call("configure", Color("ff8a14"), family, {"hair": 3, "hat": 0, "brows": 2, "outfit": 6, "eyes": 2})
		avatar.set_process(false)
		var rig: Skeleton3D = avatar.get("_skeleton")
		rigs.append(rig)
		var matcher := _provider(baseline_script if i == 0 else fast_script, rig, family, hysteresis)
		providers.append(matcher)
		avatar.set("_motion", matcher)
		trees.append(avatar.get("_tree"))
		# Actual hair springs otherwise seed idle phase from each instance ID.
		var hair: Skeleton3D = avatar.get("_hair_rig")
		var springs: RefCounted = avatar.get("_hair_springs")
		if hair != null and springs != null: springs.call("configure", hair, 3, 0, fixed_slot)
	var label := "%s/local%s/hysteresis%s" % [family, str(local), str(hysteresis)]
	_check("same starting actual rig " + label, _pose_difference(rigs[0], rigs[1]).is_empty())
	var query_frames: int = 0
	var held_frames: int = 0
	var root_position := Vector3.ZERO
	for tick: int in 114:
		var velocity := Vector3.ZERO
		var firing: bool = tick >= 63 and tick < 81
		var grounded: bool = tick < 99 or tick >= 105
		if tick >= 9 and tick < 27: velocity = Vector3(0, 0, 5.5)
		elif tick >= 27 and tick < 39: velocity = Vector3(-4, 0, 0)
		elif tick >= 39 and tick < 51: velocity = Vector3(3.9, 0, 3.9)
		elif tick >= 51 and tick < 63: velocity = Vector3(0, 0, -3)
		elif firing: velocity = Vector3(0, 0, 5.5)
		var dt: float = 1.0 / 60.0
		root_position += velocity * dt
		var root_frame := Transform3D(Basis(Vector3.UP, 0.25 * sin(float(tick) * 0.035)), root_position)
		var state: Dictionary = {"velocity": velocity, "speed": velocity.length(), "desired_velocity": velocity, "desired_facing": root_frame.basis.z,
			"grounded": grounded, "form": "kid", "is_local": local, "firing": firing, "charge": 0.4 if firing and family in ["charger", "splatling"] else 0.0,
			"aim_pitch": 0.2 * sin(float(tick) * 0.07), "tank": 0.8, "presentation_tick": true}
		var before_queries: int = providers[0].get("query_count")
		for avatar: Node3D in avatars:
			avatar.transform = root_frame
			if firing and tick % 6 == 3: avatar.call("trigger", "shoot", {"hand": tick % 2})
			avatar.call("animate", dt, state)
		var step_label := "%s/tick%d" % [label, tick]
		avatar_steps += 1
		if firing: shooting_steps += 1
		var matcher_difference := _first_property_difference(providers[0], providers[1], MATCHER_FIELDS)
		_check("matcher exact " + step_label + "/" + matcher_difference, matcher_difference.is_empty() and providers[0].call("debug_state") == providers[1].call("debug_state"))
		var avatar_difference := _first_property_difference(avatars[0], avatars[1], AVATAR_FIELDS)
		_check("Avatar state exact " + step_label + "/" + avatar_difference, avatar_difference.is_empty())
		var bone_difference := _pose_difference(rigs[0], rigs[1])
		_check("all87 pose exact " + step_label + "/" + bone_difference, bone_difference.is_empty())
		_check("authority roots unchanged " + step_label, avatars[0].transform == root_frame and avatars[1].transform == root_frame)
		var tree_difference := _first_property_difference(trees[0], trees[1], TREE_FIELDS)
		_check("AnimationTree parameters exact " + step_label + "/" + tree_difference, tree_difference.is_empty())
		var after_queries: int = providers[0].get("query_count")
		if after_queries > before_queries:
			query_frames += 1
			queried_steps += 1
			var velocities_equal: bool = true
			for bone: int in rigs[0].get_bone_count():
				if providers[0].call("local_velocity_at", bone) != providers[1].call("local_velocity_at", bone): velocities_equal = false; break
			_check("source pose velocities exact " + step_label, velocities_equal)
		else:
			held_frames += 1
			cooldown_steps += 1
		if tick == 0:
			var expected: int = 1 if local or float(fixed_slot % 3) * 0.016 <= dt else 0
			_check("fixed-slot startup query " + step_label, after_queries == expected)
		if failure_count > 0: return
	_check("actual queries and held cooldown " + label, query_frames > 0 and held_frames > 0)
	_check("actual movement transitions " + label, int(providers[0].get("transition_count")) > 0)
	avatar_cases.append({"family": family, "local": local, "hysteresis": hysteresis, "slot": fixed_slot, "steps": 114,
		"queries": providers[0].get("query_count"), "transitions": providers[0].get("transition_count"), "query_frames": query_frames, "held_frames": held_frames})

func _time_cost(matcher: RefCounted, pose: int, calls: int) -> int:
	var begin: int = Time.get_ticks_usec()
	for i: int in calls: matcher.call("_cost", pose, INF)
	return Time.get_ticks_usec() - begin

func _time_search(matcher: RefCounted, calls: int) -> int:
	var begin: int = Time.get_ticks_usec()
	for i: int in calls: matcher.call("_search_candidates")
	return Time.get_ticks_usec() - begin

func _timing_summary(samples: Array[int], calls: int) -> Dictionary:
	if samples.is_empty(): return {}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "calls_per_sample": calls, "min_us_per_call": float(sorted[0]) / calls,
		"median_us_per_call": float(sorted[sorted.size() / 2]) / calls,
		"p95_us_per_call": float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)]) / calls,
		"max_us_per_call": float(sorted[-1]) / calls, "block_us": samples}

func _microbenchmark(family: String, rig: Skeleton3D) -> void:
	var providers: Array[RefCounted] = [_provider(baseline_script, rig, family), _provider(fast_script, rig, family)]
	var bucket: Vector2i = providers[0].get("_bucket")
	var query := _row_query(bucket.x + 145)
	query[48] += 1.1
	var pose: int = bucket.x + 150
	for matcher: RefCounted in providers:
		_set_query(matcher, query)
		matcher.set("matched_pose", bucket.y - 1)
		_time_cost(matcher, pose, 16)
		_time_search(matcher, 1)
	var cost_a: Array[int] = []
	var cost_b: Array[int] = []
	var search_a: Array[int] = []
	var search_b: Array[int] = []
	for round_index: int in bench_rounds:
		# Paired alternating order limits systematic first-run thermal/cache bias.
		var order: Array[int] = [0, 1]
		if round_index % 2 != 0: order.reverse()
		for index: int in order:
			var cost_us: int = _time_cost(providers[index], pose, 128)
			var search_us: int = _time_search(providers[index], 4)
			benchmark_measured_us += cost_us + search_us
			if index == 0: cost_a.append(cost_us); search_a.append(search_us)
			else: cost_b.append(cost_us); search_b.append(search_us)
		if benchmark_measured_us >= 2000000: break
	_check("benchmark leaves identical search result " + family, _search_state(providers[0]) == _search_state(providers[1]))
	benchmarks.append({"family": family, "cost_baseline": _timing_summary(cost_a, 128), "cost_fast": _timing_summary(cost_b, 128),
		"search_baseline": _timing_summary(search_a, 4), "search_fast": _timing_summary(search_b, 4)})

func _verify_benchmark_coverage() -> void:
	_check("benchmark measured nonzero wall time", benchmark_measured_us > 0)
	_check("all seven benchmark families completed", benchmarks.size() == FAMILIES.size())
	for family: String in FAMILIES:
		var matches: int = 0
		for row: Dictionary in benchmarks:
			if String(row.get("family", "")) != family: continue
			matches += 1
			var baseline_samples: int = int(row.get("cost_baseline", {}).get("samples", 0))
			for key: String in ["cost_baseline", "cost_fast", "search_baseline", "search_fast"]:
				var timing: Dictionary = row.get(key, {})
				var valid: bool = baseline_samples > 0 and int(timing.get("samples", 0)) == baseline_samples
				valid = valid and float(timing.get("min_us_per_call", 0.0)) > 0.0
				valid = valid and float(timing.get("median_us_per_call", 0.0)) > 0.0
				_check("positive paired benchmark samples %s/%s" % [family, key], valid)
		_check("benchmark family present exactly once " + family, matches == 1)

func _finish() -> void:
	var after: Dictionary = _hash_inputs()
	if not input_before.is_empty(): _check("five production inputs unchanged", input_before == after)
	var absolute: String = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	_check("contract report output writable", file != null)
	var report: Dictionary = {"contract": "portable-mm-fast-v2", "checks": checks, "failure_count": failure_count, "failures": failures,
		"slot": fixed_slot, "cost_cases": cost_cases, "search_cases": search_cases, "avatar_steps": avatar_steps,
		"queried_steps": queried_steps, "cooldown_steps": cooldown_steps, "shooting_steps": shooting_steps, "avatar_cases": avatar_cases,
		"input_before": input_before, "input_after": after, "benchmarks": benchmarks, "benchmark_measured_us": benchmark_measured_us,
		"timing_scope": "Paired portable _cost/_search_candidates calls only, including equal Object.call overhead; no game FPS or full-frame improvement claim.",
		"semantic_scope": "Real Avatar/manual AnimationTree with fixed-slot injected original/fast portable matchers; no main-scene real-input acceptance claim.",
		"engine": Engine.get_version_info(), "platform": OS.get_name()}
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		if file.get_error() != OK:
			_check("contract report write/flush succeeded", false)
		file.close()
	else: push_error("Unable to write portable matcher contract report: " + absolute)
	print("PORTABLE_MM_FAST_CONTRACT ", JSON.stringify({"checks": checks, "failure_count": failure_count, "cost_cases": cost_cases,
		"search_cases": search_cases, "avatar_steps": avatar_steps, "benchmark_measured_us": benchmark_measured_us, "output": output}))
	if is_instance_valid(world): world.free()
	quit(0 if failure_count == 0 and file != null else 1)
