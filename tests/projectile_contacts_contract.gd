extends SceneTree

const Actor=preload("res://scripts/game/ink_actor.gd")
const Rules=preload("res://scripts/game/ink_rules.gd")
const Weapons=preload("res://scripts/game/ink_weapons.gd")
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color.ORANGE,Color.BLUE]
	var network=null
	var stage=null
	var state:String="playing"
	var boss=null
	var wall:float=-1
	var events:Array=[]
	func cast(from:Vector3,to:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:
		if wall>=0 and to.z>from.z and from.z<=wall and to.z>=wall:
			return {"position":from.lerp(to,(wall-from.z)/(to.z-from.z)),"normal":Vector3.FORWARD}
		return {}
	func notify_event(kind:String,data:Dictionary)->void:events.append({"kind":kind,"data":data})
	func paint_splat(_p:Vector3,_n:Vector3,_r:float,_team:int,_extra:Dictionary={})->float:return 0
	func sample_ink(_p:Vector3,_n:Vector3=Vector3.UP)->int:return -1
class BossProbe:
	extends Node3D
	var at:Vector3
	var distance:float=0
	var _crablets:Array=[]
	var hits:Array=[]
	func segment_hit(_a:Vector3,_b:Vector3,_r:float=0)->Dictionary:return {"point":at,"distance":distance,"crab":-1}
	func hit_segment(_a,hit:Dictionary,amount:float,weapon:String)->bool:
		hits.append({"target":"boss","damage":amount,"weapon":weapon,"point":hit.point})
		return false
class ContactWeapons:
	extends InkWeapons
	var hits:Array=[]
	var impacts:Array=[]
	var beam_origin:Vector3=Vector3(0,1.05,0)
	func apply_hit(_attacker,victim,amount:float,weapon_id:String)->bool:
		hits.append({"target":victim.display_name,"damage":amount,"weapon":weapon_id})
		return false
	func _muzzle(_actor)->Vector3:return beam_origin
	func _aim_from(_actor,_origin:Vector3)->Vector3:return Vector3.BACK
	func _impact(b:Dictionary,pos:Vector3,_normal:Vector3,direct=null,world_impact:bool=true)->void:
		if direct==null and world_impact:impacts.append({"kind":"world","point":pos});return
		var target:String="boss" if direct is BossProbe else str(direct.display_name) if direct!=null else ""
		if b.kind!="blaster":impacts.append({"kind":"contact","point":pos,"target":"" if direct is BossProbe else target})
		if b.kind=="blaster":impacts.append({"kind":"blast","point":pos,"target":target})
		if b.kind=="slosher" and bool(b.get("head",false)):impacts.append({"kind":"slosh","point":pos,"target":target})

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message);push_error(message)
func near(actual:float,wanted:float,label:String,tolerance:float=.0001)->void:expect(absf(actual-wanted)<tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func check_point(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func actor(arena:Arena,spec:Dictionary):
	var a:=Actor.new();arena.add_child(a);a.match_node=arena;a.reset_weapon()
	a.display_name=str(spec.get("name","owner"));a.team_id=int(spec.get("team",0));a.alive=bool(spec.get("alive",true))
	a.form=str(spec.get("form","kid"));a.submerged=bool(spec.get("swim",false));a.smooth_y=float(spec.get("smoothY",0))
	a.position=vec(spec.get("pos",[0,0,0]));arena.actors.append(a)
	return a
func prepare(arena:Arena,spec:Dictionary)->void:
	for a in arena.actors:a.free()
	arena.actors.clear();arena.events.clear();arena.wall=float(spec.world)
	if is_instance_valid(arena.boss):arena.boss.free()
	arena.boss=null
	actor(arena,{})
	for a in spec.actors:actor(arena,a)
	if float(spec.boss)>=0:
		arena.boss=BossProbe.new();arena.add_child(arena.boss)
		arena.boss.distance=float(spec.boss)
		arena.boss.at=Vector3(0,float(spec.get("y",spec.get("from",[0,.8,0])[1])),float(spec.boss))
func check_hits(got:Array,wanted:Array,label:String)->void:
	expect(got.size()==wanted.size(),label+" hit count")
	for i in mini(got.size(),wanted.size()):
		expect(got[i].target==wanted[i].target,label+" original contact priority")
		near(float(got[i].damage),float(wanted[i].damage),label+" original damage",.0002)
		expect(got[i].weapon==wanted[i].weapon,label+" original raw projectile weapon ID")
		if wanted[i].has("point"):check_point(got[i].point,wanted[i].point,label+" boss impact")
func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/projectile_contacts.json"))
	var arena:=Arena.new();root.add_child(arena)
	var w:=ContactWeapons.new();arena.add_child(w);w.configure(arena)
	for row in data.traces:
		var spec:Dictionary=row.input;prepare(arena,spec);w.clear();w.hits.clear();w.impacts.clear()
		var kind:String="slosher" if str(spec.kind).begins_with("slosher") else str(spec.kind)
		var head:bool=str(spec.kind)=="slosher_head"
		w._spawn_bullet({"pos":vec(spec.from),"velocity":(vec(spec.to)-vec(spec.from))*60.0,"owner":arena.actors[0],"team":0,"kind":kind,"life":2.0,"range":INF,"damage":125.0,"damage_far":30.0,"radius":.8,"straight":99.0,"trail_radius":0.0,"trail_every":0.0,"attack":7,"gravity":0.0,"drag":0.0,"weapon":Rules.weapon("slosher" if kind=="slosher" else "roller" if kind=="flick" else kind),"head":head})
		w.bullets[0].start=vec(spec.get("start",spec.from))
		if bool(spec.get("repeat",false)):w._hit_records["7:%s"%arena.actors[1].get_instance_id()]=w.clock
		w.update(1.0/60.0)
		expect(w.bullets.is_empty()==bool(row.wanted.dead),str(spec.name)+" original round termination")
		if not w.bullets.is_empty():check_point(w.bullets[0].pos,row.wanted.end,str(spec.name)+" original motion endpoint")
		var hits:Array=w.hits.duplicate()
		if is_instance_valid(arena.boss):hits.append_array(arena.boss.hits)
		check_hits(hits,row.wanted.hits,str(spec.name))
		expect(w.impacts.size()==row.wanted.impacts.size(),str(spec.name)+" original impact branch count")
		for i in mini(w.impacts.size(),row.wanted.impacts.size()):
			var want:Dictionary=row.wanted.impacts[i];var got:Dictionary=w.impacts[i]
			expect(got.kind==want.kind,str(spec.name)+" original impact branch")
			check_point(got.point,want.point,str(spec.name)+" exact sampled contact point")
			if want.has("target"):expect(got.target==want.target,str(spec.name)+" impact victim")
	for row in data.beams:
		var spec:Dictionary=row.input;prepare(arena,spec);w.clear();w.hits.clear();w.impacts.clear()
		var owner=arena.actors[0];owner.weapon_id="charger";owner.charge=1.0;w.beam_origin=Vector3(0,float(spec.y),0)
		w._charger(owner,Rules.weapon("charger"))
		var hits:Array=w.hits.duplicate()
		if is_instance_valid(arena.boss):hits.append_array(arena.boss.hits)
		check_hits(hits,row.wanted.hits,str(spec.name))
		var beam:Dictionary={}
		for event in arena.events:
			if event.kind=="weapon:beam":beam=event.data
		expect(not beam.is_empty(),str(spec.name)+" original beam is emitted")
		if not beam.is_empty():
			near(Vector3(beam.from).distance_to(beam.to),float(row.wanted.len),str(spec.name)+" actual endpoint distance")
			check_point(beam.to,row.wanted.end,str(spec.name)+" beam endpoint")
	print("Source projectile contact contract: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
