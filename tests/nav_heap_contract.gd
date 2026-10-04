extends SceneTree
const Nav=preload("res://scripts/game/ink_actor_nav.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures.append(label)
		if failures.size()<16:push_error(label)
func run()->void:
	var records:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/nav_heap.json"))
	var priorities:PackedFloat64Array=FileAccess.get_file_as_bytes(str(records.fields)).to_float64_array()
	for trace in records.traces:
		var heap=Nav.PackedHeap.new();heap.reserve(4)
		var count:int=0
		for operation in trace.operations:
			if operation.has("push"):heap.push(int(operation.push),priorities[int(operation.priority_index)]);count+=1
			else:
				expect(heap.pop()==int(operation.pop),str(trace.kind)+" exact source heap pop at count"+str(count));count-=1
			expect(heap.count==count,str(trace.kind)+" packed heap count")
		expect(heap.count==0 and heap.packed_ids.size()>=2048,str(trace.kind)+" capacity growth retains every queued entry")
	var timings:Array=[]
	for stage_id in ["tidewater","kelpline","halyard","cargo"]:
		var graph:=Nav.new();expect(graph.configure(stage_id),stage_id+" loads exact source graph")
		graph.path_cache_capacity=0
		for sample in graph.metadata.paths:
			graph.packed_heap_enabled=true
			var result:PackedInt32Array=graph.path_ids(int(sample.from),int(sample.to),int(sample.team))
			var source:PackedInt32Array=PackedInt32Array(sample.path) if sample.path is Array else PackedInt32Array()
			expect(result==source,stage_id+" packed solver keeps source path, heap duplicates and team rule")
		for packed in [false,true]:
			graph.packed_heap_enabled=packed;graph.profile_navigation=true;graph.reset_query_profile()
			var elapsed:Array=[]
			for repeat_index in 8:
				for sample in graph.metadata.paths:
					var start:int=Time.get_ticks_usec()
					graph.path_ids(int(sample.from),int(sample.to),int(sample.team))
					elapsed.append(Time.get_ticks_usec()-start)
			elapsed.sort()
			timings.append({"stage":stage_id,"packed":packed,"median_us":elapsed[floori(elapsed.size()*.5)],"p95_us":elapsed[floori(elapsed.size()*.95)],"max_us":elapsed.back(),"searches":graph.query_profile.path_searches,"heap_pops":graph.query_profile.path_iterations,"edges":graph.query_profile.path_edges})
		graph.packed_heap_enabled=false
	var file:=FileAccess.open("res://shots/nav_heap_benchmark.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify({"timings":timings,"checks":checks,"failures":failures.size()},"\t"));file.close()
	print("Source navigation heap contract: %d checks, %d failures"%[checks,failures.size()])
	print(JSON.stringify(timings))
	quit(0 if failures.is_empty() else 1)
