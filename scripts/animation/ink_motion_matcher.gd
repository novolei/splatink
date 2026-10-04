class_name InkMotionMatcher
extends RefCounted
## Real normalized pose/velocity + predicted trajectory nearest-neighbour query.
## In-place clips use an explicit virtual movement trajectory; physics owns the root.

const PATH := "res://data/motion_matching.json"
static var database: Dictionary = {}
static var _features := PackedFloat32Array()
static var _poses := PackedFloat32Array()
static var _mean := PackedFloat32Array()
static var _std := PackedFloat32Array()
static var _weights := PackedFloat32Array()
var weapon := "shooter"
var clip_index := -1
var sample_time := 0.0
var playback_rate := 1.0
var matched_pose := -1
var match_cost := 0.0
var continuation_cost := 0.0
var query_count := 0
var transition_count := 0
var transitioned := false
var _bucket := Vector2i()
var _selected := PackedInt32Array()
var _bone_map := PackedInt32Array()
var _previous_positions := PackedVector3Array()
var _query := PackedFloat32Array()
var _query_timer := 0.0
var _since_transition := 99.0
var _last_intent := Vector3.ZERO
var _valid := false
var _slot := 0
var _first_step:=true
var _best_pose:=-1
var _best_cost:=0.0
## Default off: omit bucket-constant dimensions only from the ratio decision.
## The exact search and its reported total costs continue to use every feature.
var discriminative_hysteresis_enabled:bool=OS.get_cmdline_user_args().has("--mm-discriminative-hysteresis")
var _decision_dimensions:=PackedInt32Array()
var _constant_dimensions:=PackedInt32Array()
var _decision_bucket:=Vector2i(-1,-1)
var _decision_common_cost:=0.0
var _decision_best_cost:=0.0
var _decision_continuation_cost:=0.0
var _legacy_improved:=false
var _discriminative_improved:=false
var _decision_available:=false
var _zero_common_passthrough:=false
var _last_query_weapon:=""
var _decision_continuation_pose:=-1
var _decision_distance:=0.0
var _decision_intent_change:=false
var _decision_cooldown_ready:=false
var _decision_distance_ready:=false
var hysteresis_predicate_changes:=0
var hysteresis_transition_changes:=0
var hysteresis_added_transitions:=0
var hysteresis_suppressed_transitions:=0

func configure(skeleton: Skeleton3D, family: String, slot: int = 0) -> bool:
	if database.is_empty() and FileAccess.file_exists(PATH):
		database = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_features = FileAccess.get_file_as_bytes(database.feature_path).to_float32_array()
		_poses = FileAccess.get_file_as_bytes(database.pose_path).to_float32_array()
		_mean = PackedFloat32Array(database.mean)
		_std = PackedFloat32Array(database.std)
		_weights = PackedFloat32Array(database.weights)
	if database.is_empty(): return false
	_query.resize(int(database.dimensions))
	_selected.clear()
	for name in database.selected_bones:
		_selected.append(skeleton.find_bone(name))
	_bone_map.clear()
	for i in skeleton.get_bone_count():
		_bone_map.append(database.bones.find(skeleton.get_bone_name(i)))
	_valid = not _selected.has(-1)
	_previous_positions.resize(_selected.size())
	for i in _selected.size():
		_previous_positions[i] = skeleton.get_bone_global_pose(_selected[i]).origin
	_slot = slot
	set_weapon(family)
	_query_timer = float(slot%3)*0.016
	_first_step=true
	return _valid

func set_weapon(family: String) -> void:
	if database.is_empty(): return
	if family == weapon and clip_index >= 0: return
	weapon = family
	_bucket = Vector2i(int(database.count),0)
	for i in database.clips.size():
		var record: Dictionary = database.clips[i]
		if record.weapon != family: continue
		_bucket.x = mini(_bucket.x,int(record.start))
		_bucket.y = maxi(_bucket.y,int(record.start)+int(record.count))
		if record.action == "idle": clip_index = i
	sample_time = 0.0
	matched_pose = int(database.clips[clip_index].start)
	_since_transition = 99.0
	transitioned = true
	_decision_bucket=Vector2i(-1,-1)
	_decision_available=false
	_zero_common_passthrough=false
	_last_query_weapon=""
	if discriminative_hysteresis_enabled:_classify_decision_dimensions()

