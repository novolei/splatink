extends "res://scripts/animation/ink_foot_plant.gd"
## Default-off physics experiment. configure and the limb solver are inherited.
## Contact/acquisition/release are copied verbatim; render state is never read.
var continuous_reach:bool=false
var collect_reach_diagnostics:bool=true
var apply_calls:int=0
var raw_pose_hip_y:float=0.0
var raw_pose_hip_y_available:bool=false
var measure_apply_time:bool=false
var pose_step_us:int=0
var last_reach_diagnostics:Dictionary={}

func apply(skeleton: Skeleton3D, dt: float, matcher: InkMotionMatcher, root_position: Vector3, ground_sampler: Callable, enabled: bool = true, external_targets:Array[Dictionary]=[]) -> void:
	var started:int=Time.get_ticks_usec() if measure_apply_time else 0
	if not continuous_reach and not collect_reach_diagnostics:
		# Nonlocal baseline callers use production arithmetic directly. The compact
		# packet reports the call, never invents missing component/target evidence.
		apply_calls+=1
		raw_pose_hip_y_available=false
		super.apply(skeleton,dt,matcher,root_position,ground_sampler,enabled,external_targets)
		pose_step_us=Time.get_ticks_usec()-started if measure_apply_time else 0
		last_reach_diagnostics={"call":apply_calls,"apply_calls":apply_calls,"tick":Engine.get_physics_frames(),"in_physics_frame":Engine.is_in_physics_frame(),"policy":"baseline","continuous_reach":false,"collect_reach_diagnostics":false,"enabled":enabled,"gate":"baseline_untraced","diagnostic_detail":"uncovered","dt":dt,"pose_step_us":pose_step_us}
		return
	var before:Dictionary=_begin_reach_diagnostics(skeleton,dt,root_position,enabled)
	if _legs.size()!=2:
		last_reach_diagnostics.gate="unconfigured"
		last_reach_diagnostics.reset_reason="unconfigured"
		_finish_reach_diagnostics(skeleton,before,started)
		return
	var teleported := _was_enabled and root_position.distance_squared_to(_last_root)>1.0
	last_reach_diagnostics.teleported=teleported
	if not enabled or teleported:
		last_reach_diagnostics.gate="teleported" if teleported else "disabled"
		last_reach_diagnostics.reset_reason=last_reach_diagnostics.gate
		_contact = [false,false]
		_weight = [0.0,0.0]
		_hip_drop = 0.0
		_planes.fill(Vector3.ZERO)
		_was_enabled = false
		_last_root = root_position
		_finish_reach_diagnostics(skeleton,before,started)
		return
	var targets: Array[Vector3] = []
	var rotations: Array[Quaternion] = []
	var inv := skeleton.global_transform.affine_inverse()
	last_reach_diagnostics.gate="applied"
	last_reach_diagnostics.eligible=true
	last_debug.clear()
	for i in 2:
		var leg: Dictionary = _legs[i]
		var original := skeleton.get_bone_global_pose(int(leg.foot))
		var world := skeleton.global_transform*original
		last_reach_diagnostics.raw_world_targets.append(world.origin)
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
	if continuous_reach:
		# The target already contains contact influence. Use exactly the solver's
		# influence-dependent reach, including retiring legs still sent to IK.
		for i in 2:
			if float(_weight[i])<0.0001:continue
			var leg:Dictionary=_legs[i]
			var thigh:Vector3=skeleton.get_bone_global_pose(int(leg.up)).origin
			var horizontal:=Vector2(targets[i].x-thigh.x,targets[i].z-thigh.z)
			var reach:float=(float(leg.a)+float(leg.b))*lerpf(0.9995,0.985*0.97,clampf(float(_weight[i]),0.0,1.0))
			var vertical:float=sqrt(maxf(0.0,reach*reach-horizontal.length_squared()))
			drop=maxf(drop,thigh.y-targets[i].y-vertical)
	else:
		# Baseline arithmetic and its ordering are copied from the production apply.
		for i in 2:
			if not _contact[i]: continue
			var leg: Dictionary = _legs[i]
			var thigh := skeleton.get_bone_global_pose(int(leg.up)).origin
			var horizontal := Vector2(targets[i].x-thigh.x,targets[i].z-thigh.z)
			var reach := (float(leg.a)+float(leg.b))*0.985*0.97
			var vertical := sqrt(maxf(0.0,reach*reach-horizontal.length_squared()))
			drop = maxf(drop,(thigh.y-targets[i].y-vertical)*float(_weight[i]))
	last_reach_diagnostics.required_drop_unclamped=drop
	drop = clampf(drop,0.0,0.20)
	last_reach_diagnostics.required_drop=drop
	last_reach_diagnostics.rig_space_targets=targets.duplicate()
	for i in 2:
		last_reach_diagnostics.weighted_world_targets.append(skeleton.global_transform*targets[i])
		last_reach_diagnostics.leg_reach.append(_pre_pelvis_leg_diagnostic(skeleton,i,targets[i]))
	_hip_drop = lerpf(_hip_drop,drop,1.0-exp(-dt*(40.0 if drop>_hip_drop else 16.0)))
	last_reach_diagnostics.applied_drop_requested=_hip_drop if continuous_reach else maxf(drop*0.85,_hip_drop)
	if hips>=0:
		var hip_position := skeleton.get_bone_pose_position(hips)
		if continuous_reach:
			hip_position.y -= _hip_drop
		else:
			hip_position.y -= maxf(drop*0.85,_hip_drop)
		skeleton.set_bone_pose_position(hips,hip_position)
	last_contact_error = 0.0
	for i in 2:
		_record_solver_request(skeleton,i,targets[i])
		# Zero influence must retain the source clip's FK/IK pose. Re-solving an
		# unconstrained swing leg with a fixed pole can rotate its shin or ankle.
		if float(_weight[i])<0.0001:
			_planes[i] = Vector3.ZERO
			_record_post_ik(skeleton,i,targets[i])
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
		_record_post_ik(skeleton,i,targets[i])
		if _contact[i] and _weight[i]>0.999:
			var actual := skeleton.global_transform*skeleton.get_bone_global_pose(int(_legs[i].foot)).origin
			var error := actual.distance_to(_anchor[i])
			last_contact_error = maxf(last_contact_error,error)
			max_contact_error = maxf(max_contact_error,error)
			contact_samples += 1
	_last_root = root_position
	_was_enabled = true
	_finish_reach_diagnostics(skeleton,before,started)

