class_name InkNativeMotionMatcher
extends InkMotionMatcher
## Only the native MMAnimationLibrary performs the weighted exact pose search.
## Source query prediction, cycle cadence and authoritative physical movement stay intact.

static var _native_cache:Dictionary={}
var _native_library:AnimationLibrary
var _native_to_source:=PackedInt32Array()
var _source_to_native:=PackedInt32Array()
var native_query_count:=0
var native_query_microseconds:=0
var native_poses_evaluated:=0
var native_error:=""

static func available()->bool:
	return ClassDB.class_exists("MMAnimationLibrary") and ClassDB.class_has_method("MMAnimationLibrary","query_normalized_vector") and ClassDB.class_has_method("MMAnimationLibrary","configure_external_database")

func configure(skeleton:Skeleton3D,family:String,slot:int=0)->bool:
	if not available():
		native_error="Native MMAnimationLibrary external query API unavailable"
		return false
	if not super.configure(skeleton,family,slot):return false
	return _native_library!=null

func set_weapon(family:String)->void:
	super.set_weapon(family)
	if database.is_empty() or not available():return
	if not _native_cache.has(family):
		var bundle:=_build_native_database(family)
		if bundle.is_empty():return
		_native_cache[family]=bundle
	var cached:Dictionary=_native_cache[family]
	_native_library=cached.library as AnimationLibrary
	_native_to_source=cached.native_to_source
	_source_to_native=cached.source_to_native

func _build_native_database(family:String)->Dictionary:
	var library:=ClassDB.instantiate("MMAnimationLibrary") as AnimationLibrary
	if library==null:return {}
	var records:Dictionary={}
	for record:Dictionary in database.clips:
		if String(record.weapon)!=family:continue
		var clip:=Animation.new()
		clip.length=float(record.duration)
		clip.loop_mode=Animation.LOOP_LINEAR
		library.add_animation(StringName(record.name),clip)
		records[String(record.name)]=record
	var normalized:=PackedFloat32Array()
	var indices:=PackedInt32Array()
	var times:=PackedFloat32Array()
	var offsets:=PackedInt32Array()
	var to_source:=PackedInt32Array()
	var to_native:=PackedInt32Array()
	to_native.resize(int(database.count))
	to_native.fill(-1)
	var names:=library.get_animation_list()
	var dimensions:=int(database.dimensions)
	for animation_index:int in names.size():
		var record:Dictionary=records[String(names[animation_index])]
		offsets.append(normalized.size())
		for frame:int in int(record.count):
			var source_pose:=int(record.start)+frame
			to_native[source_pose]=to_source.size()
			to_source.append(source_pose)
			indices.append(animation_index)
			times.append(float(frame)/float(database.fps))
			normalized.append_array(_features.slice(source_pose*dimensions,(source_pose+1)*dimensions))
	var error:int=library.call("configure_external_database",normalized,_weights,indices,times,offsets)
	if error!=OK:
		native_error="Native database rejected with Error %d"%error
		return {}
	return {"library":library,"native_to_source":to_source,"source_to_native":to_native}

func _search_candidates()->void:
	var native_continuation:int=_source_to_native[matched_pose]
	var result:Dictionary=_native_library.call("query_normalized_vector",_query,native_continuation)
	if not bool(result.get("valid",false)):
		native_error=String(result.get("error","Native exact query failed"))
		# The opt-in must visibly fail instead of silently running a script search.
		push_error(native_error)
		continuation_cost=INF
		_best_pose=matched_pose
		_best_cost=INF
		return
	native_query_count+=1
	native_query_microseconds=int(result.query_microseconds)
	native_poses_evaluated=int(result.poses_evaluated)
	continuation_cost=float(result.continuation_cost)
	_best_pose=_native_to_source[int(result.matched_pose_index)]
	_best_cost=float(result.cost)

func debug_state()->Dictionary:
	var result:=super.debug_state()
	result["provider"]="native MMAnimationLibrary exact contiguous search"
	result["native_queries"]=native_query_count
	result["native_query_us"]=native_query_microseconds
	result["native_poses_evaluated"]=native_poses_evaluated
	result["native_error"]=native_error
	result["native_bucket_poses"]=_native_to_source.size()
	result["upper_body_masked"]=true
	return result
