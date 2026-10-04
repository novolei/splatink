class_name InkLandingResponse
extends RefCounted
## Source-derived landing springs/body absorb, applied to each fresh MM pose.
## This is a partial body port: free hand/weapon IK, face, squash, hair/ears and
## source HEAD/HLP stabilization are not reproduced by this helper.
## The extra crouch is scaled for this compact rig, then rate limited. Raw
## source goals, springs/window and torso/head pitch remain observable unchanged.
const FootPlant = preload("res://scripts/animation/ink_foot_plant.gd")
const SPRINGS := [Vector2(3.4,.42), Vector2(2.2,.4), Vector2(3.2,.4)]
const PELVIS_CORRECTION_CAP := .005
const REACH_INTERIOR_MARGIN := .000002 # explicit body-pose change, not solver threshold
const BODY_TARGET_RATE_CAP := .6 # metres per game second, local Y/Z vector
const BODY_DISPLACEMENT_GAIN := .5 # shorten the extra crouch on this compact rig
var active := false
var age := 99.0
var amplitude := 0.0
var pelvis := Vector2.ZERO
var lean_pitch := Vector2.ZERO
var head_pitch := Vector2.ZERO
var heavy_weight := 0.0
var requested_pelvis := Vector2.ZERO
var filtered_pelvis := Vector2.ZERO
var body_target_rate_cap_mps := BODY_TARGET_RATE_CAP
var filter_count := 0
var reset_epoch := 0
var last_filter_diagnostics:Dictionary = {}
var applied_pelvis := Vector2.ZERO # local Y/Z displacement, metres
var pelvis_correction_y := 0.0
var correction_requested_y := 0.0
var correction_feasible := true
var applied_hip_pitch := 0.0
var trigger_count := 0
var apply_count := 0
var last_foot_error := 0.0
var last_foot_rotation_error := 0.0
var last_reach_clamp_count := 0
var last_diagnostics:Dictionary = {}
var _bones:Dictionary = {}
var _legs:Array[Dictionary] = []
var _rig_id := 0

func configure(rig:Skeleton3D) -> bool:
	reset()
	_bones.clear()
	_legs.clear()
	_rig_id = rig.get_instance_id() if is_instance_valid(rig) else 0
	if not is_instance_valid(rig):return false
	for name:String in ["hips","spine","chest","neck","head"]:
		var index := rig.find_bone(name)
		if index < 0:return false
		_bones[name] = index
	var plant := FootPlant.new()
	plant.configure(rig)
	_legs.assign(plant._legs)
	return _legs.size() == 2

func trigger(speed:float=8.0) -> bool:
	if not is_finite(speed):return false
	var a := clampf((speed - 2.5) / 13.0, .12, 1.0)
	amplitude = maxf(amplitude, a) if age < .25 else a
	age = 0.0
	pelvis.y -= 3.0 * a
	lean_pitch.y += 2.2 * a
	head_pitch.y += 3.5 * a
	active = true
	heavy_weight = 0.0
	trigger_count += 1
	return true