func _begin_reach_diagnostics(skeleton:Skeleton3D,dt:float,root_position:Vector3,enabled:bool) -> Dictionary:
	apply_calls+=1
	var positions:Array[Vector3]=[]
	var scales:Array[Vector3]=[]
	var hips:int=skeleton.find_bone("hips")
	for bone:int in skeleton.get_bone_count():
		positions.append(skeleton.get_bone_pose_position(bone))
		scales.append(skeleton.get_bone_pose_scale(bone))
	var hip_position:Vector3=positions[hips] if hips>=0 else Vector3.ZERO
	var hip_scale:Vector3=scales[hips] if hips>=0 else Vector3.ONE
	var hip_parent:int=skeleton.get_bone_parent(hips) if hips>=0 else -1
	var hip_axis:Vector3=skeleton.get_bone_global_pose(hip_parent).basis*Vector3.UP if hip_parent>=0 else Vector3.UP
	var raw_available:bool=raw_pose_hip_y_available and is_finite(raw_pose_hip_y)
	# Avatar publishes the current Tree sample before each apply. Consume this
	# availability token even on disabled/teleport/unconfigured gates, so a direct
	# later apply cannot advertise the preceding call's raw pose as a fresh sample.
	raw_pose_hip_y_available=false
	last_reach_diagnostics={"call":apply_calls,"apply_calls":apply_calls,"tick":Engine.get_physics_frames(),"in_physics_frame":Engine.is_in_physics_frame(),"policy":"continuous" if continuous_reach else "baseline","continuous_reach":continuous_reach,"enabled":enabled,"eligible":false,"gate":"pending","reset_reason":"","teleported":false,"dt":dt,"root_position":root_position,"bone_count":skeleton.get_bone_count(),"hip_index":hips,"hip_available":hips>=0,"pre_footplant_hip_position":hip_position,"pre_footplant_hip_scale":hip_scale,"pre_footplant_hip_y":hip_position.y,"raw_pose_hip_y":raw_pose_hip_y if raw_available else 0.0,"raw_pose_hip_y_available":raw_available,"required_drop":0.0,"required_drop_unclamped":0.0,"drop_state_previous":_hip_drop,"drop_state_next":_hip_drop,"applied_drop":0.0,"contacts_before":_contact.duplicate(),"weights_before":_weight.duplicate(),"contacts":[],"weights":[],"raw_world_targets":[],"weighted_world_targets":[],"rig_space_targets":[],"leg_reach":[],"local_component_rows":[],"vertical_drop_axis_rig":hip_axis,"vertical_drop_assumption_supported":hips>=0 and hip_axis.distance_to(Vector3.UP)<=0.00001,"skeleton_world_scale":skeleton.global_basis.get_scale(),"post_ik_observed":false,"clamp_count":0,"maximum_clamp_distance_m":0.0,"maximum_post_ik_target_error_m":0.0,"pose_step_us":0}
	return {"positions":positions,"scales":scales}

