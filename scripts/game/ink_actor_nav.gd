class_name InkActorNav
extends RefCounted

## Native query/solver for the offline-baked source NavGraph, with its exact
## cell order, multi-floor nearest lookup, directed edges and team-zone rules.
static var _cache:Dictionary={}
var metadata:Dictionary={}
var positions:PackedFloat64Array=[]
var zones:PackedInt32Array=[]
var valid:PackedByteArray=[]
var offsets:PackedInt32Array=[]
var targets:PackedInt32Array=[]
var costs:PackedFloat64Array=[]
var types:PackedByteArray=[]
var cell_offsets:PackedInt32Array=[]
var cell_ids:PackedInt32Array=[]
var valid_ids:PackedInt32Array=[]
var _g:PackedFloat32Array=[]
var _from:PackedInt32Array=[]
var _seen:PackedInt32Array=[]
var _closed:PackedInt32Array=[]
var _stamp:int=0
var profile_navigation:bool=false
var query_profile:Dictionary={}
var path_cache_capacity:int=256
var _path_cache:Dictionary={}
var _path_cache_order:Array[Vector4i]=[]
var _path_cache_cursor:int=0
var packed_heap_enabled:bool=true
var _packed_heap:PackedHeap=PackedHeap.new()

func reset_query_profile() -> void:
	query_profile={"nearest_us":0,"nearest_queries":0,"path_us":0,"path_searches":0,"path_iterations":0,"path_edges":0,"path_failures":0,"path_max_iterations":0,"path_max_us":0,"path_cache_hits":0,"path_cached_failures":0}

func clear_path_cache() -> void:
	_path_cache.clear();_path_cache_order.clear();_path_cache_cursor=0

class Heap:
	extends RefCounted
	var ids:Array[int]=[]
	var priorities:Array[float]=[]
	var count:int=0
	func push(id:int,priority:float) -> void:
		var index:int=ids.size();ids.append(id);priorities.append(priority)
		count+=1
		while index>0:
			var parent:int=(index-1)>>1
			if priorities[parent]<=priority:break
			ids[index]=ids[parent];priorities[index]=priorities[parent];index=parent
		ids[index]=id;priorities[index]=priority
	func pop() -> int:
		var top:int=ids[0];var last:int=ids.pop_back();var priority:float=priorities.pop_back()
		count-=1
		if not ids.is_empty():
			var index:int=0;var count:int=ids.size()
			while true:
				var left:int=index*2+1;var right:int=left+1;var smallest:int=index;var best:float=priority
				if left<count and priorities[left]<best:smallest=left;best=priorities[left]
				if right<count and priorities[right]<best:smallest=right
				if smallest==index:break
				ids[index]=ids[smallest];priorities[index]=priorities[smallest];index=smallest
			ids[index]=last;priorities[index]=priority
		return top

# A measured implementation of the same source heap comparisons. Packed
# storage retains Float64 priorities and duplicate/tied entry ordering, while
# reusing backing memory between exact queries. The original Array heap remains
# available for controlled timing/equivalence comparisons.
class PackedHeap:
	extends Heap
	var packed_ids:PackedInt32Array=[]
	var packed_priorities:PackedFloat64Array=[]
	func reserve(capacity:int) -> void:
		if capacity>packed_ids.size():packed_ids.resize(capacity);packed_priorities.resize(capacity)
	func push(id:int,priority:float) -> void:
		if count==packed_ids.size():reserve(maxi(32,count*2))
		var index:int=count;count+=1
		while index>0:
			var parent:int=(index-1)>>1
			if packed_priorities[parent]<=priority:break
			packed_ids[index]=packed_ids[parent];packed_priorities[index]=packed_priorities[parent];index=parent
		packed_ids[index]=id;packed_priorities[index]=priority
	func pop() -> int:
		var top:int=packed_ids[0]
		count-=1
		if count>0:
			var last:int=packed_ids[count];var priority:float=packed_priorities[count];var index:int=0
			while true:
				var left:int=index*2+1;var right:int=left+1;var smallest:int=index;var best:float=priority
				if left<count and packed_priorities[left]<best:smallest=left;best=packed_priorities[left]
				if right<count and packed_priorities[right]<best:smallest=right
				if smallest==index:break
				packed_ids[index]=packed_ids[smallest];packed_priorities[index]=packed_priorities[smallest];index=smallest
			packed_ids[index]=last;packed_priorities[index]=priority
		return top

