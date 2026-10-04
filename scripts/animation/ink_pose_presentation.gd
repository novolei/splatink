class_name InkPosePresentation
extends RefCounted
## Optional render-only interpolation of two completely solved physics poses.
## The owner restores the current authoritative packet before advancing animation.
## Neither the AnimationTree nor MM/IK/spring clocks advance during render().

const DYNAMIC_UNIFORMS := [&"uTime",&"uHurt",&"uWig",&"charge",&"uFlash",&"uGlow",&"uCharge",&"uFull",&"emission_color",&"emission_intensity"]
var _rigs:Array[Dictionary]=[]
var _nodes:Array[Node3D]=[]
var _node_previous:Array[Transform3D]=[]
var _node_current:Array[Transform3D]=[]
var _node_output:Array[Transform3D]=[]
var _node_dynamic:=PackedInt32Array()
var _node_written:=PackedByteArray()
var _materials:Array[Dictionary]=[]
var _uniform_setter:Callable
var _previous_root:=Transform3D.IDENTITY
var _current_root:=Transform3D.IDENTITY
var _tick_local_root:=Transform3D.IDENTITY
var _interpolate_root:=true
var valid:=false
var rendered:=false
var physics_samples:=0
var render_samples:=0
var profile:Dictionary={}

func configure(rigs:Array[Skeleton3D],nodes:Array[Node3D],materials:Array[Dictionary],uniform_setter:Callable,bone_indices:Array[PackedInt32Array]=[],render_bones:Array[PackedInt32Array]=[],rig_visibility:Array[Node3D]=[],interpolate_root:bool=true) -> void:
	_rigs.clear()
	_nodes.clear()
	_materials.clear()
	_uniform_setter=uniform_setter
	_interpolate_root=interpolate_root
	for rig_index:int in rigs.size():
		var rig:Skeleton3D=rigs[rig_index]
		if not is_instance_valid(rig):continue
		var indices:=PackedInt32Array()
		if rig_index<bone_indices.size():indices=bone_indices[rig_index]
		else:
			for bone:int in rig.get_bone_count():indices.append(bone)
		var previous:Array[Transform3D]=[]
		var current:Array[Transform3D]=[]
		var positions:Array[Vector3]=[]
		var rotations:Array[Quaternion]=[]
		var scales:Array[Vector3]=[]
		var output:Array[Transform3D]=[]
		var written:=PackedByteArray()
		previous.resize(indices.size())
		current.resize(indices.size())
		positions.resize(indices.size())
		rotations.resize(indices.size())
		scales.resize(indices.size())
		output.resize(indices.size())
		written.resize(indices.size())
		var allowed:Dictionary={}
		var selected:PackedInt32Array=render_bones[rig_index] if rig_index<render_bones.size() else indices
		for bone:int in selected:allowed[bone]=true
		var shown:Node3D=rig_visibility[rig_index] if rig_index<rig_visibility.size() else rig
		_rigs.append({"node":rig,"indices":indices,"previous":previous,"current":current,"positions":positions,"rotations":rotations,"scales":scales,"output":output,"written":written,"dynamic":PackedInt32Array(),"allowed":allowed,"held":{},"visibility":shown})
	for node:Node3D in nodes:
		if is_instance_valid(node) and not node in _nodes:_nodes.append(node)
	_node_previous.resize(_nodes.size())
	_node_current.resize(_nodes.size())
	_node_output.resize(_nodes.size())
	_node_written.resize(_nodes.size())
	_node_dynamic.clear()
	for entry:Dictionary in materials:
		_materials.append({"entry":entry,"previous":{},"current":{},"dynamic":[],"written":{}})
	valid=false
	rendered=false
	physics_samples=0
	render_samples=0
	profile.clear()

func set_render_bones(rig_index:int,indices:PackedInt32Array) -> void:
	if rig_index<0 or rig_index>=_rigs.size():return
	var allowed:Dictionary={}
	for bone:int in indices:allowed[bone]=true
	_rigs[rig_index].allowed=allowed

