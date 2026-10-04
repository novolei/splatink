extends SceneTree

const Fx=preload("res://scripts/fx/ink_fx.gd")
class Arena:
	extends Node3D
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
class Projectiles:
	extends RefCounted
	var bullets:Array=[]
	var storms:Array=[]
class Recorder:
	extends InkFx
	var effects:Array=[]
	func _shot_trail(p:Vector3,_v:Vector3,_col:Color,big:bool=false)->void:
		effects.append({"kind":"blaster" if big else "shot","pos":p})
	func _slosh_trail(p:Vector3,_v:Vector3,_col:Color,head:bool=false)->void:
		effects.append({"kind":"slosherHead" if head else "slosherTail","pos":p})
class RecipeRecorder:
	extends InkFx
	var random_values:Array=[]
	var random_index:int=0
	var entries:Array=[]
	func _trail_random()->float:
		var value:float=random_values[random_index];random_index+=1;return value
	func _drop(p:Vector3,v:Vector3,col:Color,size:float,life:float=1.2,gravity:float=1.0,stretch:float=1.3,cosmetic:bool=false)->void:
		entries.append({"pos":p,"vel":v,"color":col,"size":size,"life":life,"gravity":gravity,"stretch":stretch,"flags":1 if cosmetic else 0})

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<20:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.000005)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func f64(bytes:Array)->float:return PackedByteArray(bytes).decode_double(0)
func vector(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fx_projectile_hooks.json"))
	var arena:=Arena.new();root.add_child(arena)
	var camera:=Camera3D.new();arena.add_child(camera)
	var fx:=Recorder.new();arena.add_child(fx);fx.game=arena;fx._camera=camera
	for trace in data.traces:
		var p:=Projectiles.new()
		for b in trace.bullets:
			var kind:String=str(b.kind)
			p.bullets.append({"kind":"slosher" if kind.begins_with("slosher") else kind,"head":kind=="slosherHead","owner":null,"team":0})
		var frame_index:int=0
		for frame in trace.frames:
			for bullet in p.bullets:
				bullet.age=f64(frame.age_f64);bullet.delay=f64(frame.delay_f64);bullet.pos=vec(frame.pos);bullet.velocity=vec(frame.vel)
			fx.effects.clear();fx._projectile_effects(p,f64(frame.dt_f64))
			var label:String="%s f%d"%[trace.name,frame_index]
			expect(fx.effects.size()==frame.expected.effects.size(),label+" original trail emission count")
			for i in mini(fx.effects.size(),frame.expected.effects.size()):
				expect(fx.effects[i].kind==frame.expected.effects[i].kind,label+" original weapon recipe")
				vector(fx.effects[i].pos,frame.expected.effects[i].pos,label+" original trail origin")
			for i in p.bullets.size():
				near(float(p.bullets[i].fx_distance),float(frame.expected.distances[i]),label+" reset before visibility/budget")
				near(float(p.bullets[i].fx_age),float(frame.expected.ages[i]),label+" recycled age tracking")
			frame_index+=1
	var recipes:=RecipeRecorder.new();arena.add_child(recipes)
	for sample in data.recipes:
		recipes.entries.clear();recipes.random_values=sample.random;recipes.random_index=0
		recipes.call("_slosh_trail",vec(sample.pos),vec(sample.vel),Color(sample.color[0],sample.color[1],sample.color[2]),bool(sample.head))
		expect(recipes.random_index==recipes.random_values.size(),"Slosh trail consumes original random draws")
		expect(recipes.entries.size()==sample.drops.size(),"Head emits two drops; tail follows original .6 probability")
		for i in mini(recipes.entries.size(),sample.drops.size()):
			var got:Dictionary=recipes.entries[i];var wanted:Dictionary=sample.drops[i]
			vector(got.pos,wanted.pos,"Original slosh position jitter")
			vector(got.vel,wanted.vel,"Original slosh velocity inheritance")
			vector(Vector3(got.color.r,got.color.g,got.color.b),wanted.color,"Original raw linear team color")
			for field in ["size","life","gravity","stretch","flags"]:near(float(got[field]),float(wanted[field]),"Original slosh "+str(field))
	print("Source projectile FX hooks: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
