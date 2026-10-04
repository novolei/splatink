extends SceneTree
const Actor=preload("res://scripts/game/ink_actor.gd")
const Physics=preload("res://scripts/game/ink_actor_physics.gd")
class Stage:
	extends Node
	var stage_id:String="fixtures"
	var blocks:Array=[]
	var faces:Array=[]
	var bounds:Dictionary={}
	var layout:Dictionary={}
	var level_queries:InkLevelQueries=null
	var grid=null
class Manager:
	extends Node3D
	func tick_actor(_actor,_dt:float,_command:Dictionary)->void:pass
	func throw_storm(_actor)->void:pass
	func explode(_p,_actor,_radius,_maximum,_minimum,_paint_radius,_kind)->void:pass
class Arena:
	extends Node3D
	var stage:Node
	var projectiles:Node3D
	var state:String="playing"
	var team_colors:Array=[Color.ORANGE,Color.BLUE]
	var network=null
	var ink_team:int=-1
	var events:Array=[]
	func notify_event(kind:String,data:Dictionary)->void:
		if kind=="actor:land":events.append({"kind":"land","speed":data.speed})
		elif kind=="actor:climb":events.append({"kind":"climb","on":data.on})
		elif kind=="superjump:land":events.append({"kind":"jump_land"})
	func sample_ink(_p:Vector3,_n:Vector3=Vector3.UP)->int:return ink_team
	func paint_splat(_p:Vector3,_n:Vector3,_radius:float,_team:int,_extra:Dictionary={})->float:return 0.0
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures.append(label)
		if failures.size()<=24:push_error(label)
func near(actual:float,wanted:float,label:String)->void:expect(absf(actual-wanted)<.0005,label+" got"+str(actual)+" source"+str(wanted))
func run()->void:
	var records:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/actor_controller.json"))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/actor_physics/fixtures.json"))
	var arena:=Arena.new();root.add_child(arena)
	var stage:=Stage.new();arena.add_child(stage);arena.stage=stage
	stage.blocks=fixture.geometry.blocks;stage.faces=fixture.geometry.faces;stage.bounds=fixture.geometry.bounds;stage.layout=records.layout
	for b in stage.blocks:b.center=vec(b.center);b.half=vec(b.half);b.axes=b.axes.map(func(a):return vec(a))
	for f in stage.faces:f.origin=vec(f.origin);f.u=vec(f.u);f.v=vec(f.v);f.n=vec(f.n)
	var manager:=Manager.new();arena.add_child(manager);arena.projectiles=manager
	for trace in records.traces:
		var actor:=Actor.new();arena.add_child(actor);actor.match_node=arena
		expect(actor.configure_source_physics(stage),str(trace.name)+" uses actual validated source backend")
		actor.weapon_id="charger" if trace.get("special","")=="storm" else "shooter"
		actor.spawn_at(vec(trace.start));actor.invuln=0
		arena.ink_team=int(trace.get("ink",0))-1;arena.events.clear()
		if trace.has("superjump"):actor.super_jump(vec(trace.superjump))
		if trace.has("special"):actor.start_special()
		var index:int=0
		for frame in trace.frames:
			var command:Dictionary=frame.input.duplicate();command.move=vec(command.move)
			actor.tick(1.0/60.0,command)
			var w:Dictionary=frame.wanted;var label:String=str(trace.name)+" frame"+str(index);index+=1
			expect(actor.global_position.distance_to(vec(w.position))<.001,label+" controller path got"+str(actor.global_position)+" source"+str(w.position))
			expect(actor.velocity.distance_to(vec(w.velocity))<.001,label+" controller momentum got"+str(actor.velocity)+" source"+str(w.velocity))
			for field in ["form","submerged","climbing","alive"]:expect(actor.get(field)==w[field],label+" "+field)
			expect(actor.is_grounded()==bool(w.grounded),label+" exact support transition")
			for field in ["hp","ink","smooth_y","land_speed"]:near(float(actor.get(field)),float(w[field]),label+" "+field)
			expect(str(actor.super_jump_state.get("phase",""))==str(w.superjump),label+" superjump phase")
			expect(actor.special_active==str(w.special),label+" special body ownership")
			expect(arena.events.size()==w.events.size(),label+" source contact events count")
			for event_index in mini(arena.events.size(),w.events.size()):
				var actual:Dictionary=arena.events[event_index];var source:Dictionary=w.events[event_index]
				expect(actual.kind==source.kind,label+" event order")
				if source.has("speed"):near(float(actual.speed),float(source.speed),label+" impact feedback strength")
				if source.has("on"):expect(actual.on==source.on,label+" wall attachment feedback")
			arena.events.clear()
		actor.queue_free()
	print("Actor integrated source controller: %d checks, %d failures"%[checks,failures.size()])
	arena.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
