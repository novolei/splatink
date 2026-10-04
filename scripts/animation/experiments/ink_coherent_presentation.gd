extends "res://scripts/animation/ink_pose_presentation.gd"
## Opt-in experiment: translate the visual root once, then reconstruct the two
## already-solved world FK feet. Actor physics, Hips and all animation clocks stay
## authoritative. Targets are physics FK endpoints, never raw FootPlant anchors.

const LEG_NAMES := ["thighL", "shinL", "footL", "toeL", "thighR", "shinR", "footR", "toeR"]
const GEOMETRY_EPSILON := 0.00000001
const LENGTH_REPORT_EPSILON := 0.00001

var _primary:Skeleton3D
var _legs:Array[Dictionary]=[]
var _world_previous:Array[Dictionary]=[]
var _world_current:Array[Dictionary]=[]
var _modules:Array[Dictionary]=[]
var _last_owner:WeakRef
var _configuration_ok:=false
var _total_reach_clamps:=0
var _total_significant_reach_clamps:=0
var _maximum_target_error:=0.0
var _maximum_reach_clamp:=0.0

# Structured diagnostics deliberately stay outside the numeric profile consumed
# by InkGame. Every render reports both legs, including every geometric clamp.
var last_leg_diagnostics:Array[Dictionary]=[]
var maximum_target_diagnostic:Dictionary={}
var expected_world_feet:=PackedVector3Array()
var actual_world_feet:=PackedVector3Array()

func configure(rigs:Array[Skeleton3D],nodes:Array[Node3D],materials:Array[Dictionary],uniform_setter:Callable,bone_indices:Array[PackedInt32Array]=[],render_bones:Array[PackedInt32Array]=[],rig_visibility:Array[Node3D]=[],interpolate_root:bool=true) -> void:
	_restore_last_owner()
	_primary=null
	_legs.clear()
	_modules.clear()
	_clear_world_packets()
	_last_owner=null
	_configuration_ok=false
	_total_reach_clamps=0
	_total_significant_reach_clamps=0
	_maximum_target_error=0.0
	_maximum_reach_clamp=0.0
	maximum_target_diagnostic.clear()
	# The inherited signature is retained. This experiment owns only the primary
	# eight leg joints; extra rigs use explicit lower-only configure_modules maps.
	# Node/material interpolation and the full-transform root option are ignored.
	var primary_rigs:Array[Skeleton3D]=[]
	var selected:Array[PackedInt32Array]=[]
	var visibility:Array[Node3D]=[]
	if not rigs.is_empty() and is_instance_valid(rigs[0]):
		_primary=rigs[0]
		var indices:=PackedInt32Array()
		for bone_name:String in LEG_NAMES:indices.append(_primary.find_bone(bone_name))
		if not indices.has(-1):
			primary_rigs.append(_primary)
			selected.append(indices)
			visibility.append(rig_visibility[0] if not rig_visibility.is_empty() else _primary)
			for side:int in 2:
				var up:int=indices[side*4]
				var low:int=indices[side*4+1]
				var foot:int=indices[side*4+2]
				if _primary.get_bone_parent(low)!=up or _primary.get_bone_parent(foot)!=low:
					push_error("Coherent presentation requires direct thigh/shin/foot chains")
					_legs.clear()
					break
				_legs.append({"up":up,"low":low,"foot":foot,"parent":_primary.get_bone_parent(up),"up_slot":side*4,"low_slot":side*4+1,"foot_slot":side*4+2})
		else:push_error("Coherent presentation requires all eight original leg joints")
	else:push_error("Coherent presentation requires a primary Skeleton3D")
	super.configure(primary_rigs,[],[],Callable(),selected,selected,visibility,false)
	_configuration_ok=_legs.size()==2 and _legs[0].parent>=0 and _legs[1].parent>=0
	# Record unused legacy switches explicitly without adopting their behavior.
	profile.ignored_node_count=nodes.size()
	profile.ignored_material_count=materials.size()
	profile.ignored_extra_rig_count=maxi(0,rigs.size()-1)
	profile.supplied_capture_masks=bone_indices.size()
	profile.supplied_render_masks=render_bones.size()
	profile.supplied_uniform_setter=int(uniform_setter.is_valid())
	profile.supplied_full_root_switch=int(interpolate_root)

