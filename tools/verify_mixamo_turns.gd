extends SceneTree
## Run only through Root's serialized Godot wrapper. No production library changes.
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const Prototype = preload("res://scripts/animation/experiments/mixamo_turn_prototype.gd")
const NativeMatcher = preload("res://scripts/animation/native_motion_matcher.gd")
const MODES := ["source_yaw_pelvis9","fixed_authority_leg8"]
var checks:int = 0
var failures:int = 0
var summary:Dictionary = {}
var maximum_upper_position:float = 0.0
var maximum_upper_basis:float = 0.0
var maximum_muzzle:float = 0.0
var contact_samples:int = 0
var native_requested:bool = "--native-locomotion-mm" in OS.get_cmdline_args() or "--native-locomotion-mm" in OS.get_cmdline_user_args()
var native_evidence:Dictionary = {}

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("MIXAMO_TURNS watchdog");quit(1))
	call_deferred("_run")

func _check(label:String,passed:bool,detail:Variant=null) -> void:
	checks+=1
	if not passed:
		failures+=1
		if failures<32:push_error("MIXAMO_TURNS "+label+" "+str(detail))

func _run() -> void:
	var world:=Node3D.new()
	root.add_child(world)
	var visual_root:=Node3D.new()
	world.add_child(visual_root)
	var avatar:=Avatar.new()
	avatar.force_lod=0
	visual_root.add_child(avatar)
	avatar.presentation_interpolation=false
	avatar.set_process(false)
	await process_frame
	var prototype:=Prototype.new()
	_check("target rig configure",prototype.configure(avatar._skeleton))
	if prototype.player==null:quit(1);return
	_check("original 65 to 87 rig map",int(prototype.data.source_rig_bones)==65 and int(prototype.data.target_rig_bones)==87)
	_check("source pack SHA",String(prototype.data.archive_sha256)=="e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86")
	_check("source body bytes unchanged",FileAccess.get_sha256("res://assets/characters/body.glb")==String(prototype.data.target_body_sha256))
	_check("four original one shots",prototype.clips.size()==4)
	_check("three compensated upper boundaries",prototype.upper_boundaries.size()==3)
	for clip:Dictionary in prototype.clips.values():
		_check("source duration is original",is_equal_approx(float(clip.duration),1.6333333333 if not String(clip.id).contains("90") else .9333333333))
		var original:Animation=load("res://assets/animation/experiments/mixamo/"+String(clip.id)+".tres")
		_check("baseline imported",original!=null and original.loop_mode==Animation.LOOP_NONE)
		for mode:String in MODES:
			var variant:Dictionary=clip.variants[mode]
			var resource:Animation=load("res://assets/animation/experiments/mixamo/"+String(variant.id)+".tres")
			_check("variant imported",resource!=null and resource.loop_mode==Animation.LOOP_NONE)
			_check("original time retained",resource!=null and is_equal_approx(resource.length,float(clip.duration)))
			_check("track mask count",resource.get_track_count()==(8 if mode=="fixed_authority_leg8" else 10))
			for track:int in resource.get_track_count():
				var path:NodePath=resource.track_get_path(track)
				_check("no world root track",path.get_name_count()==1 and String(path.get_name(0))=="Skeleton3D" and path.get_subname_count()==1)
				_check("only intended lower bones",String(path.get_subname(0)) in Prototype.NAMES and (mode!="fixed_authority_leg8" or String(path.get_subname(0))!="hips"))
	# Independent cases reconfigure the source avatar first; no residual clip pose.
	for weapon:String in Avatar.WEAPONS:
		prototype.dispose()
		avatar.configure(Color("ff8a14"),weapon,{"hair":1,"outfit":2,"eyes":4,"hat":1})
		if native_requested:_check("native flag truly active "+weapon,avatar.native_locomotion_mm and avatar._motion is NativeMatcher)
		_check("rebuilt rig and weapon",prototype.configure(avatar._skeleton))
		for clip:Dictionary in prototype.clips.values():
			for mode:String in MODES:
				var samples:int=ceili(float(clip.duration)*60.0)
				var previous:Array[Quaternion]=[]
				var maximum_angle:float=0.0
				var maximum_contact:float=0.0
				var contacts:int=0
				var entry:float=0.0
				var maximum_reach:float=0.0
				var worst:Dictionary={}
				var baked_previous:Array[Quaternion]=[]
				var baked_maximum_angle:float=0.0
				var baked_maximum_contact:float=0.0
				for sample:int in samples+1:
					var time:float=minf(float(sample)/60.0,float(clip.duration))
					var meta:Dictionary=prototype.sample_metadata(String(clip.id),time,mode)
					visual_root.rotation.y=float(meta.root_yaw) if mode=="source_yaw_pelvis9" else 0.0
					avatar.animate(1.0/60.0,{"grounded":true,"form":"kid","speed":0.0,"velocity":Vector3.ZERO,"firing":true,"rolling":weapon=="roller","aim_pitch":.4,"is_local":true})
					var rig:Skeleton3D=avatar._skeleton
					var source:Array[Transform3D]=[]
					var packets:Array[Dictionary]=[]
					for bone:int in rig.get_bone_count():
						source.append(rig.get_bone_global_pose(bone))
						packets.append(_packet(rig,bone))
					var original_root:Transform3D=visual_root.global_transform
					var original_owner:Transform3D=avatar.global_transform
					var original_muzzle:Vector3=avatar.get_muzzle()
					var original_clock:Dictionary=_clocks(avatar)
					if mode=="fixed_authority_leg8":
						var bake:Dictionary=prototype.apply(String(clip.id),time,mode,true,false)
						baked_maximum_contact=maxf(baked_maximum_contact,float(bake.actual_fk_sole_error_m))
						var baked_current:Array[Quaternion]=[]
						for index:int in prototype.indices.slice(1):baked_current.append(rig.get_bone_pose_rotation(index))
						for item:int in baked_current.size():
							if not baked_previous.is_empty():baked_maximum_angle=maxf(baked_maximum_angle,_angle(baked_current[item],baked_previous[item]))
						baked_previous=baked_current
					var result:Dictionary=prototype.apply(String(clip.id),time,mode,true,true)
					_check("sample applied",not result.is_empty())
					_check("visual and world root untouched",visual_root.global_transform==original_root and avatar.global_transform==original_owner)
					_check("animation MM IK clocks untouched",_clocks(avatar)==original_clock)
					maximum_muzzle=maxf(maximum_muzzle,avatar.get_muzzle().distance_to(original_muzzle))
					_check("weapon world muzzle held",avatar.get_muzzle().distance_to(original_muzzle)<.000002)
					var start:int=1 if mode=="fixed_authority_leg8" else 0
					for bone:int in rig.get_bone_count():
						if bone in prototype.indices.slice(start):continue
						var actual:Transform3D=rig.get_bone_global_pose(bone)
						var error:float=actual.origin.distance_to(source[bone].origin)
						var basis_error:float=maxf(actual.basis.x.distance_to(source[bone].basis.x),maxf(actual.basis.y.distance_to(source[bone].basis.y),actual.basis.z.distance_to(source[bone].basis.z)))
						maximum_upper_position=maxf(maximum_upper_position,error)
						maximum_upper_basis=maxf(maximum_upper_basis,basis_error)
						_check("upper GLOBAL pose held",error<.000002 and basis_error<.000002,{"bone":rig.get_bone_name(bone),"error":error,"basis":basis_error})
						if mode=="fixed_authority_leg8":_check("eight mode upper LOCAL packet exact",_packet(rig,bone)==packets[bone])
					var current:Array[Quaternion]=[]
					for bone:int in prototype.indices.slice(start):
						var q:Quaternion=rig.get_bone_pose_rotation(bone)
						current.append(q)
						_check("finite and target offsets retained",q.is_finite() and rig.get_bone_pose_scale(bone)==Vector3.ONE)
						if bone!=prototype.indices[0]:_check("target segment offset unchanged",rig.get_bone_pose_position(bone)==rig.get_bone_rest(bone).origin)
						var source_q:Quaternion=packets[bone].rotation
						if sample==0:entry=maxf(entry,_angle(q,source_q))
					for item:int in current.size():
						if not previous.is_empty():
							var angle:float=_angle(current[item],previous[item])
							if angle>maximum_angle:
								maximum_angle=angle
								worst={"time":time,"sample":sample,"bone":rig.get_bone_name(prototype.indices[start+item]),"angle":angle,"weights":meta.weights,"hips":_packet(rig,prototype.indices[0]),"previous_q":previous[item],"current_q":current[item]}
					previous=current
					maximum_reach=maxf(maximum_reach,float(result.reach_clamp_m))
					for side:int in 2:
						if float(meta.weights[side])<.999:continue
						var foot:int=rig.find_bone("footL" if side==0 else "footR")
						var actual:Vector3=rig.global_transform*(rig.get_bone_global_pose(foot)*Prototype.SOLE_POINTS[int(meta.points[side])])
						# Expected anchor uses the original, unturned preview-root frame.
						# This measures rendered FK, including root/hips and current rig.
						var local_anchor:Vector3=meta.anchors[side]
						if mode=="source_yaw_pelvis9":local_anchor=Basis(Vector3.UP,-float(meta.root_yaw))*local_anchor
						var expected:Vector3=rig.global_transform*local_anchor
						maximum_contact=maxf(maximum_contact,actual.distance_to(expected))
						contacts+=1
						contact_samples+=1
					# Source Tree/inertia/FootPlant must read only their own prior tick.
					# Retargeting is a presentation experiment; restore all original raw
					# components before the next source animate, including compensated
					# spine/hem translations that the source does not key each frame.
					for bone:int in rig.get_bone_count():
						rig.set_bone_pose_position(bone,packets[bone].position)
						rig.set_bone_pose_rotation(bone,packets[bone].rotation)
						rig.set_bone_pose_scale(bone,packets[bone].scale)
						_check("source input raw restore exact",_packet(rig,bone)==packets[bone])
				var label:String=weapon+"/"+String(clip.id)+"/"+mode
				summary[label]={"original_duration_s":clip.duration,"actual_source_turn_rad":clip.actual_turn_radians,"samples60hz":samples+1,"actual_fk_contacts":contacts,"actual_fk_contact_error_m":maximum_contact,"maximum_60hz_local_step_rad":maximum_angle,"entry_from_source_hold_step_rad":entry,"maximum_reach_clamp_m":maximum_reach,"upper_pose_policy":"global boundary compensation" if mode=="source_yaw_pelvis9" else "local+global untouched","worst":worst,"bake_without_runtime_refine_max_step_rad":baked_maximum_angle,"bake_without_runtime_refine_contact_error_m":baked_maximum_contact}
				_check("full-weight contact evidence "+label,contacts>=2,contacts)
				_check("strict 3cm actual FK contact "+label,maximum_contact<.03,maximum_contact)
				_check("strict 20degree per60Hz continuity "+label,maximum_angle<.35,maximum_angle)
				await process_frame
		var provider:Dictionary=avatar._motion.debug_state()
		native_evidence[weapon]={"native_requested":native_requested,"provider":provider.get("provider","portable source pose matcher"),"query_count":int(provider.get("native_queries",0)),"pose_bucket":int(provider.get("native_bucket_poses",0)),"native_error":provider.get("native_error","")}
		if native_requested:_check("real native queries and234 pose bucket "+weapon,int(provider.get("native_queries",0))>0 and int(provider.get("native_bucket_poses",0))==234 and String(provider.get("native_error","")).is_empty(),provider)
	var report:Dictionary={"cases":summary,"native_requested":native_requested,"native_providers":native_evidence,"upper_global_position_m":maximum_upper_position,"upper_global_basis_error":maximum_upper_basis,"world_muzzle_error_m":maximum_muzzle,"actual_fk_contacts":contact_samples,"checks":checks,"failures":failures,"accepted_for_production":false,"limits":"standing turns at original duration; inferred proxy contacts; source-hold entry measured, no authored running pivot/stop/start"}
	var file:=FileAccess.open("res://shots/mixamo-turn-contract.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MIXAMO_TURNS_RESULT ",JSON.stringify(report))
	prototype.dispose()
	world.queue_free()
	await process_frame
	print("MIXAMO_TURNS ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func _packet(rig:Skeleton3D,bone:int) -> Dictionary:
	return {"position":rig.get_bone_pose_position(bone),"rotation":rig.get_bone_pose_rotation(bone),"scale":rig.get_bone_pose_scale(bone)}

func _clocks(avatar:InkAvatar) -> Dictionary:
	return {"time":avatar._time,"match_time":avatar._motion.sample_time,"match_query":avatar._motion.query_count,"inertia":avatar._inertializer._age,"hit":avatar._hit.stagger_time,"contacts":avatar._foot_plant._contact.duplicate(),"weights":avatar._foot_plant._weight.duplicate()}

func _angle(a:Quaternion,b:Quaternion) -> float:
	return InkInertializer._log_rotation(a*b.inverse()).length()
