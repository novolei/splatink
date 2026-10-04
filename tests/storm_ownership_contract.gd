extends SceneTree

const Actor=preload("res://scripts/game/ink_actor.gd")
const Weapons=preload("res://scripts/game/ink_weapons.gd")
class NetworkProbe:
	extends Node
	var active:bool=false
	var owned:Array=[]
	var sent_hits:Array=[]
	var attempts:int=0
	func owns_actor(actor:Node)->bool:return owned.has(actor)
	func send_hit(attacker:Node,victim:Node,amount:float,cause:String)->bool:
		attempts+=1
		# Mirrors the production victim-owner guard before attacker validation.
		if owns_actor(victim):return false
		sent_hits.append({"attacker":attacker,"victim":victim,"amount":amount,"cause":cause})
		return true
class CloudProbe:
	extends Node3D
	func update(_time:float,value:float)->void:scale=Vector3.ONE*value
class BossProbe:
	extends Node
	var calls:int=0
	func rain(_owner,_pos:Vector3,_radius:float,_damage:float)->void:calls+=1
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
	var network:NetworkProbe
	var stage=null
	var boss:BossProbe
	var state:String="playing"
	var spec:Dictionary={}
	var contacts:Array=[]
	var paints:Array=[]
	var events:Array=[]
	func cast(a:Vector3,b:Vector3,_exclude:Array=[],mask:int=1)->Dictionary:
		contacts.append({"skipGrates":mask==1,"up":b.y>a.y})
		if not spec.has("roof") or (mask==1 and bool(spec.get("grate",false))):return {}
		var dy:float=b.y-a.y
		if absf(dy)<.00000001:return {}
		var t:float=(float(spec.roof)-a.y)/dy
		return {"position":a.lerp(b,t),"normal":Vector3.UP if dy<0 else Vector3.DOWN} if t>=0 and t<=1 else {}
	func paint_splat(p:Vector3,_normal:Vector3,radius:float,_team:int,_extra:Dictionary={})->float:
		paints.append({"point":p,"radius":radius})
		return 0
	func notify_event(kind:String,data:Dictionary)->void:
		if kind not in ["damage","splatted","hit","storm:end"]:return
		var victim=data.get("victim");var attacker=data.get("attacker")
		events.append({"kind":kind,"victim":victim.display_name if is_instance_valid(victim) else null,"attacker":attacker.display_name if is_instance_valid(attacker) else null,"amount":data.get("amount",data.get("damage",0)),"killed":data.get("killed",false),"cause":data.get("cause",data.get("source",data.get("weaponId",null)))})
	func sample_ink(_pos:Vector3,_normal:Vector3=Vector3.UP)->int:return -1

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<25:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.000001)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func run_contract()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/storm_ownership.json"))
	var arena:=Arena.new();root.add_child(arena)
	arena.network=NetworkProbe.new();arena.add_child(arena.network)
	arena.boss=BossProbe.new();arena.add_child(arena.boss)
	var weapons:=Weapons.new();arena.add_child(weapons);weapons.configure(arena)
	for trace in source.traces:
		weapons.clear()
		for actor in arena.actors:actor.free()
		arena.actors.clear();arena.network.owned.clear()
		var spec:Dictionary=trace.input;arena.spec=spec;arena.network.active=bool(spec.online)
		for row in spec.actors:
			var actor:=Actor.new();arena.add_child(actor);actor.match_node=arena;actor.reset_weapon()
			actor.display_name=str(row.name);actor.team_id=int(row.team);actor.position=Vector3(row.pos[0],row.pos[1],row.pos[2])
			actor.alive=bool(row.get("alive",true));actor.hp=float(row.get("hp",100));actor.invuln=float(row.get("invuln",0))
			actor.special_active="slam" if bool(row.get("armor",false)) else ""
			arena.actors.append(actor)
			if bool(row.owned):arena.network.owned.append(actor)
		var cloud:=CloudProbe.new();weapons.add_child(cloud);cloud.position=Vector3(0,5,0)
		weapons.storms.append({"owner":arena.actors[0],"team":0,"pos":cloud.position,"velocity":Vector3.ZERO,"life":6.5,"age":0.0,"scale":.01,"ghost":bool(spec.ghost),"paint_time":0.0,"node":cloud})
		var index:int=0
		for frame in trace.frames:
			arena.events.clear();arena.contacts.clear();arena.paints.clear();arena.network.sent_hits.clear();arena.network.attempts=0;arena.boss.calls=0
			var dt:float=PackedByteArray(spec.dt_f64).decode_double(0)
			weapons.clock+=dt;weapons._tick_storms(dt)
			var label:String="%s f%d"%[spec.name,index]
			expect((not weapons.storms.is_empty())==bool(frame.alive),label+" source exact retirement frame")
			near(cloud.scale.x,float(frame.scale),label+" original growth/fade",.000002)
			for i in arena.actors.size():
				var actor=arena.actors[i];var expected:Dictionary=frame.actors[i]
				near(actor.hp,float(expected.hp),label+" %s owner-local HP"%actor.display_name)
				expect(actor.alive==bool(expected.alive),label+" %s life"%actor.display_name)
				expect(actor.splats==int(expected.splats),label+" %s kill attribution"%actor.display_name)
				expect(actor.deaths==int(expected.deaths),label+" %s single death"%actor.display_name)
			expect(arena.network.sent_hits.is_empty(),label+" cloud owner must not send proxy-hit packet")
			var accepted:int=frame.events.filter(func(e:Dictionary)->bool:return e.kind=="damage").size()
			expect(arena.network.attempts==(accepted if bool(spec.online) else 0),label+" only owned non-invulnerable victims enter Actor.damage network guard")
			expect(arena.contacts.size()==frame.contacts.size(),label+" source rain/owned-victim query count")
			for i in mini(arena.contacts.size(),frame.contacts.size()):
				expect(arena.contacts[i].skipGrates==frame.contacts[i].skipGrates,label+" per-call rain=false/ceilingLOS=true mask")
				expect(arena.contacts[i].up==frame.contacts[i].up,label+" source rain-before-owner-damage query order")
			expect(arena.paints.size()==int(frame.paintCount),label+" ghost suppresses rain paint but owner kill retains burst")
			expect(arena.paints.filter(func(p:Dictionary)->bool:return is_equal_approx(float(p.radius),1.7)).size()==int(frame.splatPaints),label+" source kill ink burst count")
			expect(arena.boss.calls==int(frame.bossRain),label+" ghost suppresses Boss rain")
			expect(arena.events.size()==frame.events.size(),label+" source damage/splat/hit/end event count")
			for i in mini(arena.events.size(),frame.events.size()):
				for key in ["kind","victim","attacker","killed","cause"]:expect(arena.events[i][key]==frame.events[i][key],label+" single original event "+key)
				near(float(arena.events[i].amount),float(frame.events[i].amount),label+" source accepted event damage")
			index+=1
	print("Source storm ownership: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