func set_held_bones(rig_index:int,indices:PackedInt32Array) -> void:
	if rig_index<0 or rig_index>=_rigs.size():return
	var held:Dictionary={}
	for bone:int in indices:held[bone]=true
	_rigs[rig_index].held=held

func invalidate() -> void:
	# Caller restores before changing authoritative pose or mode. The next packet
	# starts fresh instead of blending across an air/form/full-body transition.
	valid=false
	rendered=false

func capture(owner:Node3D,force_reset:bool=false) -> void:
	var begin:=Time.get_ticks_usec()
	var fresh:bool=force_reset or not valid or owner.global_position.distance_squared_to(_current_root.origin)>16.0
	_previous_root=_current_root
	_current_root=owner.global_transform
	_tick_local_root=owner.transform
	var captured_bones:=0
	var dynamic_bones:=0
	var eligible_bones:=0
	var held_bones:=0
	for entry:Dictionary in _rigs:
		var rig:Skeleton3D=entry.node
		var previous:Array[Transform3D]=entry.previous
		var current:Array[Transform3D]=entry.current
		var indices:PackedInt32Array=entry.indices
		var positions:Array[Vector3]=entry.positions
		var rotations:Array[Quaternion]=entry.rotations
		var scales:Array[Vector3]=entry.scales
		var output:Array[Transform3D]=entry.output
		var written:PackedByteArray=entry.written
		var dynamic:=PackedInt32Array()
		var allowed:Dictionary=entry.allowed
		var held:Dictionary=entry.held
		for bone:int in current.size():
			previous[bone]=current[bone]
			current[bone]=rig.get_bone_pose(indices[bone])
			# Preserve the authoritative quaternion itself. Converting its basis
			# back into a quaternion changes float32 low bits and query costs.
			positions[bone]=rig.get_bone_pose_position(indices[bone])
			rotations[bone]=rig.get_bone_pose_rotation(indices[bone])
			scales[bone]=rig.get_bone_pose_scale(indices[bone])
			if fresh:previous[bone]=current[bone]
			output[bone]=current[bone]
			written[bone]=0
			# Exact equality only: skip no genuinely changing component, including
			# the smallest authored secondary motion. Authority capture stays full.
			if allowed.has(indices[bone]):
				if held.has(indices[bone]):held_bones+=1
				elif previous[bone]!=current[bone]:dynamic.append(bone)
		entry.dynamic=dynamic
		entry.written=written
		captured_bones+=current.size()
		dynamic_bones+=dynamic.size()
		eligible_bones+=allowed.size()
	_node_dynamic.clear()
	_node_written.fill(0)
	for i:int in _nodes.size():
		_node_previous[i]=_node_current[i]
		_node_current[i]=_nodes[i].transform
		if fresh:_node_previous[i]=_node_current[i]
		_node_output[i]=_node_current[i]
		if _node_previous[i]!=_node_current[i]:_node_dynamic.append(i)
	for material:Dictionary in _materials:
		var sent:Dictionary=(material.entry as Dictionary).sent
		var previous:Dictionary=material.previous
		var current:Dictionary=material.current
		var dynamic:Array=material.dynamic
		dynamic.clear()
		(material.written as Dictionary).clear()
		for parameter:StringName in DYNAMIC_UNIFORMS:
			if not sent.has(parameter):continue
			previous[parameter]=current.get(parameter,sent[parameter])
			current[parameter]=sent[parameter]
			if fresh:previous[parameter]=current[parameter]
			if previous[parameter]!=current[parameter]:dynamic.append(parameter)
	if fresh:_previous_root=_current_root
	valid=true
	rendered=false
	physics_samples+=1
	profile.capture_us=Time.get_ticks_usec()-begin
	profile.capture_bones=captured_bones
	profile.dynamic_bones=dynamic_bones
	profile.eligible_bones=eligible_bones
	profile.held_bones=held_bones
	profile.swing_bones=eligible_bones-held_bones
	profile.dynamic_nodes=_node_dynamic.size()

