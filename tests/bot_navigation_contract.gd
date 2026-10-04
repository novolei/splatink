extends SceneTree
const Bots=preload("res://scripts/game/ink_bots.gd")
var checks:int=0
var failures:Array[String]=[]
class Ground:
	extends Node
	var bounds:Array=[-4,-4,4,4]
	func ground_height(x:float,z:float,_max_y:float=50)->float:
		return 0.0 if x>=float(bounds[0]) and z>=float(bounds[1]) and x<=float(bounds[2]) and z<=float(bounds[3]) else -INF
class ActorStub:
	extends Node3D
	var velocity:=Vector3.ZERO
	var weapon_id:String="shooter"
	var charge:float=0
	var aim_yaw:float=0
	func is_on_floor()->bool:return true
class Arena:
	extends Node
	var stage:Node
	var actors:Array=[]
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func near(actual:float,wanted:float,label:String)->void:expect(absf(actual-wanted)<.00001,label+" got "+str(actual)+" expected "+str(wanted))
func _initialize()->void:call_deferred("run")
func vec(values:Array)->Vector3:return Vector3(values[0],values[1],values[2])
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/bot_navigation.json"))
	var arena:=Arena.new();root.add_child(arena)
	var ground:=Ground.new();arena.add_child(ground);arena.stage=ground
	var actor:=ActorStub.new();arena.add_child(actor);arena.actors=[actor]
	var bots:=Bots.new();bots.match_node=arena
	for probe in data.edges:
		actor.position=vec(probe.pos);actor.velocity=Vector3(0,0,probe.speed);ground.bounds=probe.bounds
		var move:=Vector3(sin(float(probe.angle)),0,cos(float(probe.angle)))
		expect(bots.edge_guard(actor,move).distance_to(vec(probe.move))<.00001,"Source stopping-distance water edge guard "+str(probe.pos)+" speed "+str(probe.speed)+" angle "+str(probe.angle))
	for probe in data.water:
		actor.position=vec(probe.pos);ground.bounds=probe.bounds
		expect(bots.near_water(actor,float(probe.radius))==bool(probe.wet),"Source eight-heading water proximity "+str(probe.pos)+" radius "+str(probe.radius))
	for probe in data.tail:
		actor.position=vec(probe.pos);actor.velocity=Vector3.ZERO;ground.bounds=probe.bounds
		actor.weapon_id=probe.weapon;actor.charge=1.0 if probe.charging else 0.0
		var state:Dictionary={"path":PackedVector3Array([Vector3.ZERO,Vector3.ONE,Vector3(2,0,2)]),"nav_ids":PackedInt32Array([1,2,3]),"path_index":0,"no_progress":probe.progress,"jump_cooldown":probe.jump_cd,"best_distance":3.0,"goal_time":4.0,"repath":1.0,"move_magnitude":1.0,"need_jump":probe.need_jump}
		var command:Dictionary={"move":Vector3.BACK,"jump":false}
		bots._navigation_tail(actor,state,command,bool(probe.want_move))
		var result:Dictionary=probe.result
		expect(command.jump==bool(result.jump),"Source stalled hop/required jump condition")
		near(float(state.jump_cooldown),float(result.jump_cd),"Source navigation hop cooldown")
		expect(int(state.path_index)==int(result.pi),"Source delayed waypoint skip")
		near(float(state.no_progress),float(result.no_progress),"Source stalled progress/reset")
		expect(bool(state.get("skipped",false))==bool(result.skipped),"Source waypoint skip only once")
		expect((not state.path.is_empty())==bool(result.path),"Source long-stall path invalidation")
		near(float(state.goal_time),float(result.goal_timer),"Source long-stall goal invalidation")
		near(float(state.repath),float(result.repath),"Source long-stall immediate replan")
		expect(bool(state.need_jump)==bool(result.need_jump),"Source required jump persists until cooldown clears")
		expect(is_inf(float(state.best_distance)) if result.best_distance==null else absf(float(state.best_distance)-float(result.best_distance))<.00001,"Source waypoint skip resets best distance")
		expect(Vector3(command.move).distance_to(vec(result.move))<.00001,"Source water guard runs after command smoothing")
	for probe in data.aim:
		var state:Dictionary={"time":probe.time,"acq_time":probe.acquired,"ph1":probe.ph1,"ph2":probe.ph2,"acq_sign_y":probe.sign_y,"acq_sign_p":probe.sign_p}
		var wanted:Vector2=bots.target_aim(Vector2(probe.ideal[0],probe.ideal[1]),state,{"aimError":.06,"reaction":.32},true)
		near(wanted.x,float(probe.wanted[0]),"Source Boss human aim wander/acquisition yaw")
		near(wanted.y,float(probe.wanted[1]),"Source Boss human aim wander/acquisition pitch")
	print("Bot navigation source contract: %s checks, %s failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
