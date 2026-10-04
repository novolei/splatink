class_name InkHairSprings
extends RefCounted
## Direct native port of Character._updateHair: gummy strand inertia, head exclusion,
## ribbon twist removal and a separate soft club-tip spring. No gameplay root motion.
static var _database: Dictionary = {}
var _strands: Array[Dictionary] = []
var _head := -1
var _last_position := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _last_rotation := Quaternion.IDENTITY
var _acceleration := Vector3.ZERO
var _velocity := Vector3.ZERO
var _initialized := false
var max_bend := 0.0
var max_into_head := 0.0
var max_twist := 0.0

func configure(skeleton: Skeleton3D, hair: int, hat: int, seed_value: int = 0) -> void:
	if _database.is_empty():
		_database = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/secondary_motion.json"))
	_head = skeleton.find_bone("head")
	_strands.clear()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for source in _database.styles.get("%d_%d"%[hair,hat],[]):
		var index := _strands.size()
		var bones := PackedInt32Array()
		var axes := PackedVector3Array()
		var coil := PackedVector3Array()
		var side := PackedVector3Array()
		for k in 4:
			bones.append(skeleton.find_bone("hair%d_%d"%[index,k] if k<3 else "hairTip%d"%index))
			axes.append(_v(source.axes[k]))
			coil.append(_v(source.coil[k]))
			side.append(_v(source.side[k]))
		_strands.append({"bones":bones,"axis":axes,"coil":coil,"side":side,"dir":_v(source.dir),"into":_v(source.into),"length":float(source.len),"stiffness":float(source.K),"gravity":float(source.G),"phase":random.randf_range(0.0,TAU),"x":PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]),"v":PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])})
	_initialized = false

func kick(impulse:Vector3) -> void:
	var velocity:=Vector3(impulse.z*.6+impulse.x*.3,impulse.x*.4,impulse.y*.5-impulse.x*.2)
	for strand:Dictionary in _strands:
		var v:PackedVector3Array=strand.v
		for joint:int in 3:
			v[joint]+=velocity
		strand.v=v

