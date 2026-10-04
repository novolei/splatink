extends Node
## Independent imported AnimationPlayer + original 87-joint FK diagnostic.
## No controller/root movement or new MM database is simulated. World contact
## diagnostics add the declared linear 6 m/s translation only in measurements.
const BODY_SHA:="ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3"
const ZIP_SHA:="e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86"
var checks:int=0
var failures:Array[String]=[]
var quality_failures:Array[String]=[]
var cases:Array[Dictionary]=[]
var output:String="res://shots/mixamo-loop-refined-contract.json"
var family:String="shooter"
var avatar:Node3D
var prototype:RefCounted
var rig:Skeleton3D
var world:Node3D
var maximum_upper_position:float=0.0
var maximum_upper_basis:float=0.0
var maximum_muzzle:float=0.0
var maximum_json_fk_error:float=0.0

func _ready()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--loop-output="):output=arg.trim_prefix("--loop-output=")
		if arg.begins_with("--loop-family="):family=arg.trim_prefix("--loop-family=")
	get_tree().create_timer(150.0).timeout.connect(func():push_error("MIXAMO_REFINED_LOOPS watchdog");get_tree().quit(1))
	_run.call_deferred()

func _check(label:String,passed:bool)->void:
	checks+=1
	if not passed:
		failures.append(label)
		if failures.size()<16:push_error("MIXAMO_REFINED_LOOPS "+label)

func _run()->void:
	var avatar_script:Script=load("res://scripts/characters/ink_avatar.gd") as Script
	var sampler_script:Script=load("res://scripts/animation/experiments/mixamo_loop_refined_prototype.gd") as Script
	world=Node3D.new()
	add_child(world)
	avatar=avatar_script.new()
	avatar.set("force_lod",0)
	world.add_child(avatar)
	avatar.set("presentation_interpolation",false)
	avatar.set_process(false)
	await get_tree().process_frame
	_check("known original family",family in avatar_script.get_script_constant_map().get("WEAPONS",[]))
	if not failures.is_empty():_finish();return
	avatar.call("configure",Color("ff8a14"),family,{"hair":1,"outfit":2,"eyes":4,"hat":1})
	rig=avatar.get("_skeleton")
	prototype=sampler_script.new()
	_check("imported rig and resources configured",bool(prototype.call("configure",rig)))
	if not failures.is_empty():_finish();return
	var data:Dictionary=prototype.get("data")
	var clips:Dictionary=prototype.get("clips")
	_check("original body bytes",FileAccess.get_sha256("res://assets/characters/body.glb")==BODY_SHA and String(data.target_body_sha256)==BODY_SHA)
	_check("original ZIP provenance",String(data.archive_sha256)==ZIP_SHA)
	_check("21 explicitly declared variants",clips.size()==21)
	_check("experimental and never accepted",bool(data.experimental) and not bool(data.default_enabled) and not bool(data.production_accepted))
	_check("original 87 joints",rig.get_bone_count()==87 and int(data.original_target_rig_joints)==87)
	_check("three upper boundaries",(prototype.get("upper_boundaries") as PackedInt32Array).size()==3)
	# glTF skin-joint slots are not Godot Skeleton3D indices. The importer orders
	# bones by hierarchy. Check the declared slots against the original GLB, then
	# independently check imported names/parents rather than equating the orders.
	var glb:FileAccess=FileAccess.open("res://assets/characters/body.glb",FileAccess.READ)
	glb.seek(12)
	var json_bytes:int=glb.get_32()
	_check("original GLB JSON chunk",glb.get_32()==0x4e4f534a)
	var gltf:Dictionary=JSON.parse_string(glb.get_buffer(json_bytes).get_string_from_utf8())
	glb.close()
	var slots:Array=gltf.skins[0].joints
	for name:String in data.names:
		var slot:int=int(data.target_indices[name])
		_check("original GLB skin slot "+name,String(gltf.nodes[int(slots[slot])].name)==name)
		var bone:int=rig.find_bone(name)
		var parent:int=rig.get_bone_parent(bone)
		_check("imported hierarchy "+name,parent==-1 if name=="hips" else parent>=0 and rig.get_bone_name(parent)==String(data.target_parents[name]))
	var contact_regression:Dictionary=prototype.call("metadata","mixamo_loop_refined_running_raw_dense",.053820645483)
	_check("wrap contact regression retains right stance",bool(contact_regression.contact_candidate[1]))
	var native_requested:bool="--native-locomotion-mm" in OS.get_cmdline_user_args()
	_check("provider flag honored",bool(avatar.get("_native_motion_active"))==native_requested)
	for clip:Dictionary in clips.values():
		var animation:Animation=load("res://assets/animation/experiments/mixamo_loops_refined/"+String(clip.id)+".tres") as Animation
		_check("resource present "+String(clip.id),animation!=null)
		if animation==null:continue
		_check("resource loops",animation.loop_mode==Animation.LOOP_LINEAR and bool(clip.loop))
		_check("actual retimed duration",absf(animation.length-float(clip.duration))<.000001)
		_check("time has physical rate",absf(float(clip.duration)*float(clip.playback_rate_from_original)-float(clip.source_duration))<.000000001)
		_check("no trajectory or upper tracks declared",(clip.root_tracks as Array).is_empty() and (clip.upper_tracks as Array).is_empty() and bool(clip.source_trajectory_is_metadata_only) and bool(clip.world_foot_lock_applied)==(String(clip.contact_policy)!="none"))
		_check("resource mask count",animation.get_track_count()==(10 if bool(clip.writes_hips) else 8))
		for track:int in animation.get_track_count():
			var path:NodePath=animation.track_get_path(track)
			_check("only skeleton tracks",path.get_name_count()==1 and String(path.get_name(0))=="Skeleton3D" and path.get_subname_count()==1)
			var bone:String=String(path.get_subname(0))
			_check("no hips in fixed8",bone in data.names and (bool(clip.writes_hips) or bone!="hips"))
			_check("only lower rotation or pelvis position",animation.track_get_type(track)==Animation.TYPE_ROTATION_3D or (bool(clip.writes_hips) and bone=="hips" and animation.track_get_type(track)==Animation.TYPE_POSITION_3D))
			_check("all source sample keys",animation.track_get_key_count(track)==(clip.frames as Array).size())
			_check("loop interpolation enabled",animation.track_get_interpolation_loop_wrap(track))
		for context:String in ["rest_hips","production_aim_hold"]:
			for rate:int in [60,30,144]:_sample_case(clip,context,rate)
	if native_requested:
		var state:Dictionary=avatar.get("motion_state")
		_check("actual original native queries occurred",int(state.get("native_queries",0))>0 and int(state.get("native_bucket_poses",0))==234)
	_finish()

