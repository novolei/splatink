extends SceneTree
## Isolated full authored timelines. Baseline quality failures are reported, not hidden.
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Prototype = preload("res://scripts/animation/experiments/motorica_locomotion_prototype.gd")
const NativeMatcher = preload("res://scripts/animation/native_motion_matcher.gd")
var checks:int=0
var structural_failures:int=0
var quality_failures:int=0
var cases:Dictionary={}
var upper_position:float=0.0
var upper_basis:float=0.0
var muzzle_error:float=0.0
var contacts:int=0
var native_requested:bool="--native-locomotion-mm" in OS.get_cmdline_args() or "--native-locomotion-mm" in OS.get_cmdline_user_args()
var weapon:String="shooter"

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("MOTORICA watchdog");quit(1))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--motorica-family="):weapon=arg.trim_prefix("--motorica-family=")
	call_deferred("_run")

func _check(label:String,passed:bool,detail:Variant=null) -> void:
	checks+=1
	if not passed:
		structural_failures+=1
		if structural_failures<20:push_error("MOTORICA_STRUCTURE "+label+" "+str(detail))

func _quality(label:String,passed:bool,value:float) -> void:
	checks+=1
	if not passed:
		quality_failures+=1
		# These are honest measurements of an uncorrected experiment, not parser errors.
		print("MOTORICA_QUALITY_FAIL ",label," value=",value)