func apply(skeleton: Skeleton3D, dt: float, time: float, gait_weight: float, air_weight: float, enabled: bool = true) -> void:
	if _head<0 or _strands.is_empty(): return
	if not enabled or dt<=0.0:
		_initialized = false
		return
	var head := skeleton.global_transform*skeleton.get_bone_global_pose(_head)
	var position := head*Vector3(0.0,0.164,0.014)
	var rotation := head.basis.orthonormalized().get_rotation_quaternion()
	if not _initialized or position.distance_squared_to(_last_position)>9.0:
		_last_position = position
		_last_velocity = Vector3.ZERO
		_last_rotation = rotation
		_velocity = Vector3.ZERO
		_acceleration = Vector3.ZERO
		for strand in _strands:
			strand.x = PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
			strand.v = PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
		_initialized = true
		return
	var velocity := ((position-_last_position)/dt).limit_length(30.0)
	var acceleration := ((velocity-_last_velocity)/dt).limit_length(34.0)
	_acceleration = _acceleration.lerp(acceleration,1.0-exp(-dt*24.0))
	_velocity = _velocity.lerp(velocity,1.0-exp(-dt*12.0))
	_last_position = position
	_last_velocity = velocity
	var gravity := rotation.inverse()*(Vector3(0.0,-9.8,0.0)-_acceleration-_velocity*0.55)+Vector3(0.0,9.8,0.0)
	var turn := InkInertializer._log_rotation(_last_rotation.inverse()*rotation)
	_last_rotation = rotation
	var idle := (1.0-gait_weight)*(1.0-air_weight)
	var wave := TAU*0.42*time
	var steps := clampi(int(ceil(dt*60.0-0.25)),1,4)
	var h := dt/float(steps)
	max_bend = 0.0
	max_into_head = 0.0
	max_twist = 0.0
	for si in _strands.size():
		var strand: Dictionary = _strands[si]
		var direction: Vector3 = strand.dir
		var gravity_bend := direction.cross(gravity)*float(strand.gravity)*0.075*0.85*clampf(float(strand.length)/0.22,0.4,1.6)
		gravity_bend.y *= 0.3
		gravity_bend = gravity_bend.limit_length(0.62)
		var exclusion := direction.cross(strand.into as Vector3)
		var exclusion_length := exclusion.length_squared()
		var breeze := 0.6*(0.03*sin(time*1.7+float(si)*1.3)+0.012*sin(time*4.3+float(si)*2.1))
		var x: PackedVector3Array = strand.x
		var v: PackedVector3Array = strand.v
		for k in 3:
			var gain := 0.5 if k==0 else 0.3 if k==1 else 0.2
			var inertia := (0.55 if k==0 else 0.3 if k==1 else 0.15)*clampf(1.2-float(strand.stiffness)*0.3,0.3,1.0)*1.15
			x[k] -= turn*Vector3(inertia,inertia*0.5,inertia)
			var stiffness := 170.0*0.62*float(strand.stiffness)*(1.0 if k==0 else 0.75 if k==1 else 0.55)/clampf(float(strand.length)/0.22,0.6,1.6)
			var damping := 2.0*0.3*sqrt(stiffness)
			var target := gravity_bend*gain+Vector3(breeze*0.3,0.0,breeze*0.5)
			if idle>0.01:
				var ripple := idle*0.03*sin(wave-0.6*float(k)+float(strand.phase))*clampf(1.6-float(strand.stiffness)*0.4,0.3,1.0)
				target += ((strand.side[k] as Vector3)*0.8+(strand.coil[k] as Vector3)*0.35)*ripple
			for step in steps:
				v[k] += (stiffness*(target-x[k])-damping*v[k])*h
				x[k] += v[k]*h
			if exclusion_length>0.000001:
				var into := x[k].dot(exclusion)/exclusion_length
				if into>0.05:
					x[k] -= exclusion*(into-0.05)
					var into_velocity := v[k].dot(exclusion)/exclusion_length
					if into_velocity>0.0: v[k] -= exclusion*into_velocity
				max_into_head = maxf(max_into_head,x[k].dot(exclusion)/exclusion_length)
			x[k] = x[k].clamp(Vector3.ONE*-0.68,Vector3.ONE*0.68)
			var axis: Vector3 = strand.axis[k]
			var twist := x[k].dot(axis)
			x[k] -= axis*(twist-clampf(twist,-0.12,0.12))
			v[k] -= axis*v[k].dot(axis)
			max_twist = maxf(max_twist,absf(x[k].dot(axis)))
			max_bend = maxf(max_bend,x[k].length())
			if int(strand.bones[k])>=0: skeleton.set_bone_pose_rotation(int(strand.bones[k]),InkInertializer._exp_rotation(x[k]))
		# Club tip follows the last spring with its own lower frequency and softer damping.
		x[3] -= turn*Vector3(0.12,0.06,0.12)
		var tip_stiffness := 95.0*0.7*float(strand.stiffness)/clampf(float(strand.length)/0.22,0.6,1.6)
		var tip_damping := 2.0*0.24*sqrt(tip_stiffness)
		var curl := idle*0.08*sin(wave*0.95+float(strand.phase)*1.7-1.8)
		var tip_target := x[2]*Vector3(0.45,0.3,0.45)+gravity_bend*Vector3(0.12,0.1,0.12)+Vector3(breeze*0.25,0.0,breeze*0.35)+(strand.coil[3] as Vector3)*curl
		for step in steps:
			v[3] += (tip_stiffness*(tip_target-x[3])-tip_damping*v[3])*h
			x[3] += v[3]*h
		x[3] = x[3].clamp(Vector3.ONE*-0.4,Vector3.ONE*0.4)
		var tip_axis: Vector3 = strand.axis[3]
		var tip_twist := x[3].dot(tip_axis)
		x[3] -= tip_axis*(tip_twist-clampf(tip_twist,-0.12,0.12))
		max_twist = maxf(max_twist,absf(x[3].dot(tip_axis)))
		if int(strand.bones[3])>=0: skeleton.set_bone_pose_rotation(int(strand.bones[3]),InkInertializer._exp_rotation(x[3]))
		strand.x = x
		strand.v = v

static func _v(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])