func _sample_case(clip:Dictionary,context:String,rate:int)->void:
	var count:int=ceili(float(clip.duration)*float(rate)*3.0)
	var previous:Array[Quaternion]=[]
	var max_step:float=0.0
	var max_entry:float=0.0
	var max_hip_delta:float=0.0
	var ids:PackedInt32Array=prototype.get("indices")
	var direction:Vector3=Vector3.ZERO
	for evidence:Dictionary in (prototype.get("data") as Dictionary).source_evidence:
		if String(evidence.file)==String(clip.source_file):direction=_vec(evidence.source_net_hips_planar_delta_m).normalized()
	_check("actual source movement direction",direction.is_finite() and absf(direction.length()-1.0)<.00001)
	var contact_groups:Dictionary={}
	var contact_count:int=0
	var maximum_contact_span:float=0.0
	var maximum_contact_anchor_error:float=0.0
	var maximum_segment_length_error:float=0.0
	var minimum_inferred_contact_proxy_y:float=999.0
	for index:int in count+1:
		var time:float=float(index)/float(rate)
		# This is an authority-pose context, not a controller or movement test.
		if context=="rest_hips":rig.reset_bone_poses()
		else:avatar.call("animate",1.0/float(rate),{"grounded":true,"form":"kid","speed":6.0,"velocity":Vector3(0,0,6),"desired_velocity":Vector3(0,0,6),"firing":true,"aim_pitch":.4,"is_local":true})
		var authority:Array[Dictionary]=_capture(rig)
		var globals:Array[Transform3D]=[]
		for bone:int in rig.get_bone_count():globals.append(rig.get_bone_global_pose(bone))
		var module_before:Array=[]
		for module:Skeleton3D in avatar.get("_modules"):module_before.append(_capture(module))
		var owner:Transform3D=avatar.global_transform
		var muzzle:Vector3=avatar.call("get_muzzle")
		var motion:Dictionary=avatar.get("motion_state")
		var clock:float=float(avatar.get("_time"))
		var meta:Dictionary=prototype.call("apply",String(clip.id),time,true)
		_check("real manual player sampled",not meta.is_empty())
		if not meta.is_empty():
			var reference:Array[bool]=_source_contact_reference(clip,time)
			_check("discrete contact matches original nearest FBX key",bool(meta.contact_candidate[0])==reference[0] and bool(meta.contact_candidate[1])==reference[1])
		if meta.is_empty():return
		_check("owner transform held",avatar.global_transform==owner)
		_check("matching and animation clocks held",avatar.get("motion_state")==motion and float(avatar.get("_time"))==clock)
		var upper_error:float=0.0
		var basis_error:float=0.0
		for bone:int in rig.get_bone_count():
			if bone in ids:continue
			var actual:Transform3D=rig.get_bone_global_pose(bone)
			upper_error=maxf(upper_error,actual.origin.distance_to(globals[bone].origin))
			basis_error=maxf(basis_error,_basis_error(actual.basis,globals[bone].basis))
		maximum_upper_position=maxf(maximum_upper_position,upper_error)
		maximum_upper_basis=maxf(maximum_upper_basis,basis_error)
		_check("upper global pose retained",upper_error<.00001 and basis_error<.00001)
		var actual_muzzle:Vector3=avatar.call("get_muzzle")
		maximum_muzzle=maxf(maximum_muzzle,actual_muzzle.distance_to(muzzle))
		_check("actual weapon muzzle retained",actual_muzzle.distance_to(muzzle)<.00001)
		if not bool(clip.writes_hips):
			_check("original hips local retained",_packet_equal(_packet(rig,ids[0]),authority[ids[0]]))
		max_hip_delta=maxf(max_hip_delta,rig.get_bone_pose_position(ids[0]).distance_to(authority[ids[0]].position))
		var expected:Dictionary=_expected_world(clip,meta,authority)
		var json_error:float=0.0
		for item:int in ids.size():
			var bone:int=ids[item]
			var actual:Transform3D=rig.get_bone_global_pose(bone)
			var names:Array=(prototype.get("data") as Dictionary).names
			var ref:Transform3D=expected[String(names[item])]
			json_error=maxf(json_error,actual.origin.distance_to(ref.origin))
			_check("imported FK matches source keys",actual.origin.distance_to(ref.origin)<.00002 and _basis_error(actual.basis,ref.basis)<.00002)
			_check("finite imported pose",actual.origin.is_finite() and actual.basis.x.is_finite() and actual.basis.y.is_finite() and actual.basis.z.is_finite())
		maximum_json_fk_error=maxf(maximum_json_fk_error,json_error)
		var current:Array[Quaternion]=[]
		for bone:int in ids:current.append(rig.get_bone_pose_rotation(bone))
		for item:int in current.size():
			if previous.is_empty():max_entry=maxf(max_entry,_angle(current[item],authority[ids[item]].rotation))
			else:max_step=maxf(max_step,_angle(current[item],previous[item]))
		previous=current
		for side:String in ["L","R"]:
			for pair:Array in [["thigh","shin"],["shin","foot"],["foot","toe"]]:
				var parent:int=rig.find_bone(String(pair[0])+side)
				var child:int=rig.find_bone(String(pair[1])+side)
				var length_error:float=absf(rig.get_bone_global_pose(parent).origin.distance_to(rig.get_bone_global_pose(child).origin)-rig.get_bone_rest(child).origin.length())
				maximum_segment_length_error=maxf(maximum_segment_length_error,length_error)
				_check("original fixed bone length retained",length_error<.00001)
		var duration:float=float(clip.duration)
		var phase:float=fposmod(time,duration)
		var cycle:int=floori(time/duration)
		for window:Dictionary in clip.windows:
			for relative_cycle:int in [-1,0,1]:
				if phase<float(window.start_s)+float(relative_cycle)*duration or phase>=float(window.end_s)+float(relative_cycle)*duration:continue
				var side_index:int=int(window.leg)
				var side:String="L" if side_index==0 else "R"
				var local_sole:Vector3=Vector3(0,-.085,-.065) if int(window.sole_point)==0 else Vector3(0,-.085,.11)
				var foot_pose:Transform3D=rig.get_bone_global_pose(rig.find_bone("foot"+side))
				var sole:Vector3=foot_pose*local_sole+direction*6.0*time
				for point:Vector3 in [Vector3(0,-.085,-.065),Vector3(0,-.085,.11)]:minimum_inferred_contact_proxy_y=minf(minimum_inferred_contact_proxy_y,(foot_pose*point).y)
				var absolute_cycle:int=cycle+relative_cycle
				var key:String=str(window.window_id)+":"+str(absolute_cycle)
				if not contact_groups.has(key):contact_groups[key]=sole
				var anchor:Vector3=_vec(window.anchor_world_at_start_m)+direction*6.0*duration*float(absolute_cycle)
				maximum_contact_span=maxf(maximum_contact_span,sole.distance_to(contact_groups[key]))
				maximum_contact_anchor_error=maxf(maximum_contact_anchor_error,sole.distance_to(anchor))
				contact_count+=1
		prototype.call("copy_modules",avatar,bool(clip.writes_hips))
		_check_modules(module_before,bool(clip.writes_hips))
		# Restore all body/module authority before the next original MM query.
		_restore(rig,authority)
		var modules:Array=avatar.get("_modules")
		for item:int in modules.size():_restore(modules[item],module_before[item])
	var limit:float=.35*(60.0/float(rate))
	var label:String=String(clip.id)+" / "+context+" / "+str(rate)
	if rate in [60,30] and max_step>limit:quality_failures.append(label+" loop step exceeds "+str(limit))
	if maximum_contact_span>.03 or contact_count==0:quality_failures.append(label+" inferred-contact sole span exceeds .03 m or no evidence")
	if minimum_inferred_contact_proxy_y<-.01:quality_failures.append(label+" heel/ball proxy penetrates flat ground beyond diagnostic .01 m")
	cases.append({"id":clip.id,"context":context,"sample_hz":rate,"cycles":3,"sample_count":count+1,"maximum_local_lower9_step_rad":max_step,"diagnostic_step_limit_rad":limit if rate in [60,30] else null,"maximum_unblended_entry_rad":max_entry,"maximum_hips_position_change_m":max_hip_delta,"inferred_contact_samples":contact_count,"maximum_inferred_contact_sole_span_m":maximum_contact_span,"maximum_inferred_contact_sole_anchor_error_m":maximum_contact_anchor_error,"maximum_fixed_segment_length_error_m":maximum_segment_length_error,"minimum_inferred_contact_heel_ball_y_m":minimum_inferred_contact_proxy_y,"flat_ground_proxy_penetration_diagnostic_limit_m":.01,"contact_world_translation_is_measurement_only":true,"production_accepted":false})

