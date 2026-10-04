class_name InkFootPlant
extends RefCounted
## World contacts complement in-place pose matching. Analytic limb frame solver comes
## from original Character._solveLimb; game physics still controls the actor root.
var _legs: Array[Dictionary] = []
var _anchor := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var _orientation: Array[Quaternion] = [Quaternion.IDENTITY,Quaternion.IDENTITY]
var _contact := [false,false]
var _weight := [0.0,0.0]
var _was_enabled := false
var _last_root := Vector3.ZERO
var _hip_drop := 0.0
var _planes := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var contact_samples := 0
var max_contact_error := 0.0
var last_contact_error := 0.0
var last_debug: Array[Dictionary] = []
var collect_debug := false

func configure(skeleton: Skeleton3D) -> void:
	for side in ["L","R"]:
		var up := skeleton.find_bone("thigh"+side)
		var low := skeleton.find_bone("shin"+side)
		var foot := skeleton.find_bone("foot"+side)
		if up<0 or low<0 or foot<0: return
		var a := skeleton.get_bone_rest(low).origin
		var b := skeleton.get_bone_rest(foot).origin
		_legs.append({"up":up,"low":low,"foot":foot,"parent":skeleton.get_bone_parent(up),"a":a.length(),"b":b.length(),"up_frame":_rest_frame(a.normalized()),"low_frame":_rest_frame(b.normalized())})