func configure_modules(bindings:Array[Dictionary]) -> void:
	if valid or rendered:
		push_error("Configure coherent lower modules before the first physics capture")
		return
	_modules.clear()
	if not _configuration_ok:return
	var seen:Dictionary={}
	for binding:Dictionary in bindings:
		var node:Skeleton3D=binding.get("node") as Skeleton3D
		var indices_value:Variant=binding.get("indices")
		var sources_value:Variant=binding.get("sources")
		var offsets_value:Variant=binding.get("offsets")
		if not is_instance_valid(node) or node==_primary or not indices_value is PackedInt32Array or not sources_value is PackedInt32Array or not offsets_value is PackedVector3Array:
			_reject_module_configuration("Coherent module binding has invalid node or array types")
			return
		var indices:PackedInt32Array=indices_value
		var sources:PackedInt32Array=sources_value
		var offsets:PackedVector3Array=offsets_value
		if indices.is_empty() or indices.size()!=sources.size() or indices.size()!=offsets.size():
			_reject_module_configuration("Coherent module binding arrays must have equal nonzero sizes")
			return
		var allowed:PackedInt32Array=_rigs[0].indices
		for slot:int in indices.size():
			var key:=str(node.get_instance_id())+":"+str(indices[slot])
			if indices[slot]<0 or indices[slot]>=node.get_bone_count() or not allowed.has(sources[slot]) or not offsets[slot].is_finite() or seen.has(key):
				_reject_module_configuration("Coherent module binding contains invalid, duplicate or nonlower joints")
				return
			seen[key]=true
		var positions:Array[Vector3]=[]
		var rotations:Array[Quaternion]=[]
		var scales:Array[Vector3]=[]
		positions.resize(indices.size())
		rotations.resize(indices.size())
		scales.resize(indices.size())
		var written:=PackedByteArray()
		written.resize(indices.size())
		written.fill(0)
		_modules.append({"node":node,"indices":indices.duplicate(),"sources":sources.duplicate(),"offsets":offsets.duplicate(),"positions":positions,"rotations":rotations,"scales":scales,"written":written})

func _reject_module_configuration(message:String) -> void:
	push_error(message)
	_modules.clear()
	_configuration_ok=false

func capture(owner:Node3D,force_reset:bool=false) -> void:
	if not _configuration_ok or not is_instance_valid(_primary):return
	if rendered:
		# Restoring here could overwrite a caller's newly advanced physics pose.
		# The owner must restore before advancing physics, as with the base class.
		push_error("Coherent capture requires restoration before physics animation advances")
		return
	var begin:=Time.get_ticks_usec()
	var fresh:bool=force_reset or not valid or _world_current.size()!=2 or owner.global_position.distance_squared_to(_current_root.origin)>16.0
	super.capture(owner,force_reset)
	_last_owner=weakref(owner)
	# Contact/held joints also interpolate before world endpoint reconstruction.
	# The held mask remains available for diagnostics, never as a render exclusion.
	var entry:Dictionary=_rigs[0]
	var dynamic:=PackedInt32Array()
	var previous:Array[Transform3D]=entry.previous
	var current:Array[Transform3D]=entry.current
	for slot:int in current.size():
		if previous[slot]!=current[slot]:dynamic.append(slot)
	entry.dynamic=dynamic
	var packet:Array[Dictionary]=[]
	for leg:Dictionary in _legs:
		var world:Transform3D=_primary.global_transform*_primary.get_bone_global_pose(int(leg.foot))
		packet.append({"foot":world.origin,"knee":_primary.global_transform*_primary.get_bone_global_pose(int(leg.low)).origin,"rotation":world.basis.orthonormalized().get_rotation_quaternion()})
	_world_previous=_world_current
	_world_current=packet
	if fresh:_world_previous=packet.duplicate(true)
	var module_slots:=0
	for module:Dictionary in _modules:
		var rig:Skeleton3D=module.node
		if not is_instance_valid(rig):
			push_error("Coherent lower module was freed before capture")
			invalidate()
			return
		var indices:PackedInt32Array=module.indices
		var positions:Array[Vector3]=module.positions
		var rotations:Array[Quaternion]=module.rotations
		var scales:Array[Vector3]=module.scales
		var written:PackedByteArray=module.written
		written.fill(0)
		for slot:int in indices.size():
			positions[slot]=rig.get_bone_pose_position(indices[slot])
			rotations[slot]=rig.get_bone_pose_rotation(indices[slot])
			scales[slot]=rig.get_bone_pose_scale(indices[slot])
		module.written=written
		module_slots+=indices.size()
	profile.dynamic_bones=dynamic.size()
	profile.capture_bones=current.size()+module_slots
	profile.module_capture_bones=module_slots
	profile.packet_reset=int(fresh)
	profile.capture_us=Time.get_ticks_usec()-begin

