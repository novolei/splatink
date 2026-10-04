extends SceneTree
const ActorNav=preload("res://scripts/game/ink_actor_nav.gd")
var checks:int=0
var failures:Array[String]=[]
func expect(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	for stage in ["tidewater","kelpline","halyard","cargo"]:
		var graph:=ActorNav.new()
		expect(graph.configure(stage),stage+" source navigation loads")
		for probe in graph.metadata.probes:
			var p:Array=probe.pos
			expect(graph.nearest(Vector3(p[0],p[1],p[2]),float(probe.max_up))==int(probe.id),stage+" source multi-floor nearest "+str(probe.id))
		for sample in graph.metadata.paths:
			var result:PackedInt32Array=graph.path_ids(int(sample.from),int(sample.to),int(sample.team))
			var source:PackedInt32Array=PackedInt32Array(sample.path) if sample.path is Array else PackedInt32Array()
			expect(result==source,stage+" exact source directed A* path/team "+str(sample.team)+" begin "+str(sample.from))
			for index in range(1,result.size()):
				var id:int=result[index]
				expect(graph.zones[id]<0 or graph.zones[id]==int(sample.team),stage+" path cannot enter enemy spawn")
				var type:String=graph.edge_type(result[index-1],id)
				expect(type in ["walk","jump","drop"],stage+" directed source traversal kind retained")
		var profiled_sample:Dictionary=graph.metadata.paths[0]
		graph.profile_navigation=true;graph.reset_query_profile();graph.clear_path_cache()
		var profile_result:PackedInt32Array=graph.path_ids(int(profiled_sample.from),int(profiled_sample.to),int(profiled_sample.team))
		var source_profile_result:PackedInt32Array=PackedInt32Array(profiled_sample.path) if profiled_sample.path is Array else PackedInt32Array()
		expect(profile_result==source_profile_result,stage+" profiling preserves exact source path order")
		expect(int(graph.query_profile.path_searches)==1 and int(graph.query_profile.path_iterations)>0,stage+" profile counts actual A* searches and visited heap entries")
		expect(int(graph.query_profile.path_max_iterations)<=6000,stage+" profiling retains the source 6000-iteration limit")
		graph.nearest(graph.point(int(profiled_sample.from)))
		expect(int(graph.query_profile.nearest_queries)==1,stage+" profiling records source nearest queries")
		var cached_result:PackedInt32Array=graph.path_ids(int(profiled_sample.from),int(profiled_sample.to),int(profiled_sample.team))
		expect(cached_result==source_profile_result and int(graph.query_profile.path_cache_hits)==1 and int(graph.query_profile.path_searches)==1,stage+" exact-input cache reuses the source route without another A* search")
		if not cached_result.is_empty():
			cached_result[0]=-999
			var isolated:PackedInt32Array=graph.path_ids(int(profiled_sample.from),int(profiled_sample.to),int(profiled_sample.team))
			expect(isolated==source_profile_result,stage+" caller path mutation cannot corrupt cached source routes")
		graph.path_ids(int(profiled_sample.from),int(profiled_sample.to),int(profiled_sample.team),0)
		graph.path_ids(int(profiled_sample.from),int(profiled_sample.to),int(profiled_sample.team),0)
		expect(int(graph.query_profile.path_cached_failures)==1,stage+" bounded search failures are cached by their exact iteration limit")
		graph.path_cache_capacity=2;graph.clear_path_cache();graph.reset_query_profile()
		for id in range(3):graph.path_ids(id,id,0)
		expect(graph._path_cache.size()==2,stage+" route cache stays within fixed capacity")
		var searches:int=int(graph.query_profile.path_searches)
		graph.path_ids(1,1,0);graph.path_ids(0,0,0)
		expect(int(graph.query_profile.path_searches)==searches+1,stage+" route cache evicts the oldest insertion without changing path decisions")
		graph.configure(stage)
		expect(graph._path_cache.is_empty(),stage+" reconfigure clears previous static-stage routes")
		graph.profile_navigation=false
		var jumps:int=0;var drops:int=0
		for type in graph.types:
			if type==1:jumps+=1
			if type==2:drops+=1
		expect(jumps>0 and drops>0,stage+" source graph retains raised-platform jumps and downward routes")
	print("Actor Nav source contract: %s checks, %s failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