func step(dt:float, enabled:bool=true) -> void:
	if not enabled:
		if active:reset()
		return
	if not active or not is_finite(dt) or dt <= 0.0:return
	# Full elapsed game time retained, including time_scale=6.
	var count := maxi(1, ceili(dt / .1))
	var h := dt / float(count)
	for segment:int in count:
		pelvis = _spring(pelvis, SPRINGS[0], h)
		lean_pitch = _spring(lean_pitch, SPRINGS[1], h)
		head_pitch = _spring(head_pitch, SPRINGS[2], h)
	age += dt
	heavy_weight = _window(age, 0.0, .035, .07 + .13 * amplitude, .3 + .38 * amplitude) * smoothstep(.3, .75, amplitude)
	requested_pelvis = _source_pelvis_goal()
	var source_settled := age > .8 and heavy_weight == 0.0 and maxf(pelvis.length(),maxf(lean_pitch.length(),head_pitch.length())) < .00001
	var goal := Vector2.ZERO if source_settled else requested_pelvis*BODY_DISPLACEMENT_GAIN
	var previous := filtered_pelvis
	filtered_pelvis = filtered_pelvis.move_toward(goal,BODY_TARGET_RATE_CAP*dt)
	filter_count += 1
	last_filter_diagnostics = {"diagnostic_version":4,"body_displacement_gain":BODY_DISPLACEMENT_GAIN,"filter_count":filter_count,"reset_epoch":reset_epoch,"dt_s":dt,"rate_cap_mps":BODY_TARGET_RATE_CAP,"previous_pelvis_yz_m":previous,"source_requested_pelvis_yz_m":requested_pelvis,"goal_pelvis_yz_m":goal,"filtered_pelvis_yz_m":filtered_pelvis,"delta_pelvis_yz_m":filtered_pelvis-previous,"source_settled":source_settled}
	# Natural sleep cannot discard a nonzero filtered displacement. Explicit
	# hidden/spawn resets still clear the visual reaction immediately.
	if source_settled and filtered_pelvis == Vector2.ZERO:reset()

