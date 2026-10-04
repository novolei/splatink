extends SceneTree
## Root executes this through the serialized engine wrapper. No changes to source tolerances.
const Avatar=preload("res://scripts/characters/ink_avatar.gd")
const Matcher=preload("res://scripts/animation/native_motion_matcher.gd")
var checks:=0
var failures:=0
var native_us:Array[int]=[]
func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("NATIVE_MM watchdog");quit(1))
	call_deferred("_run")
func _check(label:String,passed:bool,detail:Variant=null)->void:
	checks+=1
	if not passed:
		failures+=1
		push_error("NATIVE_MM "+label+" "+str(detail))
func _run()->void:
	_check("native API registered",Matcher.available())
	if not Matcher.available():quit(1);return
	_api_shape_contract()
	var world:=Node3D.new()
	root.add_child(world)
	var avatar:=Avatar.new()
	avatar.native_locomotion_mm=true
	avatar.force_lod=1
	world.add_child(avatar)
	await process_frame
	_check("provider truly native",avatar._motion is Matcher)
	_check("full source skeleton retained",avatar._skeleton.get_bone_count()==87)
	_check("native provider creates no MMCharacter",_count_mm_characters(root)==0)
	var scenarios:=[{"velocity":Vector3.ZERO,"expect":"idle"},{"velocity":Vector3(0,0,5.5),"expect":"run"},{"velocity":Vector3(-4,0,0),"expect":"strafe_left"},{"velocity":Vector3(4,0,0),"expect":"strafe_right"},{"velocity":Vector3(0,0,-3),"expect":"backpedal"},{"velocity":Vector3.ZERO,"expect":"idle"}]
	for weapon:String in Avatar.WEAPONS:
		avatar.configure(Color("ff8a14"),weapon,{"hair":3,"outfit":6,"eyes":2})
		var matcher:=avatar._motion as Matcher
		_check("native 234-pose weapon bucket "+weapon,matcher._native_to_source.size()==234,matcher.debug_state())
		_database_query_contract(matcher)
		_filter_contract(avatar,weapon)
		for scenario:Dictionary in scenarios:
			for frame:int in 36:
				var v:Vector3=scenario.velocity
				var authority:Transform3D=avatar.global_transform
				var queries_before:int=matcher.native_query_count
				avatar.animate(1.0/60.0,{"speed":v.length(),"velocity":v,"desired_velocity":v,"desired_facing":Vector3.BACK,"grounded":true,"form":"kid","is_local":true})
				_check("pose never moves authoritative root "+weapon,avatar.global_transform==authority)
				if matcher.native_query_count>queries_before:native_us.append(matcher.native_query_microseconds)
			_check("native matched direction "+weapon+" "+String(scenario.expect),String(matcher.clip_name()).ends_with("_"+String(scenario.expect)),matcher.debug_state())
		_check("actual native queries "+weapon,matcher.native_query_count>5,matcher.debug_state())
		_check("native evaluates exact weapon database "+weapon,matcher.native_poses_evaluated==234,matcher.debug_state())
		_check("native clip family "+weapon,matcher.clip_name().begins_with(weapon+"_"))
		avatar.trigger("shoot")
		for frame:int in 60:
			avatar.animate(1.0/60.0,{"speed":5.5,"velocity":Vector3.BACK*5.5,"firing":true,"rolling":weapon=="roller","grounded":true})
		_check("source weapon upper aim retained "+weapon,float(avatar._tree.get("parameters/Aim/blend_amount"))>.5)
		avatar.animate(1.0/30.0,{"grounded":false,"velocity":Vector3(0,5,3),"form":"kid"})
		_check("source air layer retained "+weapon,float(avatar._tree.get("parameters/Air/blend_amount"))>.1)
		for frame:int in 9:avatar.animate(1.0/30.0,{"speed":8.0,"grounded":true,"form":"swim","velocity":Vector3.BACK*8})
		_check("source squid retained "+weapon,avatar._squid.visible)
		avatar.animate(1.0/30.0,{"grounded":true,"form":"kid"})
	_masked_inertia_contract(avatar._motion)
	native_us.sort()
	print("NATIVE_MM_PROFILE_US ",JSON.stringify({"queries":native_us.size(),"median":native_us[native_us.size()/2] if not native_us.is_empty() else -1,"p95":native_us[int(native_us.size()*.95)] if not native_us.is_empty() else -1,"max":native_us[-1] if not native_us.is_empty() else -1}))
	print("NATIVE_MM_CONTRACT ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func _api_shape_contract()->void:
	var library:=ClassDB.instantiate("MMAnimationLibrary") as AnimationLibrary
	var clip:=Animation.new()
	clip.length=1.0
	library.add_animation(&"test",clip)
	var data:=PackedFloat32Array([0.0,2.0,4.0])
	var weights:=PackedFloat32Array([3.0])
	var indices:=PackedInt32Array([0,0,0])
	var times:=PackedFloat32Array([0.0,.3,.6])
	var offsets:=PackedInt32Array([0])
	_check("native external database accepts checked schema",int(library.call("configure_external_database",data,weights,indices,times,offsets))==OK)
	var match:Dictionary=library.call("query_normalized_vector",PackedFloat32Array([1.9]),2)
	_check("native exact nearest index",match.get("valid",false) and int(match.matched_pose_index)==1,match)
	_check("native weighted distance",absf(float(match.cost)-.03)<.00001,match)
	_check("native continuation cost independent of selected pose",absf(float(match.continuation_cost)-13.23)<.0001,match)
	_check("native all database rows visited",int(match.poses_evaluated)==3,match)
	_check("reject shape mismatch",int(library.call("configure_external_database",data,weights,PackedInt32Array([0]),times,offsets))==ERR_INVALID_DATA)
	_check("reject negative weight",int(library.call("configure_external_database",data,PackedFloat32Array([-1.0]),indices,times,offsets))==ERR_INVALID_DATA)
	_check("reject nonfinite feature",int(library.call("configure_external_database",PackedFloat32Array([NAN,2,4]),weights,indices,times,offsets))==ERR_INVALID_DATA)
	_check("reject out-of-range feature",int(library.call("configure_external_database",PackedFloat32Array([1e20,2,4]),weights,indices,times,offsets))==ERR_INVALID_DATA)
	_check("reject incorrect animation block",int(library.call("configure_external_database",data,weights,PackedInt32Array([0,1,0]),times,offsets))==ERR_INVALID_DATA)
	_check("reject clip time outside duration",int(library.call("configure_external_database",data,weights,indices,PackedFloat32Array([0,.3,2]),offsets))==ERR_INVALID_DATA)
	_check("reject nonfinite query",not bool((library.call("query_normalized_vector",PackedFloat32Array([NAN]),0) as Dictionary).get("valid",true)))
	_check("reject excessive query magnitude",not bool((library.call("query_normalized_vector",PackedFloat32Array([1e20]),0) as Dictionary).get("valid",true)))
	_check("reject query dimension mismatch",not bool((library.call("query_normalized_vector",PackedFloat32Array([1,2]),0) as Dictionary).get("valid",true)))
	_check("reject invalid continuation index",not bool((library.call("query_normalized_vector",PackedFloat32Array([1]),9) as Dictionary).get("valid",true)))
	_check("invalid requests retain valid prior database",bool((library.call("query_normalized_vector",PackedFloat32Array([1.9]),2) as Dictionary).get("valid",false)))

func _database_query_contract(matcher:InkNativeMotionMatcher)->void:
	for native_pose:int in range(0,matcher._native_to_source.size(),13):
		var pose:int=matcher._native_to_source[native_pose]
		var query:=matcher._features.slice(pose*63,(pose+1)*63)
		var result:Dictionary=matcher._native_library.call("query_normalized_vector",query,native_pose)
		_check("source database row has native zero nearest cost",result.get("valid",false) and absf(float(result.cost))<.000001,result)
		_check("source row continuation has native zero cost",absf(float(result.continuation_cost))<.000001,result)
		_check("native/source index mapping is bijective",matcher._source_to_native[pose]==native_pose)

func _filter_contract(avatar:InkAvatar,weapon:String)->void:
	var selection:=avatar._blend_graph.get_node(&"MotionSelection") as AnimationNodeBlend2
	_check("lower-body filter enabled "+weapon,selection.filter_enabled)
	var clip:=avatar._animation.get_animation(avatar._clip("idle"))
	var allowed:=PackedStringArray()
	for track_index:int in clip.get_track_count():
		var track:NodePath=clip.track_get_path(track_index)
		var bone:String=String(track.get_subname(0)) if track.get_subname_count()>0 else ""
		var is_lower:bool=bone in Avatar.LOWER_BODY_BONES
		_check("only lower tracks selected "+String(track),selection.is_path_filtered(track)==is_lower)
		if is_lower:allowed.append(bone)
	for bone:String in Avatar.LOWER_BODY_BONES:
		_check("source lower track present "+weapon+" "+bone,allowed.has(bone))
	_check("inertia lower mask exact "+weapon,avatar._inertializer._bone_mask.size()==Avatar.LOWER_BODY_BONES.size())
	_check("upper weapon and face nodes excluded from native inertia "+weapon,avatar._inertializer._nodes.is_empty())

func _masked_inertia_contract(matcher:InkMotionMatcher)->void:
	var skeleton:=Skeleton3D.new()
	skeleton.add_bone("hips")
	skeleton.add_bone("spine")
	var held:=Transform3D(Basis(Vector3.UP,.3),Vector3(.1,.5,.02))
	skeleton.set_bone_pose(0,held)
	var inertia:=InkInertializer.new()
	inertia.configure(skeleton,[],PackedInt32Array([0]))
	skeleton.set_bone_pose(0,Transform3D(Basis(Vector3.RIGHT,-.8),Vector3(-.1,.4,.1)))
	var upper:=Transform3D(Basis(Vector3.FORWARD,.7).scaled(Vector3(1.1,.9,1.0)),Vector3(.2,.9,-.15))
	skeleton.set_bone_pose(1,upper)
	upper=skeleton.get_bone_pose(1)
	inertia.apply(skeleton,1.0/60.0,true,matcher,true)
	_check("native lower inertial transition preserves C0 position",skeleton.get_bone_pose_position(0).distance_to(held.origin)<.000001)
	_check("native lower inertial transition preserves C0 rotation",InkInertializer._log_rotation(skeleton.get_bone_pose_rotation(0)*held.basis.get_rotation_quaternion().inverse()).length()<.00001)
	_check("native inertia leaves upper raw transform exactly untouched",skeleton.get_bone_pose(1)==upper)
	skeleton.free()

func _count_mm_characters(node:Node)->int:
	var count:int=1 if node.get_class()=="MMCharacter" else 0
	for child:Node in node.get_children():count+=_count_mm_characters(child)
	return count