func _pre_pelvis_leg_diagnostic(skeleton:Skeleton3D,side:int,target:Vector3) -> Dictionary:
	var leg:Dictionary=_legs[side]
	var thigh:Vector3=skeleton.get_bone_global_pose(int(leg.up)).origin
	var weight:float=float(_weight[side])
	var a:float=float(leg.a)
	var b:float=float(leg.b)
	var reach:float=(a+b)*lerpf(0.9995,0.985*0.97,clampf(weight,0.0,1.0))
	var horizontal:=Vector2(target.x-thigh.x,target.z-thigh.z)
	var horizontal_squared:float=horizontal.length_squared()
	var vertical:float=sqrt(maxf(0.0,reach*reach-horizontal_squared))
	var baseline_reach:float=(a+b)*0.985*0.97
	var baseline_vertical:float=sqrt(maxf(0.0,baseline_reach*baseline_reach-horizontal_squared))
	var raw_required:float=thigh.y-target.y-vertical
	var contribution:float=raw_required if continuous_reach else (thigh.y-target.y-baseline_vertical)*weight
	var participates:bool=weight>=0.0001 if continuous_reach else bool(_contact[side])
	var lower:float=thigh.y-target.y-vertical
	var upper:float=thigh.y-target.y+vertical
	var reach_valid:bool=is_finite(reach) and is_finite(a) and is_finite(b) and a>0.0 and b>0.0 and reach>=absf(a-b)+0.001
	return {"side":side,"name":"L" if side==0 else "R","contact":bool(_contact[side]),"weight":weight,"required_participates":participates,"retiring":not bool(_contact[side]) and weight>=0.0001,"pre_thigh_rig_origin":thigh,"target_rig":target,"segment_a":a,"segment_b":b,"reach":reach,"maximum_reach":reach,"minimum_reach":absf(a-b)+0.001,"reach_valid":reach_valid,"horizontal_distance":horizontal.length(),"horizontal_deficit":maxf(0.0,horizontal.length()-reach),"vertical_capacity":vertical,"interval_lower":lower,"interval_upper":upper,"interval_feasible":reach_valid and horizontal_squared<=reach*reach,"interval_within_drop_limit":reach_valid and horizontal_squared<=reach*reach and maxf(0.0,lower)<=minf(0.20,upper),"raw_required_drop":raw_required,"required_contribution":contribution if participates else 0.0,"baseline_reach":baseline_reach,"solver_invoked":false,"post_ik_observed":false,"clamped":false,"would_clamp":false,"clamp_distance":0.0,"clamp_reason":""}

