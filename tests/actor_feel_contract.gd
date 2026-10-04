extends SceneTree
const Actor=preload("res://scripts/game/ink_actor.gd")
const Weapons=preload("res://scripts/game/ink_weapons.gd")
var checks:int=0
var failures:Array[String]=[]
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color.ORANGE,Color.BLUE]
	var network=null
	var state:String="playing"
	var stage=null
	var wall:bool=false
	var events:Array=[]
	func notify_event(kind:String,data:Dictionary)->void:events.append({"kind":kind,"data":data})
	func cast(from:Vector3,to:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:return {"position":from.lerp(to,.5),"normal":Vector3.LEFT} if wall else {}
	func sample_ink(_p:Vector3,_n:Vector3=Vector3.UP)->int:return 0
	func paint_splat(_p:Vector3,_n:Vector3,_r:float,_team:int,_extra:Dictionary={})->float:return 0.0
class Avatar:
	extends Node3D
	var hits:Array=[]
	var triggers:Array=[]
	var state:Dictionary={}
	func trigger(kind:String,arg=null)->void:
		triggers.append({"kind":kind,"arg":arg})
		if kind=="hit":hits.append(arg)
	func animate(_dt:float,data:Dictionary)->void:state=data
	func get_muzzle()->Vector3:return Vector3(0,1.05,.2)
	func aim_ready()->float:return 1.0
class Stage:
	extends Node
	var layout:Dictionary={"spawnPads":[[0,0,-10],[0,0,10]],"spawnBarrier":4.2}
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.00001)->void:expect(absf(actual-wanted)<tolerance,label+" got "+str(actual)+" expected "+str(wanted))
func vec(values:Array)->Vector3:return Vector3(values[0],values[1],values[2])
func _initialize()->void:call_deferred("run")
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/actor_feel.json"))
	var arena:=Arena.new();root.add_child(arena)
	var actor:=Actor.new();arena.add_child(actor);actor.match_node=arena;actor.reset_weapon();arena.actors=[actor]
	for probe in data.gravity:near(actor.air_vertical_velocity(float(probe.vertical),float(probe.dt)),float(probe.wanted),"Source fall/apex gravity composition")
	for trace in data.facing:
		actor.spawn_at(Vector3.ZERO);actor.rotation.y=float(trace.initial_yaw);actor._facing_velocity=float(trace.initial_velocity)
		actor.form="squid" if trace.mode in ["squid","swim","climb"] else "kid";actor.submerged=trace.mode=="swim";actor.climbing=trace.mode=="climb";actor.wall_normal=Vector3.LEFT
		actor.special_active="slam" if trace.mode=="special" else "";actor._prev={"sub":trace.mode=="sub"};actor.weapon_state.firing_time=1.0 if trace.mode=="aim" else 0.0
		for frame in trace.frames:
			actor.velocity=vec(frame.velocity);actor.aim_yaw=float(frame.aim_yaw);actor._face(1.0/60.0,vec(frame.move))
			near(wrapf(actor.rotation.y-float(frame.yaw),-PI,PI),0.0,"Source body facing spring "+str(trace.mode),.0001)
			near(actor._facing_velocity,float(frame.turn),"Source capped angular acceleration/feed-forward "+str(trace.mode),.001)
	for probe in data.weapons:
		actor.reset_weapon();actor.weapon_id=probe.weapon
		var state:Dictionary=probe.state;actor.charge=float(state.get("charge",0)) if bool(state.get("charging",false)) else 0.0
		actor.rolling=bool(state.get("rolling",false));actor.weapon_state.roll_time=float(state.get("rollT",0));actor.weapon_state.firing_time=float(state.get("firingT",0));actor.weapon_state.lock=float(state.get("lockT",0));actor.weapon_state.flick_recover=float(state.get("flickRecover",0))
		actor.weapon_state.windup=float(state.get("slosh",-1)) if actor.weapon_id=="slosher" else float(state.get("flick",-1));actor.weapon_state.burst=1.0 if bool(state.get("streaming",false)) else 0.0;actor.weapon_state.dodge=.2 if state.has("dodge") else 0.0
		near(actor.weapon_move_speed(),float(probe.speed),"Source weapon movement state "+str(probe.weapon))
		expect(actor.weapon_busy()==bool(probe.busy),"Source busy state prevents invalid dive/recharge")
		expect(actor.weapon_firing_pose()==bool(probe.pose),"Source firing pose persists after trigger release")
	actor.spawn_at(Vector3.ZERO);actor.invuln=0;actor.weapon_id="charger"
	var avatar:=Avatar.new();actor.add_child(avatar);actor.avatar=avatar
	var weapons:=Weapons.new();arena.add_child(weapons);weapons.configure(arena)
	weapons.tick_actor(actor,.005,{"fire":true});expect(actor.charge>0 and actor.charge<.02,"Source tiny charger tap begins a valid charge")
	weapons.tick_actor(actor,0,{"fire":false});near(actor.charge,0,"Tiny charger release clears charging instead of permanently blocking squid form")
	near(actor.ink,97.84,"Source minimum charger tap spends .12 of full ink cost")
	expect(not actor.weapon_busy() and actor.weapon_firing_pose(),"Source tiny charger shot retains firing pose without blocking swim")
	actor._last_fire=2;actor.ink=0;expect(not actor.spend_ink(1),"Empty weapon reports failed spend");near(actor._last_fire,2,"Failed empty shot does not postpone passive ink refill forever")
	actor.hp=100;actor.hurt_flash=0;avatar.hits.clear();actor.rotation.y=PI/2
	var attacker:=Node3D.new();arena.add_child(attacker);attacker.position=Vector3.BACK
	actor.damage(30,attacker);near(actor.hurt_flash,.5,"Source damage flash accumulates amount/60")
	expect(avatar.hits.size()==1 and avatar.hits[0] is Dictionary,"Source non-ink damage emits directional flinch data")
	near(float(avatar.hits[0].x),-1,"Source flinch direction follows +Z character frame")
	near(float(avatar.hits[0].amp),.5,"Source damage flinch amplitude")
	actor.damage(1,null,"ink");expect(avatar.hits.size()==1,"Source ink damage cannot trigger weapon flinch")
	expect(actor.last_attacker==attacker,"Damage without an attacker preserves previous attacker for water splat credit")
	weapons.clear();actor.reset_weapon();actor.weapon_id="shooter";actor.ink=70.5;actor.weapon_state.aiming_sub=true
	weapons.tick_actor(actor,0,{"fire":true,"sub_released":true})
	expect(weapons.bullets.size()==1 and weapons.bullets[0].kind=="shooter","Source primary fire spends ink before bomb release in the same frame")
	near(actor.ink,69.55,"Simultaneous primary shot can consume the last fraction needed for a bomb")
	weapons.clear();actor.reset_weapon();actor.ink=100
	weapons.tick_actor(actor,0,{"sub_released":true})
	expect(weapons.bullets.is_empty(),"Source bomb release requires a preceding armed sub press")
	for probe in data.landings:
		actor._hard_land=0;avatar.triggers.clear();arena.events.clear();actor._on_land(float(probe.vertical))
		near(actor.land_speed,float(probe.speed),"Source landing speed uses downward velocity only")
		near(actor._hard_land,float(probe.hard_land),"Source hard landing intensity retains speed-dependent recovery weight")
		expect(avatar.triggers.size()==probe.triggers.size(),"Source quiet and upward floor contacts cannot trigger landing animation/audio")
		if not avatar.triggers.is_empty():near(float(avatar.triggers[0].arg),float(probe.triggers[0][1]),"Source landing animation impact strength")
	var stage:=Stage.new();arena.add_child(stage);arena.stage=stage
	for probe in data.barriers:
		actor.global_position=vec(probe.pos);actor.velocity=vec(probe.vel);actor._spawn_barrier()
		expect(actor.global_position.distance_to(vec(probe.wanted_pos))<.00001,"Source enemy spawn barrier displacement")
		expect(actor.velocity.distance_to(vec(probe.wanted_vel))<.00001,"Source enemy spawn barrier reflects inward motion without blocking outward escape")
	actor.spawn_at(Vector3.ZERO);actor.form="squid";actor.climbing=false;arena.wall=true
	expect(actor._try_climb(true,Vector3.RIGHT,1.0/60.0,{}),"Own ink accepts squid wall attachment")
	expect(actor.form=="squid","Climbing retains source squid gameplay form without repeated form-change effects")
	actor.climbing=true;actor._animate(0)
	expect(avatar.state.form=="climb","Avatar receives wall climb visual form independently of gameplay squid form")
	expect(avatar.state.hurt_color==arena.team_colors[1],"Character hurt overlay uses source enemy team color")
	arena.state="intro";expect(not actor.can_super_jump(),"Source super jump is disabled outside a playing match")
	arena.state="playing";expect(actor.super_jump(Vector3.BACK),"Source super jump accepts playing state")
	expect(not actor.climbing and actor.form=="squid","Source super jump detaches the squid from the wall")
	actor.tick(0,{"aim_dir":Vector3(4,2,3),"aim_yaw":-.7,"aim_pitch":.25})
	near(actor.aim_yaw,-.7,"Source Player look yaw stays separate from muzzle convergence direction")
	near(actor.aim_pitch,.25,"Source Player look pitch stays separate from body-axis aim magnetism")
	near(actor.aim_dir.length(),1.0,"Converged weapon direction remains normalized")
	actor.tick(0,{"aim_dir":Vector3(4,2,3)})
	near(actor.aim_yaw,atan2(4,3),"Legacy actor commands derive yaw when explicit look is omitted")
	near(actor.aim_pitch,asin(2.0/sqrt(29.0)),"Legacy actor commands derive pitch when explicit look is omitted")
	print("Actor feel source contract: %s checks, %s failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