func restore(owner:Node3D,preserve_root:bool=false) -> void:
	if not valid or not rendered:return
	var begin:=Time.get_ticks_usec()
	if not preserve_root:owner.transform=_tick_local_root
	# Restore every written slot, including held and otherwise nondynamic joints.
	for entry:Dictionary in _rigs:
		var rig:Skeleton3D=entry.node
		if not is_instance_valid(rig):continue
		var indices:PackedInt32Array=entry.indices
		var positions:Array[Vector3]=entry.positions
		var rotations:Array[Quaternion]=entry.rotations
		var scales:Array[Vector3]=entry.scales
		var written:PackedByteArray=entry.written
		var output:Array[Transform3D]=entry.output
		var current:Array[Transform3D]=entry.current
		for slot:int in indices.size():
			if not written[slot]:continue
			rig.set_bone_pose_position(indices[slot],positions[slot])
			rig.set_bone_pose_rotation(indices[slot],rotations[slot])
			rig.set_bone_pose_scale(indices[slot],scales[slot])
			output[slot]=current[slot]
			written[slot]=0
		entry.written=written
	for module:Dictionary in _modules:
		var rig:Skeleton3D=module.node
		if not is_instance_valid(rig):continue
		var indices:PackedInt32Array=module.indices
		var positions:Array[Vector3]=module.positions
		var rotations:Array[Quaternion]=module.rotations
		var scales:Array[Vector3]=module.scales
		var written:PackedByteArray=module.written
		for slot:int in indices.size():
			if not written[slot]:continue
			rig.set_bone_pose_position(indices[slot],positions[slot])
			rig.set_bone_pose_rotation(indices[slot],rotations[slot])
			rig.set_bone_pose_scale(indices[slot],scales[slot])
			written[slot]=0
		module.written=written
	rendered=false
	profile.restore_us=Time.get_ticks_usec()-begin

func invalidate() -> void:
	_restore_last_owner()
	super.invalidate()
	_clear_world_packets()

func _restore_last_owner() -> void:
	if not rendered or _last_owner==null:return
	var owner:Node3D=_last_owner.get_ref() as Node3D
	if is_instance_valid(owner):restore(owner)

func _clear_world_packets() -> void:
	_world_previous.clear()
	_world_current.clear()
	last_leg_diagnostics.clear()
	expected_world_feet.clear()
	actual_world_feet.clear()