func _record_solver_request(skeleton:Skeleton3D,side:int,target:Vector3) -> void:
	var leg:Dictionary=_legs[side]
	var row:Dictionary=last_reach_diagnostics.leg_reach[side]
	# Repeat precisely the origin/reach/distance arithmetic at the inherited solver
	# entry, before it writes rotations. This does not invoke the solver twice.
	var parent:Transform3D=skeleton.get_bone_global_pose(int(leg.parent))
	var origin:Vector3=parent*skeleton.get_bone_pose_position(int(leg.up))
	var a:float=float(leg.a)
	var b:float=float(leg.b)
	var reach:float=(a+b)*lerpf(0.9995,0.985*0.97,clampf(float(_weight[side]),0.0,1.0))
	var requested:float=(target-origin).length()
	var clamped_distance:float=clampf(requested,absf(a-b)+0.001,reach)
	var invoked:bool=float(_weight[side])>=0.0001
	row.post_pelvis_origin=origin
	row.requested_distance=requested
	row.clamped_distance=clamped_distance
	row.deficit=maxf(0.0,requested-reach)
	row.minimum_deficit=maxf(0.0,absf(a-b)+0.001-requested)
	row.would_clamp=requested!=clamped_distance
	row.solver_invoked=invoked
	row.clamped=invoked and requested!=clamped_distance
	row.clamp_distance=absf(requested-clamped_distance) if invoked else 0.0
	row.would_clamp_distance=absf(requested-clamped_distance)
	row.clamp_reason=("too_far" if requested>reach else "too_near") if row.clamped else ""
	row.parent_scale=parent.basis.get_scale()
	row.applied_drop=last_reach_diagnostics.pre_footplant_hip_y-skeleton.get_bone_pose_position(int(last_reach_diagnostics.hip_index)).y if int(last_reach_diagnostics.hip_index)>=0 else 0.0

func _record_post_ik(skeleton:Skeleton3D,side:int,target:Vector3) -> void:
	var row:Dictionary=last_reach_diagnostics.leg_reach[side]
	var actual:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(int(_legs[side].foot)).origin
	var world_target:Vector3=skeleton.global_transform*target
	row.post_ik_world_foot=actual
	row.weighted_world_target=world_target
	row.post_ik_target_error_m=actual.distance_to(world_target)
	row.post_ik_anchor_error_m=actual.distance_to(_anchor[side])
	row.post_ik_observed=true