func step(dt: float, skeleton: Skeleton3D, local_velocity: Vector3, local_intent: Vector3, local_facing: Vector3, is_local: bool = true, enabled: bool = true) -> void:
	if not _valid or clip_index < 0: return
	if _first_step:
		_first_step=false
		# The local pose query is input-critical. Resource allocation may change
		# instance IDs; only remote avatars use the startup phase staggering.
		if is_local:_query_timer=0.0
	transitioned = false
	_since_transition += dt
	var record: Dictionary = database.clips[clip_index]
	var tagged_speed := Vector2(record.velocity[0],record.velocity[1]).length()
	var speed := Vector2(local_velocity.x,local_velocity.z).length()
	var target_rate := clampf(speed/tagged_speed,0.55,1.8) if tagged_speed>0.1 else 1.0
	playback_rate = lerpf(playback_rate,target_rate,1.0-exp(-dt*log(2.0)/0.15))
	sample_time = fposmod(sample_time+dt*playback_rate,float(record.duration))
	matched_pose = int(record.start)+mini(int(record.count)-1,int(sample_time*float(database.fps)))
	_update_query(dt,skeleton,local_velocity,local_intent,local_facing)
	_query_timer -= dt
	if not enabled: return
	var abrupt := local_intent.distance_squared_to(_last_intent)>3.0
	if _query_timer>0.0 and not abrupt: return
	_query_timer = 0.05 if is_local else 0.125
	_last_intent = local_intent
	query_count += 1
	_search_candidates()
	_last_query_weapon=weapon
	var best := _best_pose
	var best_cost := _best_cost
	var new_clip := _clip_for_pose(best)
	var new_record: Dictionary = database.clips[new_clip]
	var new_time := float(best-int(new_record.start))/float(database.fps)
	var distance := absf(new_time-sample_time)
	if new_clip == clip_index:
		distance = minf(distance,float(record.duration)-distance)
	var improved := best_cost < continuation_cost*0.72
	var intent_change := abrupt and new_clip != clip_index
	_legacy_improved=improved
	_discriminative_improved=improved
	_decision_available=false
	_zero_common_passthrough=false
	_decision_best_cost=best_cost
	_decision_continuation_cost=continuation_cost
	_decision_common_cost=0.0
	_decision_continuation_pose=matched_pose
	_decision_distance=distance
	_decision_intent_change=intent_change
	_decision_cooldown_ready=_since_transition>=0.14
	_decision_distance_ready=new_clip != clip_index or distance>0.16
	if discriminative_hysteresis_enabled and is_finite(best_cost) and is_finite(continuation_cost):
		if _decision_bucket!=_bucket:_classify_decision_dimensions()
		_decision_common_cost=_constant_cost()
		_decision_available=true
		_zero_common_passthrough=_decision_common_cost==0.0
		if not _zero_common_passthrough:
			# Re-sum the two rows directly. Subtracting a large shared term from
			# the provider totals would lose precision and couple this to its sum order.
			_decision_best_cost=_discriminative_cost(best)
			_decision_continuation_cost=_discriminative_cost(matched_pose)
			_discriminative_improved=_decision_best_cost<_decision_continuation_cost*0.72
		# With exactly no shared cost there is nothing to correct. Preserve the
		# provider ratio bit-for-bit, including native binary32 threshold edges.
		improved=_discriminative_improved
		if improved!=_legacy_improved:hysteresis_predicate_changes+=1
		var legacy_transition:=_decision_cooldown_ready and (_legacy_improved or intent_change) and _decision_distance_ready
		var proposed_transition:=_decision_cooldown_ready and (improved or intent_change) and _decision_distance_ready
		if legacy_transition!=proposed_transition:
			hysteresis_transition_changes+=1
			if proposed_transition:hysteresis_added_transitions+=1
			else:hysteresis_suppressed_transitions+=1
	if _since_transition>=0.14 and (improved or intent_change) and (new_clip != clip_index or distance>0.16):
		# Preserve cycles/second across locomotion families, not the numeric rate.
		# A walk clip is longer than a run clip; carrying an accelerated walk rate
		# into the shorter run cycle briefly doubled gait cadence after take-off.
		var new_speed := Vector2(new_record.velocity[0],new_record.velocity[1]).length()
		if new_clip!=clip_index and tagged_speed>0.1 and new_speed>0.1:
			playback_rate = clampf(playback_rate*float(new_record.duration)/float(record.duration),0.55,1.8)
		clip_index = new_clip
		sample_time = new_time
		matched_pose = best
		transitioned = true
		transition_count += 1
		_since_transition = 0.0
	match_cost = best_cost