func _check_modules(before:Array,writes_hips:bool)->void:
	var changed:PackedInt32Array=prototype.get("indices")
	if not writes_hips:changed=changed.slice(1)
	else:changed=changed.duplicate();changed.append_array(prototype.get("upper_boundaries"))
	var modules:Array=avatar.get("_modules")
	var maps:Array=avatar.get("_pose_maps")
	var offsets:Array=avatar.get("_module_rest_offsets")
	for item:int in modules.size():
		var module:Skeleton3D=modules[item]
		var mapping:PackedInt32Array=maps[item]
		for bone:int in module.get_bone_count():
			var source:int=mapping[bone]
			if source in changed:
				_check("garment changed joint follows body",module.get_bone_pose_position(bone).distance_to(rig.get_bone_pose_position(source)+offsets[item][bone])<.000001 and _angle(module.get_bone_pose_rotation(bone),rig.get_bone_pose_rotation(source))<.00001)
			else:_check("unaffected garment local pose held",_packet_equal(_packet(module,bone),before[item][bone]))

func _expected_world(clip:Dictionary,meta:Dictionary,authority:Array[Dictionary])->Dictionary:
	var frames:Array=clip.frames
	var a:Dictionary=frames[int(meta.frame)]
	var b:Dictionary=frames[int(meta.next_frame)]
	var amount:float=float(meta.fraction)
	var result:Dictionary={}
	var names:Array=(prototype.get("data") as Dictionary).names
	var parents:Dictionary=(prototype.get("data") as Dictionary).target_parents
	var ids:PackedInt32Array=prototype.get("indices")
	for item:int in names.size():
		var position:Vector3=_vec(a.lower[item].position).lerp(_vec(b.lower[item].position),amount)
		var q:Quaternion=_quat(a.lower[item].rotation).slerp(_quat(b.lower[item].rotation),amount).normalized()
		if item==0 and not bool(clip.writes_hips):position=authority[ids[0]].position;q=authority[ids[0]].rotation
		var pose:=Transform3D(Basis(q),position)
		var parent:String=String(parents[names[item]])
		result[names[item]]=(result[parent] as Transform3D)*pose if result.has(parent) else pose
	return result

