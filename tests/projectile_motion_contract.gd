extends SceneTree

const Actor=preload("res://scripts/game/ink_actor.gd")
const Rules=preload("res://scripts/game/ink_rules.gd")
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color.ORANGE,Color.BLUE]
	var network=null
	var stage=null
	var state:String="playing"
	var boss=null
	func cast(from:Vector3,to:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:
		# Source segment() is empty; only the separate vertical trail ray hits.
		if from.x==to.x and from.z==to.z and from.y>=0 and to.y<=0:
			return {"position":from.lerp(to,from.y/(from.y-to.y)),"normal":Vector3.UP}
		return {}
	func notify_event(_kind:String,_data:Dictionary)->void:pass
	func paint_splat(_pos:Vector3,_n:Vector3,_r:float,_team:int,_extra:Dictionary={})->float:return 0
	func sample_ink(_pos:Vector3,_n:Vector3=Vector3.UP)->int:return -1
class MotionWeapons:
	extends InkWeapons
	var paints:Array=[]
	var bursts:Array=[]
	func _paint(owner,pos:Vector3,_normal:Vector3,radius:float,_options:Dictionary={},_fill:bool=true)->void:
		paints.append({"pos":pos,"radius":radius,"team":owner.team_id})
	func _impact(_bullet:Dictionary,pos:Vector3,_normal:Vector3,_direct=null,_world:bool=true)->void:
		bursts.append(pos)

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<20:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.0002)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(values:Array)->Vector3:return Vector3(values[0],values[1],values[2])
func f64(bytes:Array)->float:return PackedByteArray(bytes).decode_double(0)
func vector(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/projectile_motion.json"))
	var arena:=Arena.new();root.add_child(arena)
	var owner:=Actor.new();arena.add_child(owner);owner.match_node=arena;owner.reset_weapon()
	# Owner stays outside the contact array: isolate original integrator/lifecycle.
	var weapons:=MotionWeapons.new();arena.add_child(weapons);weapons.configure(arena)
	for trace in data.traces:
		var spec:Dictionary=trace.input;weapons.clear()
		var kind:String=str(spec.kind)
		weapons._spawn_bullet({"pos":vec(spec.pos),"velocity":vec(spec.vel),"owner":owner,"team":0,"kind":kind,"life":f64(spec.life_f64),"range":INF,"damage":35.0,"damage_far":30.0,"radius":.8,"straight":float(spec.straight),"trail_radius":float(spec.get("trailRadius",0)),"trail_every":float(spec.get("trailEvery",0)),"trail":float(spec.get("trail",0)),"attack":1,"gravity":float(spec.gravity),"drag":float(spec.drag),"delay":float(spec.get("delay",0)),"weapon":Rules.weapon("roller" if kind=="flick" else kind)})
		var bullet:Dictionary=weapons.bullets[0]
		var index:int=0
		for frame in trace.frames:
			weapons.paints.clear();weapons.bursts.clear()
			weapons.update(f64(spec.dt_f64))
			var label:String="%s frame%d"%[spec.name,index]
			expect((not weapons.bullets.is_empty())==bool(frame.alive),label+" exact termination frame age=%.17f life=%.17f"%[float(bullet.age),float(bullet.lifetime)])
			near(float(bullet.age),float(frame.age),label+" authoritative age",.000000001)
			near(float(bullet.delay),float(frame.delay),label+" delay crossing",.000000001)
			vector(bullet.pos,frame.pos,label+" source position")
			vector(bullet.velocity,frame.vel,label+" source velocity")
			near(float(bullet.trail),float(frame.trail),label+" strict trail accumulator")
			expect(weapons.paints.size()==frame.paints.size(),label+" source drip count")
			for i in mini(weapons.paints.size(),frame.paints.size()):
				vector(weapons.paints[i].pos,frame.paints[i].pos,label+" source drip point")
				expect(weapons.paints[i].team==int(frame.paints[i].team),label+" source drip team")
				expect(float(weapons.paints[i].radius)>=float(spec.trailRadius)*.8 and float(weapons.paints[i].radius)<=float(spec.trailRadius)*1.2,label+" original drip random radius range")
			expect(weapons.bursts.size()==frame.bursts.size(),label+" timed blaster detonation count")
			for i in mini(weapons.bursts.size(),frame.bursts.size()):vector(weapons.bursts[i],frame.bursts[i],label+" source blast endpoint")
			index+=1
	print("Projectile motion source contract: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