func _search_candidates()->void:
	# Preserve the portable provider's arithmetic and ordering exactly. The
	# opt-in native provider overrides only this search/continuation boundary.
	continuation_cost=_cost(matched_pose,INF)
	_best_pose=matched_pose
	_best_cost=continuation_cost
	for pose in range(_bucket.x,_bucket.y):
		var cost:=_cost(pose,_best_cost)
		if cost<_best_cost:
			_best_cost=cost
			_best_pose=pose

func _update_query(dt: float, skeleton: Skeleton3D, velocity: Vector3, intent: Vector3, facing: Vector3) -> void:
	for i in _selected.size():
		var position := skeleton.get_bone_global_pose(_selected[i]).origin
		var v := (position-_previous_positions[i])/maxf(0.001,dt)
		_previous_positions[i] = position
		var offset := i*6
		_query[offset] = position.x
		_query[offset+1] = position.y
		_query[offset+2] = position.z
		_query[offset+3] = v.x
		_query[offset+4] = v.y
		_query[offset+5] = v.z
	for i in database.trajectory_times.size():
		var t := float(database.trajectory_times[i])
		var future := intent*t+(velocity-intent)*(1.0-exp(-4.62*t))/4.62
		_query[42+i*3] = future.x
		_query[43+i*3] = future.z
		_query[44+i*3] = atan2(facing.x,facing.z)*(1.0-exp(-t*8.0))
	for d in _query.size():
		_query[d] = (_query[d]-_mean[d])/_std[d]

func _cost(pose: int, limit: float) -> float:
	var start := pose*63
	var cost := 0.0
	# Trajectory is discriminative and contiguous: prune before reading all pose dimensions.
	for d in range(42,_query.size()):
		var delta := _features[start+d]-_query[d]
		cost += delta*delta*_weights[d]
	if cost>limit: return cost
	for d in 42:
		var delta := _features[start+d]-_query[d]
		cost += delta*delta*_weights[d]
		if cost>limit: return cost
	return cost

func _classify_decision_dimensions()->void:
	_decision_dimensions.clear()
	_constant_dimensions.clear()
	_decision_bucket=_bucket
	if _bucket.y<=_bucket.x:return
	var dimensions:=int(database.dimensions)
	# Use exact extrema of the active bucket, not normalization standard
	# deviations or a permanent list of facing indices. Authored varying facing
	# in a future database therefore remains part of the decision.
	for d:int in dimensions:
		var minimum:=float(_features[_bucket.x*dimensions+d])
		var maximum:=minimum
		for pose:int in range(_bucket.x+1,_bucket.y):
			var value:=float(_features[pose*dimensions+d])
			minimum=minf(minimum,value)
			maximum=maxf(maximum,value)
		if minimum==maximum:_constant_dimensions.append(d)
		else:_decision_dimensions.append(d)