func render(owner:Node3D,fraction:float) -> bool:
	if not valid or not _configuration_ok or _world_previous.size()!=2 or _world_current.size()!=2:return false
	if not is_finite(fraction):
		push_error("Coherent presentation interpolation fraction is not finite")
		return false
	var begin:=Time.get_ticks_usec()
	# A render never uses the preceding render's corrections as an FK input.
	restore(owner)
	var alpha:=clampf(fraction,0.0,1.0)
	var displayed_origin:Vector3=_previous_root.origin.lerp(_current_root.origin,alpha)
	var parent:Node3D=owner.get_parent_node_3d()
	# Assign only local translation. A whole global_transform assignment performs
	# parent-basis inverse/composition and perturbs authoritative local basis bits.
	owner.position=parent.global_transform.affine_inverse()*displayed_origin if parent!=null else displayed_origin
	if not super.render(owner,alpha):return false
	var local_writes:int=int(profile.get("bone_writes",0))
	last_leg_diagnostics.clear()
	expected_world_feet.clear()
	actual_world_feet.clear()
	var inverse:Transform3D=_primary.global_transform.affine_inverse()
	var inverse_rotation:Quaternion=_primary.global_basis.orthonormalized().get_rotation_quaternion().inverse()
	var clamps:=0
	var significant_clamps:=0
	var maximum_clamp:=0.0
	var maximum_error:=0.0
	var maximum_rotation_error:=0.0
	var maximum_length_error:=0.0
	var maximum_world_length_error:=0.0
	var unsupported_affine:=0
	var geometry_writes:=0
	for side:int in 2:
		var before:Dictionary=_world_previous[side]
		var after:Dictionary=_world_current[side]
		var target_world:Vector3=(before.foot as Vector3).lerp(after.foot,alpha)
		var knee_world:Vector3=(before.knee as Vector3).lerp(after.knee,alpha)
		var foot_world_rotation:Quaternion=(before.rotation as Quaternion).slerp(after.rotation,alpha).normalized()
		var result:Dictionary=_solve_leg(_legs[side],inverse*target_world,inverse*knee_world,(inverse_rotation*foot_world_rotation).normalized())
		var actual:Transform3D=_primary.global_transform*_primary.get_bone_global_pose(int(_legs[side].foot))
		var error:float=actual.origin.distance_to(target_world)
		var rotation_error:float=actual.basis.orthonormalized().get_rotation_quaternion().angle_to(foot_world_rotation)
		expected_world_feet.append(target_world)
		actual_world_feet.append(actual.origin)
		result.side=side
		result.fraction=alpha
		result.physics_sample=physics_samples
		result.expected_world_foot=target_world
		result.actual_world_foot=actual.origin
		result.expected_world_error_m=error
		result.world_rotation_error_rad=rotation_error
		if error>_maximum_target_error:
			_maximum_target_error=error
			maximum_target_diagnostic=result.duplicate(true)
		last_leg_diagnostics.append(result)
		clamps+=int(result.clamped)
		significant_clamps+=int(float(result.clamp_distance)>LENGTH_REPORT_EPSILON)
		maximum_clamp=maxf(maximum_clamp,float(result.clamp_distance))
		maximum_error=maxf(maximum_error,error)
		maximum_rotation_error=maxf(maximum_rotation_error,rotation_error)
		maximum_length_error=maxf(maximum_length_error,float(result.length_error))
		maximum_world_length_error=maxf(maximum_world_length_error,float(result.world_length_error))
		unsupported_affine+=int(result.unsupported_affine)
		geometry_writes+=int(result.writes)
	_total_reach_clamps+=clamps
	_total_significant_reach_clamps+=significant_clamps
	_maximum_reach_clamp=maxf(_maximum_reach_clamp,maximum_clamp)
	_maximum_target_error=maxf(_maximum_target_error,maximum_error)
	var module_writes:int=_copy_lower_modules()
	var entry:Dictionary=_rigs[0]
	var written:PackedByteArray=entry.written
	var indices:PackedInt32Array=entry.indices
	var held:Dictionary=entry.held
	var primary_writes:=0
	var held_writes:=0
	for slot:int in written.size():
		if not written[slot]:continue
		primary_writes+=1
		held_writes+=int(held.has(indices[slot]))
	profile.local_bone_writes=local_writes
	profile.geometry_bone_writes=geometry_writes
	profile.bone_writes=primary_writes
	profile.held_bone_writes=held_writes
	profile.swing_bone_writes=primary_writes-held_writes
	profile.module_bone_writes=module_writes
	profile.world_fk_legs=2
	profile.expected_world_foot_error_m=maximum_error
	profile.maximum_expected_world_foot_error_m=_maximum_target_error
	profile.world_foot_rotation_error_rad=maximum_rotation_error
	profile.bone_length_error_m=maximum_length_error
	profile.world_bone_length_error_m=maximum_world_length_error
	profile.nonuniform_rig_transform=int(not _uniform_basis(_primary.global_basis))
	profile.reach_clamps=clamps
	profile.significant_reach_clamps=significant_clamps
	profile.total_reach_clamps=_total_reach_clamps
	profile.total_significant_reach_clamps=_total_significant_reach_clamps
	profile.reach_clamp_distance_m=maximum_clamp
	profile.maximum_reach_clamp_distance_m=_maximum_reach_clamp
	profile.unsupported_affine_legs=unsupported_affine
	profile.root_origin_only=1
	profile.node_writes=0
	profile.render_us=Time.get_ticks_usec()-begin
	return true

func position_at(_fraction:float) -> Vector3:
	# The camera keeps its current authoritative target in this experiment.
	return _current_root.origin

