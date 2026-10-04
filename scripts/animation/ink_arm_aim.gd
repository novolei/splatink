class_name InkArmAim
extends RefCounted
## Original kid-space hand grip frames and Character._solveLimb analytic arm IK.
## The sampled source choreography supplies zero-pitch weapon sway and recoil;
## this layer adds the camera pitch while retaining that instantaneous frame.
var _arms: Array[Dictionary] = []
var right_error := 0.0
var left_error := 0.0
var enabled := false
var target_right := Transform3D.IDENTITY
var target_left := Transform3D.IDENTITY

func configure(skeleton: Skeleton3D) -> void:
	_arms.clear()
	for side in ["R","L"]:
		var up := skeleton.find_bone("uArm"+side)
		var low := skeleton.find_bone("fArm"+side)
		var end := skeleton.find_bone("hand"+side)
		var a := skeleton.get_bone_rest(low).origin
		var b := skeleton.get_bone_rest(end).origin
		_arms.append({"up":up,"low":low,"end":end,"parent":skeleton.get_bone_parent(up),"a":a.length(),"b":b.length(),"up_frame":_frame(a.normalized()),"low_frame":_frame(b.normalized())})

func apply(skeleton: Skeleton3D, data: Dictionary, right_frame: Transform3D, left_frame: Transform3D, pitch: float, weight: float, dual: bool, pump: float = 0.0, project_support: bool = false) -> void:
	enabled = absf(pitch)>0.00001 and weight>0.001 and _arms.size()==2
	right_error = 0.0
	left_error = 0.0
	if not enabled: return
	var hold: Dictionary = data.hold
	var aim_p := clampf(pitch,-1.0,1.15)
	var aim_pose := clampf(aim_p,-0.8,1.0)
	var chest := skeleton.find_bone("chest")
	var previous_chest := skeleton.get_bone_global_pose(chest).origin
	# Source distributes pitch across three YXZ torso joints.
	_add_pitch(skeleton,"spine",-aim_pose*0.10*weight)
	_add_pitch(skeleton,"chest",-aim_pose*0.18*weight)
	_add_pitch(skeleton,"neck",-aim_p*0.08*weight)
	var translation := skeleton.get_bone_global_pose(chest).origin-previous_chest
	var zero := _anchor(hold.aim,0.0,false)
	var pitched := _anchor(hold.aim,aim_p,false)
	var rotation := Quaternion.IDENTITY.slerp(pitched.basis.get_rotation_quaternion()*zero.basis.get_rotation_quaternion().inverse(),weight)
	var destination := Transform3D(Basis(rotation)*right_frame.basis,right_frame.origin+(pitched.origin-zero.origin)*weight+translation)
	# The source bucket's front grip exceeds the short support arm's reach at
	# steep pitch. Preserve its angle and minimally move its anchor into the
	# intersection of both hand reach spheres; the authored rig stays unchanged.
	if project_support and not dual and float(hold.twoAim)>0.5:
		destination = _reachable_anchor(skeleton,destination,_grip(data.handR),_grip(data.handL))
	target_right = destination*_grip(data.handR)
	right_error = _solve(skeleton,_arms[0],target_right.origin,_vector(hold.poleR),target_right.basis.get_rotation_quaternion(),1.0)
	if dual:
		zero = _anchor(hold.aim,0.0,true)
		pitched = _anchor(hold.aim,aim_p,true)
		rotation = Quaternion.IDENTITY.slerp(pitched.basis.get_rotation_quaternion()*zero.basis.get_rotation_quaternion().inverse(),weight)
		destination = Transform3D(Basis(rotation)*left_frame.basis,left_frame.origin+(pitched.origin-zero.origin)*weight+translation)
		target_left = destination*_grip(data.handL)
		left_error = _solve(skeleton,_arms[1],target_left.origin,_vector(hold.poleL),target_left.basis.get_rotation_quaternion(),1.0)
	else:
		# Source recomputes the front grip from the weapon AFTER right-arm IK.
		# A clamped right target must not leave the support hand chasing the
		# unattainable pre-solve weapon anchor.
		destination = skeleton.get_bone_global_pose(int(_arms[0].end))*_grip(data.handR).affine_inverse()
		var grip := _grip(data.handL)
		grip.origin.z -= 0.036*pump
		target_left = destination*grip
		var support := lerpf(float(hold.twoCarry),float(hold.twoAim),weight)
		if support>0.001:
			left_error = _solve(skeleton,_arms[1],target_left.origin,_vector(hold.poleL),target_left.basis.get_rotation_quaternion(),support)
			# Original protraction rule keeps the support hand on the foregrip.
			var clavicle := skeleton.find_bone("clavL")
			var initial_y := skeleton.get_bone_pose_rotation(clavicle).get_euler(EULER_ORDER_YXZ).y
			for iteration in 3:
				if support<=0.5 or left_error<=0.0005: break
				var r := skeleton.get_bone_pose_rotation(clavicle).get_euler(EULER_ORDER_YXZ)
				if r.y<=initial_y-0.55: break
				var extra := clampf(left_error*12.0,0.0,0.3)
				r.y -= extra
				r.x -= extra*0.35
				skeleton.set_bone_pose_rotation(clavicle,Basis.from_euler(r,EULER_ORDER_YXZ).get_rotation_quaternion())
				left_error = _solve(skeleton,_arms[1],target_left.origin,_vector(hold.poleL),target_left.basis.get_rotation_quaternion(),support)