func _source_contact_reference(clip:Dictionary,time:float)->Array[bool]:
	var flags:Array[bool]=[false,false]
	var intervals:int=roundi(float(clip.source_duration)*30.0)
	var phase:float=fposmod(time,float(clip.duration))
	var original_key:int=floori(phase/float(clip.duration)*float(intervals)+.5)%intervals
	for evidence:Dictionary in (prototype.get("data") as Dictionary).source_evidence:
		if String(evidence.file)!=String(clip.source_file):continue
		for leg:int in 2:
			for source_index:Variant in evidence.source_contact_evidence[leg].candidate_indices:
				if original_key==int(source_index):flags[leg]=true
	return flags

func _packet(skeleton:Skeleton3D,bone:int)->Dictionary:
	return {"position":skeleton.get_bone_pose_position(bone),"rotation":skeleton.get_bone_pose_rotation(bone),"scale":skeleton.get_bone_pose_scale(bone)}

func _capture(skeleton:Skeleton3D)->Array[Dictionary]:
	var values:Array[Dictionary]=[]
	for bone:int in skeleton.get_bone_count():values.append(_packet(skeleton,bone))
	return values

func _restore(skeleton:Skeleton3D,values:Array)->void:
	for bone:int in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(bone,values[bone].position)
		skeleton.set_bone_pose_rotation(bone,values[bone].rotation)
		skeleton.set_bone_pose_scale(bone,values[bone].scale)

