class_name InkInertializer
extends RefCounted
## Critically damped position/quaternion-log offsets preserve output pose + velocity.
## New target animation runs immediately; offsets decay without a cross-fade pose mixture.
var half_life := 0.095
var _last_position := PackedVector3Array()
var _previous_position := PackedVector3Array()
var _last_rotation: Array[Quaternion] = []
var _previous_rotation: Array[Quaternion] = []
var _last_scale := PackedVector3Array()
var _position_offset := PackedVector3Array()
var _velocity_offset := PackedVector3Array()
var _rotation_offset := PackedVector3Array()
var _angular_velocity_offset := PackedVector3Array()
var _scale_offset := PackedVector3Array()
var _age := 99.0
var _last_dt := 1.0/60.0
var _initialized := false
var _enabled := false
var _nodes: Array[Dictionary] = []
var max_position_delta := 0.0
var max_rotation_delta := 0.0
var _bone_mask:=PackedInt32Array()
var _bone_indices:=PackedInt32Array()

func configure(skeleton: Skeleton3D, animated_nodes: Array = [], bone_mask:PackedInt32Array=PackedInt32Array()) -> void:
	var count := skeleton.get_bone_count()
	_bone_mask=bone_mask.duplicate()
	_bone_indices=bone_mask.duplicate()
	if _bone_indices.is_empty():
		for i:int in count:_bone_indices.append(i)
	_last_position.resize(count)
	_previous_position.resize(count)
	_last_scale.resize(count)
	_position_offset.resize(count)
	_velocity_offset.resize(count)
	_rotation_offset.resize(count)
	_angular_velocity_offset.resize(count)
	_scale_offset.resize(count)
	_last_rotation.resize(count)
	_previous_rotation.resize(count)
	for i in count:
		_last_position[i] = skeleton.get_bone_pose_position(i)
		_previous_position[i] = _last_position[i]
		_last_rotation[i] = skeleton.get_bone_pose_rotation(i)
		_previous_rotation[i] = _last_rotation[i]
		_last_scale[i] = skeleton.get_bone_pose_scale(i)
	_initialized = true
	_nodes.clear()
	for node in animated_nodes:
		if node is Node3D:
			_nodes.append({"node":node,"position":node.position,"previous":node.position,"rotation":node.quaternion,"previous_rotation":node.quaternion,"scale":node.scale,"offset":Vector3.ZERO,"velocity":Vector3.ZERO,"rotation_offset":Vector3.ZERO,"angular_velocity":Vector3.ZERO,"scale_offset":Vector3.ZERO})

func apply(skeleton: Skeleton3D, dt: float, transition: bool, matcher: InkMotionMatcher, enabled: bool = true) -> void:
	if not _initialized: configure(skeleton)
	if enabled and (transition or not _enabled):
		_begin(skeleton,matcher)
	_enabled = enabled
	# A new nearest-neighbour clip is sought at its selected sample time now.
	# The offsets measured by _begin therefore belong to t=0 of that sample,
	# not t=dt. Advancing their clock first subtracted a full frame of target
	# velocity before the new clip had advanced, breaking transition continuity.
	var decay := 1.67834699/maxf(0.025,half_life)
	var e := exp(-decay*_age)
	for entry in _nodes:
		var node := entry.node as Node3D
		if enabled and _age<0.85:
			node.position += (entry.offset+(entry.velocity+decay*entry.offset)*_age)*e
			var offset: Vector3 = (entry.rotation_offset+(entry.angular_velocity+decay*entry.rotation_offset)*_age)*e
			node.quaternion = (_exp_rotation(offset)*node.quaternion).normalized()
			node.scale += entry.scale_offset*(1.0+decay*_age)*e
		entry.previous = entry.position
		entry.previous_rotation = entry.rotation
		entry.position = node.position
		entry.rotation = node.quaternion
		entry.scale = node.scale
	max_position_delta = 0.0
	max_rotation_delta = 0.0
	for i:int in _bone_indices:
		var position := skeleton.get_bone_pose_position(i)
		var rotation := skeleton.get_bone_pose_rotation(i)
		var scale := skeleton.get_bone_pose_scale(i)
		if enabled and _age < 0.85:
			position += (_position_offset[i]+(_velocity_offset[i]+decay*_position_offset[i])*_age)*e
			var offset := (_rotation_offset[i]+(_angular_velocity_offset[i]+decay*_rotation_offset[i])*_age)*e
			rotation = _exp_rotation(offset)*rotation
			scale += _scale_offset[i]*(1.0+decay*_age)*e
			skeleton.set_bone_pose_position(i,position)
			skeleton.set_bone_pose_rotation(i,rotation.normalized())
			skeleton.set_bone_pose_scale(i,scale)
		max_position_delta = maxf(max_position_delta,position.distance_to(_last_position[i]))
		max_rotation_delta = maxf(max_rotation_delta,_log_rotation(rotation*_last_rotation[i].inverse()).length())
		_previous_position[i] = _last_position[i]
		_previous_rotation[i] = _last_rotation[i]
		_last_position[i] = position
		_last_rotation[i] = rotation
		_last_scale[i] = scale
	_age += dt
	_last_dt = maxf(0.001,dt)

func _begin(skeleton: Skeleton3D, matcher: InkMotionMatcher) -> void:
	_age = 0.0
	for entry in _nodes:
		var node := entry.node as Node3D
		entry.offset = entry.position-node.position
		entry.velocity = ((entry.position-entry.previous)/_last_dt as Vector3).limit_length(6.0)
		entry.rotation_offset = _log_rotation(entry.rotation*node.quaternion.inverse())
		entry.angular_velocity = (_log_rotation(entry.rotation*entry.previous_rotation.inverse())/_last_dt).limit_length(16.0)
		entry.scale_offset = entry.scale-node.scale
	for i:int in _bone_indices:
		var velocity := (_last_position[i]-_previous_position[i])/_last_dt
		var angular_velocity := _log_rotation(_last_rotation[i]*_previous_rotation[i].inverse())/_last_dt
		var target: Dictionary = matcher.local_velocity_at(i)
		_position_offset[i] = _last_position[i]-skeleton.get_bone_pose_position(i)
		var target_position: Vector3 = target.position
		var target_rotation: Vector3 = target.rotation
		_velocity_offset[i] = (velocity-target_position).limit_length(8.0)
		_rotation_offset[i] = _log_rotation(_last_rotation[i]*skeleton.get_bone_pose_rotation(i).inverse())
		_angular_velocity_offset[i] = (angular_velocity-target_rotation).limit_length(20.0)
		_scale_offset[i] = _last_scale[i]-skeleton.get_bone_pose_scale(i)

static func _log_rotation(rotation: Quaternion) -> Vector3:
	var q := rotation.normalized()
	if q.w<0: q = Quaternion(-q.x,-q.y,-q.z,-q.w)
	return q.get_axis()*q.get_angle() if absf(q.w)<0.999999 else Vector3.ZERO

static func _exp_rotation(value: Vector3) -> Quaternion:
	var angle := value.length()
	return Quaternion(value/angle,angle) if angle>0.000001 else Quaternion.IDENTITY