func _reachable_anchor(skeleton: Skeleton3D, anchor: Transform3D, right_grip: Transform3D, left_grip: Transform3D) -> Transform3D:
	var grips := [right_grip,left_grip]
	# Alternating projections converge to the closest feasible common anchor.
	# This runs for the single slosher preview / actor only while pitched aiming.
	for iteration in 24:
		var moved := false
		for i in 2:
			var arm: Dictionary = _arms[i]
			var shoulder := skeleton.get_bone_global_pose(int(arm.parent))*skeleton.get_bone_pose_position(int(arm.up))
			var target := anchor*(grips[i] as Transform3D).origin
			var delta := target-shoulder
			var reach := (float(arm.a)+float(arm.b))*0.998
			if delta.length()>reach:
				anchor.origin -= delta.normalized()*(delta.length()-reach)
				moved = true
		if not moved: break
	return anchor

static func _anchor(aim: Dictionary, pitch: float, mirror: bool) -> Transform3D:
	var p := _vector(aim.p).rotated(Vector3.RIGHT,-clampf(pitch,-0.8,1.0))+Vector3(-0.03,0.93,0.05)
	var r := _vector(aim.r)
	r.x -= pitch
	if mirror:
		p.x = -p.x
		r.y = -r.y
		r.z = -r.z
	return Transform3D(Basis.from_euler(r,EULER_ORDER_YXZ),p)

static func _grip(data: Dictionary) -> Transform3D:
	var q: Array = data.quat
	return Transform3D(Basis(Quaternion(float(q[0]),float(q[1]),float(q[2]),float(q[3]))),_vector(data.pos))

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

static func _add_pitch(skeleton: Skeleton3D, name: String, delta: float) -> void:
	var index := skeleton.find_bone(name)
	var r := skeleton.get_bone_pose_rotation(index).get_euler(EULER_ORDER_YXZ)
	r.x += delta
	skeleton.set_bone_pose_rotation(index,Basis.from_euler(r,EULER_ORDER_YXZ).get_rotation_quaternion())

static func _frame(direction: Vector3) -> Basis:
	var h := (Vector3.LEFT-direction*Vector3.LEFT.dot(direction)).normalized()
	return Basis(direction,h,direction.cross(h)).transposed()

static func _solve(skeleton: Skeleton3D, arm: Dictionary, target: Vector3, pole: Vector3, rotation: Quaternion, weight: float) -> float:
	var parent := skeleton.get_bone_global_pose(int(arm.parent))
	var parent_q := parent.basis.orthonormalized().get_rotation_quaternion()
	var origin := parent*skeleton.get_bone_pose_position(int(arm.up))
	var a := float(arm.a)
	var b := float(arm.b)
	var direction := target-origin
	var max_reach := (a+b)*0.9995
	var error := maxf(0.0,direction.length()-max_reach)
	var distance := clampf(direction.length(),absf(a-b)+0.001,max_reach)
	direction = direction.normalized()
	var cos_a := clampf((a*a+distance*distance-b*b)/(2.0*a*distance),-1.0,1.0)
	var n := pole-direction*pole.dot(direction)
	if n.length_squared()<0.00000001: n = Vector3.BACK-direction*direction.z
	n = n.normalized()
	var knee := origin+direction*a*cos_a+n*a*sqrt(1.0-cos_a*cos_a)
	var end := origin+direction*distance
	var h := n.cross(direction).normalized()
	var axis := (knee-origin).normalized()
	var up_q := (Basis(axis,h,axis.cross(h))*(arm.up_frame as Basis)).get_rotation_quaternion()
	var local := parent_q.inverse()*up_q
	local = skeleton.get_bone_pose_rotation(int(arm.up)).slerp(local.normalized(),weight)
	skeleton.set_bone_pose_rotation(int(arm.up),local)
	parent_q = parent_q*local
	axis = (end-knee).normalized()
	var low_q := (Basis(axis,h,axis.cross(h))*(arm.low_frame as Basis)).get_rotation_quaternion()
	local = parent_q.inverse()*low_q
	local = skeleton.get_bone_pose_rotation(int(arm.low)).slerp(local.normalized(),weight)
	skeleton.set_bone_pose_rotation(int(arm.low),local)
	parent_q = parent_q*local
	local = parent_q.inverse()*rotation
	skeleton.set_bone_pose_rotation(int(arm.end),skeleton.get_bone_pose_rotation(int(arm.end)).slerp(local.normalized(),weight))
	return error