func apply(rig:Skeleton3D, aim_weight:float=0.0, two_hand:float=0.0) -> bool:
	if not active or _legs.size() != 2 or not is_instance_valid(rig):return false
	if rig.get_instance_id() != _rig_id:return false
	var k := heavy_weight
	requested_pelvis = _source_pelvis_goal()
	applied_pelvis = filtered_pelvis
	applied_hip_pitch = .3*lean_pitch.x + .14*amplitude*k
	if applied_pelvis == Vector2.ZERO and applied_hip_pitch == 0.0 and head_pitch.x == 0.0 and k == 0.0:return false
	var targets:Array[Transform3D] = []
	var baseline_distances:Array[float] = []
	for leg:Dictionary in _legs:
		targets.append(rig.get_bone_global_pose(int(leg.foot)))
		baseline_distances.append(targets[-1].origin.distance_to(rig.get_bone_global_pose(int(leg.up)).origin))
	var hip_index:int = _bones.hips
	var hip_position := rig.get_bone_pose_position(hip_index)
	var initial_hip_position := hip_position
	hip_position.y += applied_pelvis.x
	hip_position.z += applied_pelvis.y
	rig.set_bone_pose_position(hip_index, hip_position)
	var filtered_hip_position := rig.get_bone_pose_position(hip_index)
	_pitch(rig,"hips",applied_hip_pitch)
	_pitch(rig,"spine",.42*lean_pitch.x + .26*amplitude*k)
	_pitch(rig,"chest",.28*lean_pitch.x + .10*amplitude*k)
	_pitch(rig,"neck",.08*amplitude*k)
	_pitch(rig,"head",.5*head_pitch.x + .12*amplitude*k)
	# Project the body's local-Y offset into the intersection of both original
	# ankle targets' reachable intervals. Neither foot target nor limb length is
	# changed. The minimum-reach exclusions also remain part of feasibility.
	var correction := _body_correction(rig,targets)
	correction_feasible = correction.feasible
	correction_requested_y = correction.value
	var before_correction := rig.get_bone_pose_position(hip_index)
	var corrected := before_correction
	corrected.y += correction_requested_y
	if correction_requested_y != 0.0:rig.set_bone_pose_position(hip_index,corrected)
	var actual_hip := rig.get_bone_pose_position(hip_index)
	pelvis_correction_y = actual_hip.y-before_correction.y
	applied_pelvis = Vector2(actual_hip.y-initial_hip_position.y,actual_hip.z-initial_hip_position.z)
	last_foot_error = 0.0
	last_foot_rotation_error = 0.0
	last_reach_clamp_count = 0
	var rows:Array = []
	for side:int in 2:
		var leg:Dictionary = _legs[side]
		var target := targets[side]
		var rotation := target.basis.orthonormalized().get_rotation_quaternion()
		var thigh := rig.get_bone_global_pose(int(leg.up)).origin
		var requested := thigh.distance_to(target.origin)
		var reach := (float(leg.a)+float(leg.b))*.9995
		var minimum := absf(float(leg.a)-float(leg.b))+.001
		var clamp_distance := absf(requested - clampf(requested,minimum,reach))
		if clamp_distance > 0.0:last_reach_clamp_count += 1
		# influence=0 retains authored knee plane and avoids stance soft-knee
		# shortening. The original .9995/minimum reach clamp remains observable.
		FootPlant._solve(rig,leg,target.origin,rotation*Vector3.BACK,rotation,Vector3.ZERO,0.0,0.0)
		var actual := rig.get_bone_global_pose(int(leg.foot))
		var error := actual.origin.distance_to(target.origin)
		var rotation_error := _angle(actual.basis.orthonormalized().get_rotation_quaternion(),rotation)
		last_foot_error = maxf(last_foot_error,error)
		last_foot_rotation_error = maxf(last_foot_rotation_error,rotation_error)
		rows.append({"side":side,"target":target.origin,"actual":actual.origin,"baseline_distance_m":baseline_distances[side],"baseline_clamp_distance_m":absf(baseline_distances[side]-clampf(baseline_distances[side],minimum,reach)),"pre_correction_distance_m":correction.distances[side],"requested_distance_m":requested,"reach_m":reach,"minimum_reach_m":minimum,"clamp_distance_m":clamp_distance,"foot_error_m":error,"rotation_error_rad":rotation_error})
	apply_count += 1
	last_diagnostics = {"diagnostic_version":4,"body_displacement_gain":BODY_DISPLACEMENT_GAIN,"age":age,"amplitude":amplitude,"heavy_weight":k,"source_pelvis_state":pelvis,"source_lean_pitch_state":lean_pitch,"requested_pelvis_yz_m":requested_pelvis,"filtered_pelvis_yz_m":filtered_pelvis,"body_target_rate_cap_mps":BODY_TARGET_RATE_CAP,"filter_count":filter_count,"reset_epoch":reset_epoch,"filter_step":last_filter_diagnostics,"initial_hip_position_m":initial_hip_position,"filtered_hip_position_m":filtered_hip_position,"corrected_hip_position_m":actual_hip,"applied_pelvis_yz_m":applied_pelvis,"pelvis_correction_y_m":pelvis_correction_y,"correction_requested_y_m":correction_requested_y,"correction_feasible":correction_feasible,"correction_cap_m":PELVIS_CORRECTION_CAP,"reach_interior_margin_m":REACH_INTERIOR_MARGIN,"applied_hip_pitch_rad":applied_hip_pitch,"legs":rows,"unported_big_freehand_weight":smoothstep(.7,.95,amplitude)*(1.0-clampf(aim_weight,0,1))*(1.0-clampf(two_hand,0,1))}
	return true

func reset() -> void:
	active = false
	age = 99.0
	amplitude = 0.0
	pelvis = Vector2.ZERO
	lean_pitch = Vector2.ZERO
	head_pitch = Vector2.ZERO
	heavy_weight = 0.0
	requested_pelvis = Vector2.ZERO
	filtered_pelvis = Vector2.ZERO
	last_filter_diagnostics = {}
	reset_epoch += 1
	applied_pelvis = Vector2.ZERO
	pelvis_correction_y = 0.0
	correction_requested_y = 0.0
	correction_feasible = true
	applied_hip_pitch = 0.0
	last_foot_error = 0.0
	last_foot_rotation_error = 0.0
	last_reach_clamp_count = 0
	last_diagnostics = {}

func _source_pelvis_goal() -> Vector2:
	return Vector2(clampf(pelvis.x,-.2,.08)-absf(lean_pitch.x)*.06-.11*amplitude*heavy_weight,-.02*amplitude*heavy_weight)