func restore(owner:Node3D,preserve_root:bool=false) -> void:
	if not valid or not rendered:return
	var begin:=Time.get_ticks_usec()
	if _interpolate_root and not preserve_root:owner.transform=_tick_local_root
	for entry:Dictionary in _rigs:
		var rig:Skeleton3D=entry.node
		var current:Array[Transform3D]=entry.current
		var indices:PackedInt32Array=entry.indices
		var positions:Array[Vector3]=entry.positions
		var rotations:Array[Quaternion]=entry.rotations
		var scales:Array[Vector3]=entry.scales
		var written:PackedByteArray=entry.written
		var output:Array[Transform3D]=entry.output
		for bone:int in entry.dynamic:
			if not written[bone]:continue
			# These setters restore exact tick components; Skeleton's dirty flag
			# coalesces them into its normal single deferred skin update.
			rig.set_bone_pose_position(indices[bone],positions[bone])
			rig.set_bone_pose_rotation(indices[bone],rotations[bone])
			rig.set_bone_pose_scale(indices[bone],scales[bone])
			output[bone]=current[bone]
			written[bone]=0
		entry.written=written
	for i:int in _node_dynamic:
		if _node_written[i]:
			_nodes[i].transform=_node_current[i]
			_node_output[i]=_node_current[i]
			_node_written[i]=0
	for material:Dictionary in _materials:
		var current:Dictionary=material.current
		for parameter:StringName in material.written:_uniform_setter.call(material.entry,parameter,current[parameter])
		(material.written as Dictionary).clear()
	rendered=false
	profile.restore_us=Time.get_ticks_usec()-begin

func render(owner:Node3D,fraction:float) -> bool:
	if not valid:return false
	var begin:=Time.get_ticks_usec()
	var alpha:=clampf(fraction,0.0,1.0)
	if _interpolate_root:owner.global_transform=_previous_root.interpolate_with(_current_root,alpha)
	var writes:=0
	for entry:Dictionary in _rigs:
		if not (entry.visibility as Node3D).is_visible_in_tree():continue
		var rig:Skeleton3D=entry.node
		var previous:Array[Transform3D]=entry.previous
		var current:Array[Transform3D]=entry.current
		var indices:PackedInt32Array=entry.indices
		var output:Array[Transform3D]=entry.output
		var written:PackedByteArray=entry.written
		for bone:int in entry.dynamic:
			var pose:Transform3D=previous[bone].interpolate_with(current[bone],alpha)
			if output[bone]==pose:continue
			# One native call writes the local pose. Skeleton deformation is uploaded
			# by its normal deferred update, not three separate component setters.
			rig.set_bone_pose(indices[bone],pose)
			output[bone]=pose
			written[bone]=1
			writes+=1
		entry.written=written
	var node_writes:=0
	for i:int in _node_dynamic:
		if not _nodes[i].is_visible_in_tree():continue
		var output:Transform3D=_node_previous[i].interpolate_with(_node_current[i],alpha)
		if _node_output[i]==output:continue
		_nodes[i].transform=output
		_node_output[i]=output
		_node_written[i]=1
		node_writes+=1
	for material:Dictionary in _materials:
		var previous:Dictionary=material.previous
		var current:Dictionary=material.current
		if not ((material.entry as Dictionary).mesh as MeshInstance3D).is_visible_in_tree():continue
		for parameter:StringName in material.dynamic:
			_uniform_setter.call(material.entry,parameter,lerp(previous[parameter],current[parameter],alpha))
			(material.written as Dictionary)[parameter]=true
	rendered=true
	render_samples+=1
	profile.render_us=Time.get_ticks_usec()-begin
	profile.bone_writes=writes
	if not _interpolate_root:
		profile.swing_bone_writes=writes
		profile.held_bone_writes=0
	profile.node_writes=node_writes
	profile.fraction=alpha
	return true

func position_at(fraction:float) -> Vector3:
	return _previous_root.origin.lerp(_current_root.origin,clampf(fraction,0.0,1.0)) if _interpolate_root else _current_root.origin

func authoritative_root(owner:Node3D) -> Transform3D:
	var parent:=owner.get_parent_node_3d()
	return parent.global_transform*_tick_local_root if parent!=null else _tick_local_root