func apply(skeleton: Skeleton3D, dt: float, matcher: InkMotionMatcher, root_position: Vector3, ground_sampler: Callable, enabled: bool = true, external_targets:Array[Dictionary]=[]) -> void:
	if _legs.size()!=2: return
	var teleported := _was_enabled and root_position.distance_squared_to(_last_root)>1.0
	if not enabled or teleported:
		_contact = [false,false]
		_weight = [0.0,0.0]
		_hip_drop = 0.0
		_planes.fill(Vector3.ZERO)
		_was_enabled = false
		_last_root = root_position
		return
	var targets: Array[Vector3] = []
	var rotations: Array[Quaternion] = []
	var inv := skeleton.global_transform.affine_inverse()
	last_debug.clear()
	for i in 2:
		var leg: Dictionary = _legs[i]
		var original := skeleton.get_bone_global_pose(int(leg.foot))
		var world := skeleton.global_transform*original
		if external_targets.size()==2:
			# A source settle step owns its continuous swing endpoint. The normal
			# clip-driven contact acquisition/release policy below remains intact.
			var target:Dictionary=external_targets[i]
			_anchor[i]=target.position
			_orientation[i]=target.rotation
			_contact[i]=bool(target.planted)
			_weight[i]=1.0
			if collect_debug:last_debug.append({"phase_height":0.0,"raw_world":world.origin,"old_contact":_contact[i],"old_anchor":_anchor[i],"old_weight":_weight[i],"source_settle":true})
			targets.append(inv*_anchor[i])
			rotations.append(inv.basis.orthonormalized().get_rotation_quaternion()*_orientation[i])
			continue
		# Source contact height is ANKLE_H=.085; the source's heel/toe roll lifts the ankle before swing.
		var offset := matcher.matched_pose*63+31+i*6
		var height := matcher._features[offset]*matcher._std[31+i*6]+matcher._mean[31+i*6]
		var contact := height<0.108
		if collect_debug:
			last_debug.append({"phase_height":height,"raw_world":world.origin,"old_contact":_contact[i],"old_anchor":_anchor[i],"old_weight":_weight[i],"raw_up_q":skeleton.get_bone_pose_rotation(int(leg.up)),"raw_low_q":skeleton.get_bone_pose_rotation(int(leg.low)),"raw_foot_q":skeleton.get_bone_pose_rotation(int(leg.foot)),"raw_knee":skeleton.get_bone_global_pose(int(leg.low)).origin,"raw_ankle":original.origin})
		var floor_y := root_position.y
		if ground_sampler.is_valid():
			var sample := float(ground_sampler.call(world.origin.x,world.origin.z,root_position.y+0.45))
			if is_finite(sample): floor_y = sample
		# The selected clip can be in stance while its inertialized output is still in swing.
		# Capture the real ankle near touchdown, then acquire its constraint continuously.
		if contact and not _contact[i]:
			# A retiring world anchor still contributes to the displayed ankle.
			# Replacing it with the new FK touchdown while its weight was 47%
			# moved that ankle ~20 cm in one side-turn frame. Finish the release
			# before acquiring the next stance, preserving the rendered endpoint.
			if world.origin.y-floor_y>0.122 or float(_weight[i])>0.02:
				contact = false
		if _contact[i]:
			var q := world.basis.orthonormalized().get_rotation_quaternion()
			var turn := InkInertializer._log_rotation(q*_orientation[i].inverse()).length()
			if world.origin.distance_to(_anchor[i])>0.33 or turn>0.85:
				contact = false
		if contact and not _contact[i]:
			_anchor[i] = world.origin
			_anchor[i].y = floor_y+0.085
			_orientation[i] = world.basis.orthonormalized().get_rotation_quaternion()
			_weight[i] = 0.0
			# A new stance begins in the current authored knee plane. Reusing the
			# residual plane from the previous step twisted the thigh on side turns.
			_planes[i] = Vector3.ZERO
		if contact:
			_weight[i] = lerpf(float(_weight[i]),1.0,1.0-exp(-dt*18.0))
		else:
			_weight[i] *= exp(-dt*24.0)
		_contact[i] = contact
		var position := world.origin.lerp(_anchor[i],float(_weight[i]))
		var quat := world.basis.orthonormalized().get_rotation_quaternion().slerp(_orientation[i],float(_weight[i]))
		targets.append(inv*position)
		rotations.append(inv.basis.orthonormalized().get_rotation_quaternion()*quat)
	# Original pelvis reach rule: drop only as much as a carrying leg needs.
	var hips := skeleton.find_bone("hips")
	var drop := 0.0
	for i in 2:
		if not _contact[i]: continue
		var leg: Dictionary = _legs[i]
		var thigh := skeleton.get_bone_global_pose(int(leg.up)).origin
		var horizontal := Vector2(targets[i].x-thigh.x,targets[i].z-thigh.z)
		var reach := (float(leg.a)+float(leg.b))*0.985*0.97
		var vertical := sqrt(maxf(0.0,reach*reach-horizontal.length_squared()))
		drop = maxf(drop,(thigh.y-targets[i].y-vertical)*float(_weight[i]))
	drop = clampf(drop,0.0,0.20)
	_hip_drop = lerpf(_hip_drop,drop,1.0-exp(-dt*(40.0 if drop>_hip_drop else 16.0)))
	if hips>=0:
		var hip_position := skeleton.get_bone_pose_position(hips)
		hip_position.y -= maxf(drop*0.85,_hip_drop)
		skeleton.set_bone_pose_position(hips,hip_position)
	last_contact_error = 0.0
	for i in 2:
		# Zero influence must retain the source clip's FK/IK pose. Re-solving an
		# unconstrained swing leg with a fixed pole can rotate its shin or ankle.
		if float(_weight[i])<0.0001:
			_planes[i] = Vector3.ZERO
			continue
		var forward := rotations[i]*Vector3.BACK
		var pole := Vector3(forward.x*0.7+(0.1 if i==0 else -0.1),0.05,forward.z*0.7+0.3)
		var previous_plane := inv.basis*_planes[i]
		var plane := _solve(skeleton,_legs[i],targets[i],pole,rotations[i],previous_plane,dt,float(_weight[i]))
		if collect_debug:
			last_debug[i].target = targets[i]
			last_debug[i].origin = skeleton.get_bone_global_pose(int(_legs[i].up)).origin
			last_debug[i].distance = (targets[i] as Vector3).distance_to(last_debug[i].origin)
			last_debug[i].plane = plane
			last_debug[i].solved_up_q=skeleton.get_bone_pose_rotation(int(_legs[i].up))
			last_debug[i].solved_low_q=skeleton.get_bone_pose_rotation(int(_legs[i].low))
			last_debug[i].solved_foot_q=skeleton.get_bone_pose_rotation(int(_legs[i].foot))
		_planes[i] = skeleton.global_basis*plane
		if _contact[i] and _weight[i]>0.999:
			var actual := skeleton.global_transform*skeleton.get_bone_global_pose(int(_legs[i].foot)).origin
			var error := actual.distance_to(_anchor[i])
			last_contact_error = maxf(last_contact_error,error)
			max_contact_error = maxf(max_contact_error,error)
			contact_samples += 1
	_last_root = root_position
	_was_enabled = true