func _run() -> void:
	_check("known source weapon family",weapon in Avatar.WEAPONS,weapon)
	if not weapon in Avatar.WEAPONS:quit(1);return
	var world:=Node3D.new()
	root.add_child(world)
	var path_root:=Node3D.new()
	world.add_child(path_root)
	var avatar:=Avatar.new()
	avatar.force_lod=0
	path_root.add_child(avatar)
	avatar.presentation_interpolation=false
	avatar.set_process(false)
	await process_frame
	avatar.configure(Color("ff8a14"),weapon,{"hair":1,"outfit":2,"eyes":4,"hat":1})
	var prototype:=Prototype.new()
	_check("71 to 87 rig configured",prototype.configure(avatar._skeleton))
	if prototype.player==null:world.queue_free();quit(1);return
	_check("original rig counts",int(prototype.data.source_rig_bones)==71 and int(prototype.data.target_rig_bones)==87)
	_check("body geometry bytes preserved",FileAccess.get_sha256("res://assets/characters/body.glb")==String(prototype.data.target_body_sha256))
	_check("three complete original clips",prototype.clips.size()==3)
	_check("three independent upper boundaries",prototype.upper_boundaries.size()==3)
	if native_requested:_check("native provider instantiated",avatar.native_locomotion_mm and avatar._motion is NativeMatcher)
	for clip:Dictionary in prototype.clips.values():
		_check("original sample extent",is_equal_approx(float(clip.duration),float(int(clip.sample_count)-1)/30.0))
		for mode:String in Prototype.MODES:
			var variant:Dictionary=clip.variants[mode]
			var animation:Animation=load(Prototype.DIRECTORY+String(variant.id)+".tres") as Animation
			_check("resource imported nonloop",animation!=null and animation.loop_mode==Animation.LOOP_NONE)
			if animation==null:continue
			_check("authored time retained",is_equal_approx(animation.length,float(clip.duration)))
			_check("exact lower mask",animation.get_track_count()==(8 if mode=="fixed_authority_leg8" else 10))
			for track:int in animation.get_track_count():
				var path:NodePath=animation.track_get_path(track)
				_check("no owner/world root track",path.get_name_count()==1 and String(path.get_name(0))=="Skeleton3D" and path.get_subname_count()==1)
				_check("only intended lower joints",String(path.get_subname(0)) in Prototype.NAMES and (mode!="fixed_authority_leg8" or String(path.get_subname(0))!="hips"))
			var previous:Array[Quaternion]=[]
			var max_angle:float=0.0
			var max_contact:float=0.0
			var max_entry:float=0.0
			var max_hip_step:float=0.0
			var old_hip:=Vector3.ZERO
			var contact_count:int=0
			var worst:Dictionary={}
			var samples:int=ceili(float(clip.duration)*60.0)
			for sample:int in samples+1:
				var time:float=minf(float(sample)/60.0,float(clip.duration))
				var meta:Dictionary=prototype.sample_metadata(String(clip.id),time,mode)
				# The author path is only this experiment's visual owner. No Actor exists.
				path_root.transform=meta.root_transform
				avatar.animate(1.0/60.0,{"grounded":true,"form":"kid","speed":0.0,"velocity":Vector3.ZERO,"firing":true,"rolling":weapon=="roller","aim_pitch":.4,"is_local":true})
				var rig:Skeleton3D=avatar._skeleton
				var packets:Array[Dictionary]=prototype.capture_authority()
				var source:Array[Transform3D]=[]
				for bone:int in rig.get_bone_count():source.append(rig.get_bone_global_pose(bone))
				var owner:Transform3D=avatar.global_transform
				var path_owner:Transform3D=path_root.global_transform
				var muzzle:Vector3=avatar.get_muzzle()
				var clocks:Dictionary=_clocks(avatar)
				var result:Dictionary=prototype.apply(String(clip.id),time,mode,true)
				_check("sample applied",not result.is_empty())
				_check("owner remains authoritative",avatar.global_transform==owner and path_root.global_transform==path_owner)
				_check("MM IK hit clocks unchanged",_clocks(avatar)==clocks)
				var actual_muzzle:float=avatar.get_muzzle().distance_to(muzzle)
				muzzle_error=maxf(muzzle_error,actual_muzzle)
				_check("upper weapon muzzle unchanged",actual_muzzle<.000002)
				var start:int=1 if mode=="fixed_authority_leg8" else 0
				var affected:PackedInt32Array=prototype.indices.slice(start)
				for bone:int in rig.get_bone_count():
					if bone in affected:continue
					var actual:Transform3D=rig.get_bone_global_pose(bone)
					var p_error:float=actual.origin.distance_to(source[bone].origin)
					var b_error:float=maxf(actual.basis.x.distance_to(source[bone].basis.x),maxf(actual.basis.y.distance_to(source[bone].basis.y),actual.basis.z.distance_to(source[bone].basis.z)))
					upper_position=maxf(upper_position,p_error)
					upper_basis=maxf(upper_basis,b_error)
					_check("upper global pose held",p_error<.000002 and b_error<.000002,{"bone":rig.get_bone_name(bone),"position":p_error,"basis":b_error})
					if start==1:_check("fixed mode upper raw packet exact",_packet(rig,bone)==packets[bone])
				var current:Array[Quaternion]=[]
				for bone:int in affected:
					var q:Quaternion=rig.get_bone_pose_rotation(bone)
					current.append(q)
					_check("finite unit lower scale",q.is_finite() and rig.get_bone_pose_scale(bone)==Vector3.ONE)
					if bone!=prototype.indices[0]:_check("target segment offset retained",rig.get_bone_pose_position(bone)==rig.get_bone_rest(bone).origin)
					if sample==0:max_entry=maxf(max_entry,_angle(q,packets[bone].rotation))
				for item:int in current.size():
					if previous.is_empty():continue
					var angle:float=_angle(current[item],previous[item])
					if angle>max_angle:
						max_angle=angle
						worst={"time":time,"sample":sample,"bone":rig.get_bone_name(affected[item]),"previous_q":previous[item],"current_q":current[item],"angle_rad":angle}
				previous=current
				var hip:Vector3=rig.get_bone_pose_position(prototype.indices[0])
				if sample>0:max_hip_step=maxf(max_hip_step,hip.distance_to(old_hip))
				old_hip=hip
				for side:int in 2:
					if not bool(meta.candidates[side]):continue
					var foot:int=rig.find_bone("footL" if side==0 else "footR")
					var actual:Vector3=rig.global_transform*(rig.get_bone_global_pose(foot)*Prototype.SOLE_POINTS[int(meta.points[side])])
					# Root-path FK and the original span anchor share the world frame.
					var reference:Transform3D=path_root.global_transform*(meta.root_transform as Transform3D).affine_inverse()
					var expected:Vector3=reference*(meta.anchors[side] as Vector3)
					max_contact=maxf(max_contact,actual.distance_to(expected))
					contact_count+=1
					contacts+=1
				# Critical: the next source tick sees its own pose, never the prototype.
				prototype.restore_authority(packets)
				for bone:int in rig.get_bone_count():_check("87 raw packets restored exactly",_packet(rig,bone)==packets[bone])
			var label:String=weapon+"/"+String(clip.id)+"/"+mode
			cases[label]={"original_duration_s":clip.duration,"samples60hz":samples+1,"inferred_contacts":contact_count,"maximum_rendered_fk_proxy_slide_m":max_contact,"maximum_60hz_local_step_rad":max_angle,"entry_from_source_hold_rad":max_entry,"maximum_hip_local_step_m":max_hip_step,"worst":worst,"contact_correction_applied":false,"full_clip_nonloop":true}
			_check("actual contact observations "+label,contact_count>0,contact_count)
			_quality("strict 3cm FK contact "+label,max_contact<.03,max_contact)
			_quality("strict .35rad per60Hz continuity "+label,max_angle<.35,max_angle)
			await process_frame
	var provider:Dictionary=avatar._motion.debug_state()
	var evidence:Dictionary={"native_requested":native_requested,"provider":provider.get("provider","portable source pose matcher"),"query_count":int(provider.get("native_queries",0)),"pose_bucket":int(provider.get("native_bucket_poses",0)),"native_error":provider.get("native_error","")}
	if native_requested:_check("native actually queried original 234pose bucket",int(evidence.query_count)>0 and int(evidence.pose_bucket)==234 and String(evidence.native_error).is_empty(),evidence)
	var report:Dictionary={"weapon":weapon,"cases":cases,"native_evidence":evidence,"checks":checks,"structural_failures":structural_failures,"quality_failures":quality_failures,"accepted_for_production":false,"upper_global_position_m":upper_position,"upper_global_basis_error":upper_basis,"muzzle_error_m":muzzle_error,"inferred_contact_samples":contacts,"policy":"Complete source-time baseline; inferred contacts only; no IK correction or physics/controller integration; source-hold entry measured, not blended."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var file:=FileAccess.open("res://shots/motorica-contract-"+weapon+("-native" if native_requested else "-portable")+".json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MOTORICA_RESULT ",JSON.stringify(report))
	prototype.dispose()
	world.queue_free()
	await process_frame
	print("MOTORICA ",checks," checks; structural=",structural_failures," quality=",quality_failures)
	quit(1 if structural_failures+quality_failures else 0)

func _packet(rig:Skeleton3D,bone:int) -> Dictionary:
	return {"position":rig.get_bone_pose_position(bone),"rotation":rig.get_bone_pose_rotation(bone),"scale":rig.get_bone_pose_scale(bone)}

func _clocks(avatar:InkAvatar) -> Dictionary:
	return {"time":avatar._time,"match_time":avatar._motion.sample_time,"match_query":avatar._motion.query_count,"inertia":avatar._inertializer._age,"hit":avatar._hit.stagger_time,"contacts":avatar._foot_plant._contact.duplicate(),"weights":avatar._foot_plant._weight.duplicate()}

func _angle(a:Quaternion,b:Quaternion) -> float:
	return InkInertializer._log_rotation(a*b.inverse()).length()