func _solve_leg(leg:Dictionary,target:Vector3,knee_hint:Vector3,end_rotation:Quaternion) -> Dictionary:
	var up:int=leg.up
	var low:int=leg.low
	var foot:int=leg.foot
	var parent:Transform3D=_primary.get_bone_global_pose(int(leg.parent))
	var original_up:Transform3D=_primary.get_bone_global_pose(up)
	var original_low:Transform3D=_primary.get_bone_global_pose(low)
	var original_foot:Transform3D=_primary.get_bone_global_pose(foot)
	var origin:Vector3=original_up.origin
	var a:float=origin.distance_to(original_low.origin)
	var b:float=original_low.origin.distance_to(original_foot.origin)
	var rig_world:Transform3D=_primary.global_transform
	var world_a:float=(rig_world*origin).distance_to(rig_world*original_low.origin)
	var world_b:float=(rig_world*original_low.origin).distance_to(rig_world*original_foot.origin)
	var result:Dictionary={"clamped":false,"clamp_reason":"","clamp_distance":0.0,"requested_distance":origin.distance_to(target),"minimum_reach":absf(a-b),"maximum_reach":a+b,"segment_a":a,"segment_b":b,"origin_local":origin,"target_local":target,"knee_hint_local":knee_hint,"length_error":0.0,"world_length_error":0.0,"unsupported_affine":false,"writes":0}
	# Quaternion-only corrections preserve segment lengths under uniform parent
	# scales. Nonuniform ancestor scales require a different affine solver; expose
	# this limit instead of silently stretching bones or changing the physics pose.
	if not _uniform_basis(parent.basis) or not _uniform_basis(original_up.basis) or not _uniform_basis(original_low.basis) or a<=GEOMETRY_EPSILON or b<=GEOMETRY_EPSILON:
		result.unsupported_affine=true
		return result
	var direction:Vector3=target-origin
	var requested:float=direction.length()
	var minimum:float=maxf(absf(a-b),GEOMETRY_EPSILON)
	var maximum:float=a+b
	var distance:float=clampf(requested,minimum,maximum)
	result.minimum_reach=minimum
	result.clamped=requested<minimum or requested>maximum
	result.clamp_reason="too_far" if requested>maximum else "too_close" if requested<minimum else ""
	result.clamp_distance=absf(distance-requested)
	if requested<=GEOMETRY_EPSILON:
		direction=(original_foot.origin-origin).normalized()
		if direction.length_squared()<GEOMETRY_EPSILON:direction=Vector3.DOWN
	else:direction/=requested
	var bend:Vector3=knee_hint-origin
	bend-=direction*bend.dot(direction)
	if bend.length_squared()<GEOMETRY_EPSILON:
		bend=original_low.origin-origin
		bend-=direction*bend.dot(direction)
	if bend.length_squared()<GEOMETRY_EPSILON:
		var fallback:Vector3=Vector3.RIGHT if absf(direction.x)<0.8 else Vector3.FORWARD
		bend=fallback-direction*fallback.dot(direction)
	bend=bend.normalized()
	var cosine:float=clampf((a*a+distance*distance-b*b)/(2.0*a*distance),-1.0,1.0)
	var knee:Vector3=origin+direction*a*cosine+bend*a*sqrt(maxf(0.0,1.0-cosine*cosine))
	var endpoint:Vector3=origin+direction*distance
	var parent_q:Quaternion=parent.basis.orthonormalized().get_rotation_quaternion()
	# Pre-multiplying the current animated global joint orientation by its shortest
	# direction correction carries the original animation twist with the segment.
	var up_q:Quaternion=original_up.basis.orthonormalized().get_rotation_quaternion()
	var new_up_q:Quaternion=(_direction_rotation(original_low.origin-origin,knee-origin,bend)*up_q).normalized()
	result.writes+=_write_primary_rotation(int(leg.up_slot),(parent_q.inverse()*new_up_q).normalized())
	var moved_low:Transform3D=_primary.get_bone_global_pose(low)
	var moved_foot:Transform3D=_primary.get_bone_global_pose(foot)
	var low_q:Quaternion=moved_low.basis.orthonormalized().get_rotation_quaternion()
	var new_low_q:Quaternion=(_direction_rotation(moved_foot.origin-moved_low.origin,endpoint-moved_low.origin,bend)*low_q).normalized()
	var actual_up_q:Quaternion=_primary.get_bone_global_pose(up).basis.orthonormalized().get_rotation_quaternion()
	result.writes+=_write_primary_rotation(int(leg.low_slot),(actual_up_q.inverse()*new_low_q).normalized())
	var actual_low_q:Quaternion=_primary.get_bone_global_pose(low).basis.orthonormalized().get_rotation_quaternion()
	result.writes+=_write_primary_rotation(int(leg.foot_slot),(actual_low_q.inverse()*end_rotation).normalized())
	var solved_up:Vector3=_primary.get_bone_global_pose(up).origin
	var solved_low:Vector3=_primary.get_bone_global_pose(low).origin
	var solved_foot:Vector3=_primary.get_bone_global_pose(foot).origin
	result.length_error=maxf(absf(solved_up.distance_to(solved_low)-a),absf(solved_low.distance_to(solved_foot)-b))
	result.world_length_error=maxf(absf((rig_world*solved_up).distance_to(rig_world*solved_low)-world_a),absf((rig_world*solved_low).distance_to(rig_world*solved_foot)-world_b))
	return result

