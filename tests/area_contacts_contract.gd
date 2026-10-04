extends SceneTree

const Actor=preload("res://scripts/game/ink_actor.gd")
const Rules=preload("res://scripts/game/ink_rules.gd")
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
	var stage=null
	var network=null
	var boss=null
	var state:String="playing"
	var spec:Dictionary={}
	var contacts:Array=[]
	func cast(a:Vector3,b:Vector3,_exclude:Array=[],mask:int=1)->Dictionary:
		contacts.append({"from":a,"to":b,"skipGrates":mask==1})
		if not spec.has("wall") or (mask==1 and bool(spec.get("grate",false))):return {}
		var dx:float=b.x-a.x
		if absf(dx)<.00000001:return {}
		var t:float=(float(spec.wall)-a.x)/dx
		if t<0 or t>1:return {}
		var p:Vector3=a.lerp(b,t)
		if p.y<float(spec.get("minY",-INF)) or p.y>float(spec.get("maxY",INF)):return {}
		return {"position":p,"normal":Vector3.LEFT}
	func notify_event(_kind:String,_data:Dictionary)->void:pass
	func paint_splat(_p:Vector3,_n:Vector3,_r:float,_t:int,_extra:Dictionary={})->float:return 0
	func sample_ink(_p:Vector3,_n:Vector3=Vector3.UP)->int:return -1
class ContactWeapons:
	extends InkWeapons
	var hits:Array=[]
	func apply_hit(_attacker,victim,amount:float,weapon:String)->bool:
		hits.append({"name":victim.display_name,"damage":amount,"weapon":weapon})
		return false

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<30:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.0002)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func point(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func run_contract()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/area_contacts.json"))
	var arena:=Arena.new();root.add_child(arena)
	var weapons:=ContactWeapons.new();arena.add_child(weapons);weapons.configure(arena)
	for trace in source.traces:
		weapons.clear();weapons.hits.clear()
		for actor in arena.actors:actor.free()
		arena.actors.clear();arena.contacts.clear();arena.spec=trace.input
		var spec:Dictionary=trace.input;var direct=null
		for row in spec.actors:
			var actor:=Actor.new();arena.add_child(actor);actor.match_node=arena;actor.reset_weapon()
			actor.display_name=str(row.name);actor.team_id=int(row.team);actor.position=vec(row.pos);actor.alive=bool(row.get("alive",true))
			arena.actors.append(actor)
			if row.name==spec.get("direct",null):direct=actor
			if spec.get("prior",[]).has(row.name):weapons._hit_records["7:%s"%actor.get_instance_id()]=weapons.clock
		var owner=arena.actors[0];var p:Vector3=vec(spec.pos)
		match str(spec.kind):
			"bomb":weapons.explode(p,owner,3.1,180,35,2.7,"bomb",direct)
			"blaster":weapons.explode(p,owner,2.6,70,30,1.5,"blaster",direct)
			"slosh":weapons._slosh_splash({"owner":owner,"team":0,"attack":7,"weapon":Rules.weapon("slosher")},p,direct)
			"slam":weapons.explode(p,owner,5.2,180,55,5.2,"slam",direct)
		var label:String=str(spec.name)
		expect(weapons.hits.size()==trace.hits.size(),label+" exact accepted area-hit count")
		for i in mini(weapons.hits.size(),trace.hits.size()):
			expect(weapons.hits[i].name==trace.hits[i].name,label+" source victim order/exclusions")
			near(float(weapons.hits[i].damage),float(trace.hits[i].damage),label+" source radial damage")
			expect(weapons.hits[i].weapon==trace.hits[i].weapon,label+" source area weapon ID")
		expect(arena.contacts.size()==trace.contacts.size(),label+" source terrain query count")
		for i in mini(arena.contacts.size(),trace.contacts.size()):
			expect(arena.contacts[i].skipGrates==trace.contacts[i].skipGrates,label+" floor/LOS original grate mask")
			point(arena.contacts[i]["from"],trace.contacts[i]["from"],label+" original LOS origin")
			point(arena.contacts[i].to,trace.contacts[i].to,label+" original len-minus-5cm endpoint")
	print("Source area contacts: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