static func _rest_frame(direction: Vector3) -> Basis:
	var h := (Vector3.RIGHT-direction*Vector3.RIGHT.dot(direction)).normalized()
	return Basis(direction,h,direction.cross(h)).transposed()

static func _solve(skeleton: Skeleton3D, leg: Dictionary, target: Vector3, pole: Vector3, end_rotation: Quaternion, previous_plane: Vector3, dt: float, influence: float = 1.0) -> Vector3:
	var parent := skeleton.get_bone_global_pose(int(leg.parent))
	var parent_q := parent.basis.orthonormalized().get_rotation_quaternion()
	var origin := parent*skeleton.get_bone_pose_position(int(leg.up))
	var a := float(leg.a)
	var b := float(leg.b)
	var direction := target-origin
	# Match the source's pre-solve swing-target clamp (legReach * .97). A nearly
	# straight knee amplifies centimetres of endpoint motion into large angle jumps.
	# The contact's soft-knee reach rule must fade with that contact. Applying it
	# at 0.5% residual influence still bent a fully extended source swing knee
	# by the entire stance correction during release / a new clip transition.
	var reach := (a+b)*lerpf(0.9995,0.985*0.97,clampf(influence,0.0,1.0))
	var distance := clampf(direction.length(),absf(a-b)+0.001,reach)
	direction = direction.normalized()
	var cos_a := clampf((a*a+distance*distance-b*b)/(2.0*a*distance),-1.0,1.0)
	var n := pole-direction*pole.dot(direction)
	if n.length_squared()<0.00000001:
		n = Vector3.BACK-direction*direction.z
	n = n.normalized()
	# Use the authored animated knee as the unconstrained plane, then approach
	# the source foot-facing pole with contact weight. Release restores swing.
	var animated := skeleton.get_bone_global_pose(int(leg.low)).origin-origin
	animated -= direction*animated.dot(direction)
	if animated.length_squared()>0.000001:
		n = animated.normalized().slerp(n,clampf(influence,0.0,1.0)).normalized()
	# A planted foot can put the original pole near the limb axis after a stop/turn.
	# Transport the bend plane continuously while keeping the exact ankle endpoint.
	var previous := previous_plane-direction*previous_plane.dot(direction)
	if previous.length_squared()>0.000001:
		previous = previous.normalized()
		var angle := previous.angle_to(n)
		if angle>0.00001:
			var transported := previous.slerp(n,minf(1.0,12.0*dt/angle)).normalized()
			# Plane stabilization belongs to the planted constraint. Its effect
			# fades with that constraint instead of overriding the swing pose.
			n = n.slerp(transported,influence*influence).normalized()
	var knee := origin+direction*a*cos_a+n*a*sqrt(1.0-cos_a*cos_a)
	var clamped_target := origin+direction*distance
	var h := n.cross(direction).normalized()
	var axis := (knee-origin).normalized()
	var global_up := (Basis(axis,h,axis.cross(h))*(leg.up_frame as Basis)).get_rotation_quaternion()
	var local_up := parent_q.inverse()*global_up
	skeleton.set_bone_pose_rotation(int(leg.up),local_up.normalized())
	axis = (clamped_target-knee).normalized()
	var global_low := (Basis(axis,h,axis.cross(h))*(leg.low_frame as Basis)).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(int(leg.low),(global_up.inverse()*global_low).normalized())
	skeleton.set_bone_pose_rotation(int(leg.foot),(global_low.inverse()*end_rotation).normalized())
	return n