func _body_correction(rig:Skeleton3D,targets:Array[Transform3D]) -> Dictionary:
	var hip_parent := rig.get_bone_parent(int(_bones.hips))
	var axis := rig.get_bone_global_pose(hip_parent).basis*Vector3.UP if hip_parent >= 0 else Vector3.UP
	var axis_sq := axis.length_squared()
	var lower := -PELVIS_CORRECTION_CAP
	var upper := PELVIS_CORRECTION_CAP
	var vectors:Array[Vector3] = []
	var distances:Array[float] = []
	var limits:Array[Vector2] = []
	var exclusions:Array[Vector2] = []
	var feasible := axis_sq > .00000001
	for side:int in 2:
		var leg:Dictionary = _legs[side]
		var q := targets[side].origin-rig.get_bone_global_pose(int(leg.up)).origin
		vectors.append(q)
		distances.append(q.length())
		var reach := (float(leg.a)+float(leg.b))*.9995-REACH_INTERIOR_MARGIN
		var minimum := absf(float(leg.a)-float(leg.b))+.001+REACH_INTERIOR_MARGIN
		limits.append(Vector2(minimum,reach))
		if not feasible:continue
		var center := q.dot(axis)/axis_sq
		var perpendicular_sq := maxf(0.0,q.length_squared()-q.dot(axis)*q.dot(axis)/axis_sq)
		if perpendicular_sq > reach*reach:
			feasible = false
			continue
		var radius := sqrt(maxf(0.0,(reach*reach-perpendicular_sq)/axis_sq))
		lower = maxf(lower,center-radius)
		upper = minf(upper,center+radius)
		if perpendicular_sq < minimum*minimum:
			var min_radius := sqrt((minimum*minimum-perpendicular_sq)/axis_sq)
			exclusions.append(Vector2(center-min_radius,center+min_radius))
	if not feasible or lower > upper:return {"feasible":false,"value":0.0,"distances":distances}
	var candidates:Array[float] = [clampf(0.0,lower,upper),lower,upper]
	for excluded:Vector2 in exclusions:
		candidates.append(clampf(excluded.x,lower,upper))
		candidates.append(clampf(excluded.y,lower,upper))
	var chosen := INF
	for candidate:float in candidates:
		var valid := true
		for side:int in 2:
			var distance := (vectors[side]-axis*candidate).length()
			valid = valid and distance >= limits[side].x-.0000001 and distance <= limits[side].y+.0000001
		if valid and absf(candidate) < absf(chosen):chosen = candidate
	return {"feasible":is_finite(chosen),"value":chosen if is_finite(chosen) else 0.0,"distances":distances}

func _pitch(rig:Skeleton3D, name:String, value:float) -> void:
	if value == 0.0:return
	var index:int = _bones[name]
	var euler := Basis(rig.get_bone_pose_rotation(index)).get_euler(EULER_ORDER_XYZ)
	euler.x += value
	rig.set_bone_pose_rotation(index,Basis.from_euler(euler,EULER_ORDER_XYZ).get_rotation_quaternion())

static func _spring(state:Vector2, parameters:Vector2, dt:float) -> Vector2:
	var w := TAU*parameters.x
	var decay := parameters.y*w
	var wd := w*sqrt(1.0-parameters.y*parameters.y)
	var c := cos(wd*dt)
	var s := sin(wd*dt)
	var e := exp(-decay*dt)
	return Vector2(e*(state.x*c+(state.y+decay*state.x)*s/wd),e*(state.y*c-(decay*state.y+w*w*state.x)*s/wd))

static func _window(t:float, a:float, b:float, c:float, d:float) -> float:
	if t <= a or t >= d:return 0.0
	if t < b:return smoothstep(0.0,1.0,(t-a)/(b-a))
	if t > c:return 1.0-smoothstep(0.0,1.0,(t-c)/(d-c))
	return 1.0

static func _angle(a:Quaternion, b:Quaternion) -> float:
	var delta := (a*b.inverse()).normalized()
	return 2.0*atan2(Vector3(delta.x,delta.y,delta.z).length(),absf(delta.w))
