class_name InkHitRecoil
extends RefCounted
## Additive local Hips X/Z recoil. Apply once to each freshly authored pose,
## after source HitResponse and before FootPlant; upper aim remains downstream.
const FREQUENCY_HZ := 3.5
const DAMPING_RATIO := 0.58
const IMPULSE_SPEED := 2.2
const VELOCITY_CAP := 1.8
const OFFSET_CAP := 0.045
const MAX_SUBSTEP := 0.1
const SLEEP_OFFSET := 0.000001
const SLEEP_VELOCITY := 0.00001

var offset := Vector2.ZERO
var velocity := Vector2.ZERO
var active := false
var hip_index := -1
var trigger_count := 0
var apply_count := 0
var offset_clamp_count := 0
var velocity_clamp_count := 0
var last_diagnostics:Dictionary = {}
var _rig_id := 0

func configure(rig:Skeleton3D) -> bool:
	reset()
	hip_index = rig.find_bone("hips") if is_instance_valid(rig) else -1
	_rig_id = rig.get_instance_id() if is_instance_valid(rig) else 0
	return hip_index >= 0

func trigger(arg:Dictionary) -> bool:
	var x:Variant = arg.get("x", 0.0)
	var z:Variant = arg.get("z", 0.0)
	var amp:Variant = arg.get("amp", 0.0)
	if not _is_number(x) or not _is_number(z) or not _is_number(amp):return false
	var incoming := Vector2(float(x), float(z))
	var strength := float(amp)
	var length := incoming.length()
	if not incoming.is_finite() or not is_finite(length) or length <= 0.000001 or not is_finite(strength) or strength <= 0.0:return false
	# Actor.damage supplies victim -> attacker in actor-local X/Z.
	var away := -incoming / length
	var next_velocity := velocity + away * (IMPULSE_SPEED * strength)
	if not next_velocity.is_finite():return false
	if next_velocity.length() > VELOCITY_CAP:
		next_velocity = next_velocity.limit_length(VELOCITY_CAP)
		velocity_clamp_count += 1
	velocity = next_velocity
	active = true
	trigger_count += 1
	last_diagnostics = {"event":"hit", "away":away, "amp":strength, "velocity":velocity}
	return true

func step(dt:float, kid_visible:bool=true) -> void:
	if not kid_visible:
		if active or offset != Vector2.ZERO or velocity != Vector2.ZERO:reset()
		return
	if not active or not is_finite(dt) or dt <= 0.0:return
	# Retain all elapsed game time, including time_scale=6; only each closed-form
	# segment is <= .1 s. This is not an Euler integration or elapsed-time clamp.
	var count := maxi(1, ceili(dt / MAX_SUBSTEP))
	var h := dt / float(count)
	var w := TAU * FREQUENCY_HZ
	var decay := DAMPING_RATIO * w
	var wd := w * sqrt(1.0 - DAMPING_RATIO * DAMPING_RATIO)
	var c := cos(wd * h)
	var s := sin(wd * h)
	var e := exp(-decay * h)
	for segment:int in count:
		var previous_offset := offset
		var previous_velocity := velocity
		offset = e * (previous_offset * c + (previous_velocity + decay * previous_offset) * (s / wd))
		velocity = e * (previous_velocity * c - (decay * previous_velocity + w * w * previous_offset) * (s / wd))
		if offset.length() > OFFSET_CAP:
			var radial := offset.normalized()
			offset = radial * OFFSET_CAP
			velocity -= radial * maxf(0.0, velocity.dot(radial))
			offset_clamp_count += 1
		if velocity.length() > VELOCITY_CAP:
			velocity = velocity.limit_length(VELOCITY_CAP)
			velocity_clamp_count += 1
	last_diagnostics = {"event":"step", "dt":dt, "substeps":count, "offset":offset, "velocity":velocity}
	if offset.length() <= SLEEP_OFFSET and velocity.length() <= SLEEP_VELOCITY:reset()

func apply(rig:Skeleton3D) -> bool:
	if not active or offset == Vector2.ZERO or hip_index < 0 or not is_instance_valid(rig):return false
	if rig.get_instance_id() != _rig_id or hip_index >= rig.get_bone_count():return false
	var position := rig.get_bone_pose_position(hip_index)
	position.x += offset.x
	position.z += offset.y
	rig.set_bone_pose_position(hip_index, position)
	apply_count += 1
	return true

func reset() -> void:
	offset = Vector2.ZERO
	velocity = Vector2.ZERO
	active = false
	last_diagnostics = {"event":"reset"}

static func _is_number(value:Variant) -> bool:
	return value is float or value is int