func configure(stage_id:String) -> bool:
	clear_path_cache()
	var path:String="res://data/actor_nav/%s.json"%stage_id
	if not FileAccess.file_exists(path):return false
	if not _cache.has(stage_id):
		var record=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not record is Dictionary:return false
		var bytes:PackedByteArray=FileAccess.get_file_as_bytes(str(record.fields))
		var fields:Dictionary={"metadata":record}
		for name in record.sections:
			var section:Dictionary=record.sections[name]
			var data:PackedByteArray=bytes.slice(int(section.offset),int(section.offset)+int(section.bytes))
			if name in ["positions","costs"]:fields[name]=data.to_float64_array()
			elif name in ["valid","types"]:fields[name]=data
			else:fields[name]=data.to_int32_array()
		_cache[stage_id]=fields
	var fields:Dictionary=_cache[stage_id]
	metadata=fields.metadata;positions=fields.positions;zones=fields.zones;valid=fields.valid;offsets=fields.offsets;targets=fields.targets;costs=fields.costs;types=fields.types;cell_offsets=fields.cell_offsets;cell_ids=fields.cell_ids
	valid_ids.clear()
	for id in valid.size():
		if valid[id]:valid_ids.append(id)
	for field in ["_g","_from","_seen","_closed"]:
		var storage=get(field);storage.resize(valid.size());set(field,storage)
	_packed_heap.reserve(valid.size()+128);_packed_heap.count=0
	return true

func point(id:int) -> Vector3:
	return Vector3(positions[id*3],positions[id*3+1],positions[id*3+2])

func nearest(pos:Vector3,max_up:float=.8) -> int:
	var started:int=Time.get_ticks_usec() if profile_navigation else 0
	if metadata.is_empty():return -1
	var ix:int=int(floor((pos.x-float(metadata.x0))/float(metadata.step)+.5))
	var iz:int=int(floor((pos.z-float(metadata.z0))/float(metadata.step)+.5))
	var nx:int=int(metadata.nx);var nz:int=int(metadata.nz)
	var best:int=-1;var distance:float=INF
	# Native Vector3 input is float32. Keep the original inclusive maxUp boundary
	# when conversion of -.8 becomes -.8000000119; source node heights are float64.
	var height_limit:float=pos.y+max_up
	var input_precision:float=maxf(0.0000001,absf(pos.y)*0.00000012)
	for radius in 4:
		for dz in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				if maxi(absi(dx),absi(dz))!=radius:continue
				var x:int=ix+dx;var z:int=iz+dz
				if x<0 or z<0 or x>=nx or z>=nz:continue
				var cell:int=z*nx+x
				for index in range(cell_offsets[cell],cell_offsets[cell+1]):
					var id:int=cell_ids[index]
					if not valid[id] or positions[id*3+1]>height_limit+input_precision:continue
					var px:float=positions[id*3]-pos.x;var py:float=(positions[id*3+1]-pos.y)*2.5;var pz:float=positions[id*3+2]-pos.z
					var squared:float=px*px+py*py+pz*pz
					if squared<distance:distance=squared;best=id
		if best>=0:
			_profile_nearest(started)
			return best
	_profile_nearest(started)
	return best

func _profile_nearest(started:int) -> void:
	if not profile_navigation:return
	query_profile.nearest_us=int(query_profile.get("nearest_us",0))+Time.get_ticks_usec()-started
	query_profile.nearest_queries=int(query_profile.get("nearest_queries",0))+1

func _heuristic(id:int,target:int) -> float:
	var x:float=positions[id*3]-positions[target*3];var z:float=positions[id*3+2]-positions[target*3+2]
	return sqrt(x*x+z*z)+absf(positions[id*3+1]-positions[target*3+1])*.5