func _discriminative_cost(pose:int)->float:
	var start:=pose*int(database.dimensions)
	var cost:=0.0
	# Match the portable provider's trajectory-first ordering without pruning.
	for d:int in _decision_dimensions:
		if d<42:continue
		var delta:=_features[start+d]-_query[d]
		cost+=delta*delta*_weights[d]
	for d:int in _decision_dimensions:
		if d>=42:continue
		var delta:=_features[start+d]-_query[d]
		cost+=delta*delta*_weights[d]
	return cost

func _constant_cost()->float:
	var start:=_bucket.x*int(database.dimensions)
	var cost:=0.0
	for d:int in _constant_dimensions:
		if d<42:continue
		var delta:=_features[start+d]-_query[d]
		cost+=delta*delta*_weights[d]
	for d:int in _constant_dimensions:
		if d>=42:continue
		var delta:=_features[start+d]-_query[d]
		cost+=delta*delta*_weights[d]
	return cost

func _clip_for_pose(pose: int) -> int:
	for i in database.clips.size():
		var record: Dictionary = database.clips[i]
		if pose>=int(record.start) and pose<int(record.start)+int(record.count): return i
	return clip_index

func clip_name() -> String:
	return String(database.clips[clip_index].name) if clip_index>=0 else weapon+"_idle"

func local_velocity_at(bone: int) -> Dictionary:
	var mapped := _bone_map[bone] if bone<_bone_map.size() else -1
	if mapped<0: return {"position":Vector3.ZERO,"rotation":Vector3.ZERO}
	var record: Dictionary = database.clips[clip_index]
	var frame := matched_pose-int(record.start)
	var next := int(record.start)+(frame+1)%int(record.count)
	var a := matched_pose*int(database.pose_stride)+mapped*10
	var b := next*int(database.pose_stride)+mapped*10
	var pos := Vector3(_poses[b]-_poses[a],_poses[b+1]-_poses[a+1],_poses[b+2]-_poses[a+2])*float(database.fps)*playback_rate
	var qa := Quaternion(_poses[a+3],_poses[a+4],_poses[a+5],_poses[a+6])
	var qb := Quaternion(_poses[b+3],_poses[b+4],_poses[b+5],_poses[b+6])
	var delta := qb*qa.inverse()
	if delta.w<0: delta = Quaternion(-delta.x,-delta.y,-delta.z,-delta.w)
	var rot := delta.get_axis()*delta.get_angle()*float(database.fps)*playback_rate if absf(delta.w)<0.999999 else Vector3.ZERO
	return {"position":pos,"rotation":rot}

func debug_state() -> Dictionary:
	return {"clip":clip_name(),"pose":matched_pose,"time":sample_time,"cost":match_cost,"continuation_cost":continuation_cost,"queries":query_count,"transitions":transition_count,"rate":playback_rate,"database_poses":database.get("count",0),"feature_dimensions":database.get("dimensions",0),"discriminative_hysteresis":{"enabled":discriminative_hysteresis_enabled,"decision_available":_decision_available,"zero_common_passthrough":_zero_common_passthrough,"last_query_weapon":_last_query_weapon,"constant_dimensions":_constant_dimensions,"nonconstant_dimensions":_decision_dimensions,"best_pose":_best_pose,"continuation_pose":_decision_continuation_pose,"common_cost":_decision_common_cost,"best_total_cost":match_cost,"continuation_total_cost":continuation_cost,"best_decision_cost":_decision_best_cost,"continuation_decision_cost":_decision_continuation_cost,"legacy_improved":_legacy_improved,"new_improved":_discriminative_improved,"distance_seconds":_decision_distance,"cooldown_ready":_decision_cooldown_ready,"distance_ready":_decision_distance_ready,"intent_change":_decision_intent_change,"predicate_changes":hysteresis_predicate_changes,"transition_changes":hysteresis_transition_changes,"added_transitions":hysteresis_added_transitions,"suppressed_transitions":hysteresis_suppressed_transitions}}