func _packet_equal(a:Dictionary,b:Dictionary)->bool:
	return a.position==b.position and a.rotation==b.rotation and a.scale==b.scale

func _vec(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
func _quat(value:Array)->Quaternion:return Quaternion(float(value[0]),float(value[1]),float(value[2]),float(value[3])).normalized()
func _angle(a:Quaternion,b:Quaternion)->float:
	var delta:Quaternion=a.normalized().inverse()*b.normalized()
	return 2.0*atan2(Vector3(delta.x,delta.y,delta.z).length(),absf(delta.w))
func _basis_error(a:Basis,b:Basis)->float:return maxf((a.x-b.x).length(),maxf((a.y-b.y).length(),(a.z-b.z).length()))

func _finish()->void:
	var native:Dictionary=avatar.get("motion_state") if is_instance_valid(avatar) else {}
	if prototype!=null:prototype.call("dispose")
	if is_instance_valid(world):world.queue_free()
	await get_tree().process_frame
	var report:Dictionary={"checks":checks,"structural_failures":failures,"quality_failures":quality_failures,"cases":cases,"native_original_library":native,"family":family,"diagnostic_only":true,"controller_input_test":false,"source_travel_applied":false,"production_accepted":false,"target_indices_are_gltf_skin_slots":true,"candidate_data_sha256":FileAccess.get_sha256("res://assets/animation/experiments/mixamo_loops_refined/loops.json"),"offline_report_sha256":FileAccess.get_sha256("res://.tools/mixamo-loop-refined/report.json"),"maximum_upper_global_position_error_m":maximum_upper_position,"maximum_upper_global_basis_error":maximum_upper_basis,"maximum_muzzle_error_m":maximum_muzzle,"maximum_imported_json_fk_error_m":maximum_json_fk_error}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("MIXAMO_REFINED_LOOPS report write failed");get_tree().quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MIXAMO_REFINED_LOOPS ",checks," checks; ",failures.size()," structural failures; ",quality_failures.size()," quality failures; ",cases.size()," cases; ",output)
	get_tree().quit(0 if failures.is_empty() else 1)