func _write_primary_rotation(slot:int,rotation:Quaternion) -> int:
	var entry:Dictionary=_rigs[0]
	var indices:PackedInt32Array=entry.indices
	var bone:int=indices[slot]
	if _primary.get_bone_pose_rotation(bone)==rotation:return 0
	_primary.set_bone_pose_rotation(bone,rotation)
	var written:PackedByteArray=entry.written
	written[slot]=1
	entry.written=written
	var output:Array[Transform3D]=entry.output
	output[slot]=_primary.get_bone_pose(bone)
	return 1

func _copy_lower_modules() -> int:
	var writes:=0
	for module:Dictionary in _modules:
		var rig:Skeleton3D=module.node
		if not is_instance_valid(rig):continue
		var indices:PackedInt32Array=module.indices
		var sources:PackedInt32Array=module.sources
		var offsets:PackedVector3Array=module.offsets
		var written:PackedByteArray=module.written
		for slot:int in indices.size():
			var position:Vector3=_primary.get_bone_pose_position(sources[slot])+offsets[slot]
			var rotation:Quaternion=_primary.get_bone_pose_rotation(sources[slot])
			var scale:Vector3=_primary.get_bone_pose_scale(sources[slot])
			var bone:int=indices[slot]
			if rig.get_bone_pose_position(bone)==position and rig.get_bone_pose_rotation(bone)==rotation and rig.get_bone_pose_scale(bone)==scale:continue
			rig.set_bone_pose_position(bone,position)
			rig.set_bone_pose_rotation(bone,rotation)
			rig.set_bone_pose_scale(bone,scale)
			written[slot]=1
			writes+=1
		module.written=written
	return writes

static func _uniform_basis(basis:Basis) -> bool:
	var scale:Vector3=basis.get_scale().abs()
	var largest:float=maxf(scale.x,maxf(scale.y,scale.z))
	var smallest:float=minf(scale.x,minf(scale.y,scale.z))
	if not scale.is_finite() or smallest<=GEOMETRY_EPSILON or largest-smallest>largest*0.00001 or basis.determinant()<=0.0:return false
	var x:Vector3=basis.x.normalized()
	var y:Vector3=basis.y.normalized()
	var z:Vector3=basis.z.normalized()
	return maxf(absf(x.dot(y)),maxf(absf(y.dot(z)),absf(z.dot(x))))<=0.00001

static func _direction_rotation(from:Vector3,to:Vector3,fallback:Vector3) -> Quaternion:
	if from.length_squared()<GEOMETRY_EPSILON or to.length_squared()<GEOMETRY_EPSILON:return Quaternion.IDENTITY
	var a:Vector3=from.normalized()
	var b:Vector3=to.normalized()
	if a.dot(b)<-0.999999:
		var axis:Vector3=fallback-a*fallback.dot(a)
		if axis.length_squared()<GEOMETRY_EPSILON:
			var candidate:Vector3=Vector3.RIGHT if absf(a.x)<0.8 else Vector3.UP
			axis=candidate-a*candidate.dot(a)
		return Quaternion(axis.normalized(),PI)
	return Quaternion(a,b).normalized()