func _finish_reach_diagnostics(skeleton:Skeleton3D,before:Dictionary,started:int) -> void:
	var positions:Array[Vector3]=before.positions
	var scales:Array[Vector3]=before.scales
	var hips:int=int(last_reach_diagnostics.hip_index)
	var rows:Array[Dictionary]=[]
	var unexpected_positions:=0
	var unexpected_scales:=0
	var maximum_non_hips_delta:=0.0
	var maximum_scale_delta:=0.0
	for bone:int in skeleton.get_bone_count():
		var position:Vector3=skeleton.get_bone_pose_position(bone)
		var scale:Vector3=skeleton.get_bone_pose_scale(bone)
		var position_exact:bool=position==positions[bone]
		var scale_exact:bool=scale==scales[bone]
		var hip_y_only:bool=bone==hips and position.x==positions[bone].x and position.z==positions[bone].z
		var allowed:bool=position_exact or hip_y_only
		unexpected_positions+=int(not allowed)
		unexpected_scales+=int(not scale_exact)
		if bone!=hips:maximum_non_hips_delta=maxf(maximum_non_hips_delta,position.distance_to(positions[bone]))
		maximum_scale_delta=maxf(maximum_scale_delta,scale.distance_to(scales[bone]))
		rows.append({"index":bone,"name":String(skeleton.get_bone_name(bone)),"pre_position":positions[bone],"post_position":position,"pre_scale":scales[bone],"post_scale":scale,"position_exact":position_exact,"scale_exact":scale_exact,"position_change_allowed":allowed,"position_delta":position-positions[bone],"scale_delta":scale-scales[bone]})
	var hip_position:Vector3=skeleton.get_bone_pose_position(hips) if hips>=0 else Vector3.ZERO
	last_reach_diagnostics.post_footplant_hip_position=hip_position
	last_reach_diagnostics.post_footplant_hip_y=hip_position.y
	last_reach_diagnostics.post_footplant_hip_scale=skeleton.get_bone_pose_scale(hips) if hips>=0 else Vector3.ONE
	last_reach_diagnostics.drop_state_next=_hip_drop
	if not last_reach_diagnostics.has("applied_drop_requested"):last_reach_diagnostics.applied_drop_requested=0.0
	last_reach_diagnostics.applied_drop=float(last_reach_diagnostics.pre_footplant_hip_y)-hip_position.y if hips>=0 else 0.0
	last_reach_diagnostics.contacts=_contact.duplicate()
	last_reach_diagnostics.weights=_weight.duplicate()
	last_reach_diagnostics.local_component_rows=rows
	last_reach_diagnostics.unexpected_position_changes=unexpected_positions
	last_reach_diagnostics.unexpected_scale_changes=unexpected_scales
	last_reach_diagnostics.all_other_local_translations_exact=unexpected_positions==0
	last_reach_diagnostics.all_local_scales_exact=unexpected_scales==0
	last_reach_diagnostics.maximum_non_hips_position_delta_m=maximum_non_hips_delta
	last_reach_diagnostics.maximum_scale_delta=maximum_scale_delta
	last_reach_diagnostics.allowed_hips_y_change=hip_position.y-float(last_reach_diagnostics.pre_footplant_hip_y) if hips>=0 else 0.0
	var clamp_count:=0
	var maximum_clamp:=0.0
	var maximum_error:=0.0
	var interval_lower:=0.0
	var interval_upper:=0.20
	var participating_legs:=0
	var interval_feasible:=true
	for row:Dictionary in last_reach_diagnostics.leg_reach:
		clamp_count+=int(row.clamped)
		maximum_clamp=maxf(maximum_clamp,float(row.clamp_distance))
		maximum_error=maxf(maximum_error,float(row.get("post_ik_target_error_m",0.0)))
		if row.required_participates:
			participating_legs+=1
			interval_lower=maxf(interval_lower,float(row.interval_lower))
			interval_upper=minf(interval_upper,float(row.interval_upper))
			interval_feasible=interval_feasible and bool(row.interval_feasible)
	last_reach_diagnostics.clamp_count=clamp_count
	last_reach_diagnostics.maximum_clamp_distance_m=maximum_clamp
	last_reach_diagnostics.maximum_post_ik_target_error_m=maximum_error
	last_reach_diagnostics.post_ik_observed=not last_reach_diagnostics.leg_reach.is_empty()
	last_reach_diagnostics.participating_legs=participating_legs
	last_reach_diagnostics.reach_interval_lower=interval_lower
	last_reach_diagnostics.reach_interval_upper=interval_upper
	last_reach_diagnostics.reach_interval_feasible=last_reach_diagnostics.eligible and interval_feasible and interval_lower<=interval_upper and bool(last_reach_diagnostics.vertical_drop_assumption_supported)
	last_reach_diagnostics.required_drop_limited=last_reach_diagnostics.required_drop_unclamped>0.20
	pose_step_us=Time.get_ticks_usec()-started if measure_apply_time else 0
	last_reach_diagnostics.pose_step_us=pose_step_us