func path_ids(begin:int,end:int,team:int,max_iterations:int=6000) -> PackedInt32Array:
	if begin<0 or end<0 or begin>=valid.size() or end>=valid.size():return PackedInt32Array()
	var cache_key:=Vector4i(begin,end,team,max_iterations)
	if path_cache_capacity>0 and _path_cache.has(cache_key):
		var cached:PackedInt32Array=_path_cache[cache_key]
		if profile_navigation:
			query_profile.path_cache_hits=int(query_profile.get("path_cache_hits",0))+1
			if cached.is_empty():query_profile.path_cached_failures=int(query_profile.get("path_cached_failures",0))+1
		return cached.duplicate()
	var started:int=Time.get_ticks_usec() if profile_navigation else 0
	_stamp+=1
	var heap:Heap=_packed_heap if packed_heap_enabled else Heap.new()
	heap.count=0
	_g[begin]=0;_from[begin]=-1;_seen[begin]=_stamp;heap.push(begin,_heuristic(begin,end))
	var iterations:int=0
	var edge_count:int=0
	while heap.count>0 and iterations<max_iterations:
		iterations+=1
		var current:int=heap.pop()
		if current==end:break
		if _closed[current]==_stamp:continue
		_closed[current]=_stamp
		if profile_navigation:edge_count+=offsets[current+1]-offsets[current]
		for edge in range(offsets[current],offsets[current+1]):
			var id:int=targets[edge]
			if zones[id]>=0 and zones[id]!=team:continue
			var cost:float=float(_g[current])+costs[edge]
			if _seen[id]!=_stamp or cost<float(_g[id]):
				_seen[id]=_stamp;_g[id]=cost;_from[id]=current;heap.push(id,cost+_heuristic(id,end))
	_profile_path(started,iterations,edge_count,_seen[end]!=_stamp)
	if _seen[end]!=_stamp:
		_store_path(cache_key,PackedInt32Array())
		return PackedInt32Array()
	var result:PackedInt32Array=[];var previous:int=end
	while previous!=-1:
		result.append(previous);previous=_from[previous]
		if result.size()>4000:break
	result.reverse();_store_path(cache_key,result);return result

func _store_path(key:Vector4i,result:PackedInt32Array) -> void:
	if path_cache_capacity<=0:return
	# Preserve the source solver/heap ordering; only memoize its pure static result.
	# A defensive copy both here and on retrieval isolates callers' mutable paths.
	if _path_cache_order.size()>=path_cache_capacity:
		if _path_cache_cursor>=_path_cache_order.size():_path_cache_cursor=0
		_path_cache.erase(_path_cache_order[_path_cache_cursor])
		_path_cache_order[_path_cache_cursor]=key
		_path_cache_cursor=(_path_cache_cursor+1)%path_cache_capacity
	else:_path_cache_order.append(key)
	_path_cache[key]=result.duplicate()

func _profile_path(started:int,iterations:int,edges:int,failed:bool) -> void:
	if not profile_navigation:return
	var elapsed:int=Time.get_ticks_usec()-started
	query_profile.path_us=int(query_profile.get("path_us",0))+elapsed
	query_profile.path_searches=int(query_profile.get("path_searches",0))+1
	query_profile.path_iterations=int(query_profile.get("path_iterations",0))+iterations
	query_profile.path_edges=int(query_profile.get("path_edges",0))+edges
	query_profile.path_failures=int(query_profile.get("path_failures",0))+(1 if failed else 0)
	query_profile.path_max_iterations=maxi(int(query_profile.get("path_max_iterations",0)),iterations)
	query_profile.path_max_us=maxi(int(query_profile.get("path_max_us",0)),elapsed)

func find_path(from:Vector3,to:Vector3,team:int=0,max_up:float=.8) -> PackedVector3Array:
	var ids:PackedInt32Array=path_ids(nearest(from,max_up),nearest(to,max_up),team)
	var result:PackedVector3Array=[]
	for id in ids:result.append(point(id))
	return result

func edge_type(begin:int,end:int) -> String:
	if begin<0 or begin+1>=offsets.size():return "walk"
	for edge in range(offsets[begin],offsets[begin+1]):
		if targets[edge]==end:return ["walk","jump","drop"][types[edge]]
	return "walk"
