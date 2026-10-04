extends SceneTree

const Actor=preload("res://scripts/game/ink_actor.gd")
class Arena:
	extends Node3D
	var actors:Array=[]
	var team_colors:Array=[Color.ORANGE,Color.BLUE]
	var stage=null
	var network=null
	var boss=null
	var state:String="playing"
	var planes:Array=[]
	var contacts:Array=[]
	var events:Array=[]
	func cast(a:Vector3,b:Vector3,_exclude:Array=[],mask:int=1)->Dictionary:
		contacts.append({"skipGrates":mask==1})
		var best:float=INF;var hit:Dictionary={}
		for plane in planes:
			if mask==1 and bool(plane.get("grate",false)):continue
			var n:Vector3=Vector3(plane.normal[0],plane.normal[1],plane.normal[2]).normalized()
			var p:=Vector3(plane.point[0],plane.point[1],plane.point[2])
			var da:float=(a-p).dot(n);var db:float=(b-p).dot(n)
			if da>=0 and db<0:
				var t:float=da/(da-db)
				if t<best:best=t;hit={"position":a.lerp(b,t),"normal":n}
		return hit
	func notify_event(kind:String,data:Dictionary)->void:events.append({"kind":kind,"data":data})
	func paint_splat(_p:Vector3,_n:Vector3,_r:float,_team:int,_extra:Dictionary={})->float:return 0
	func sample_ink(_p:Vector3,_n:Vector3=Vector3.UP)->int:return -1
class Recorder:
	extends InkWeapons
	var bursts:Array=[]
	var clouds:Array=[]
	func explode(p:Vector3,_owner,_r:float,_max:float,_min:float,_paint_r:float,_kind:String,_skip=null,_fx_r:float=-1.0,_visual:bool=false)->void:bursts.append(p)
	func spawn_storm(_owner,p:Vector3,_dir:Vector3,_ghost:bool=false)->void:clouds.append(p)

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
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func vector(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/throwables.json"))
	var arena:=Arena.new();root.add_child(arena)
	var owner:=Actor.new();arena.add_child(owner);owner.match_node=arena;owner.reset_weapon()
	var weapons:=Recorder.new();arena.add_child(weapons);weapons.configure(arena)
	for trace in data.traces:
		var s:Dictionary=trace.input;weapons.clear();arena.planes=s.planes
		weapons._spawn_bullet({"pos":vec(s.pos),"velocity":vec(s.vel),"owner":owner,"team":0,"kind":str(s.kind),"life":8.0 if s.kind=="bomb" else 1.1,"range":INF,"damage":0.0,"radius":0.0,"straight":0.0,"trail_radius":0.0,"trail_every":0.0,"attack":1,"gravity":24.0,"fuse":-1.0,"beep":0.0,"weapon":{}})
		var bullet:Dictionary=weapons.bullets[0];bullet.spin=vec(s.spin)
		var index:int=0
		for frame in trace.frames:
			arena.contacts.clear();arena.events.clear();weapons.bursts.clear();weapons.clouds.clear()
			weapons.update(PackedByteArray(s.dt_f64).decode_double(0))
			var label:String="%s f%d"%[s.name,index]
			expect((not weapons.bullets.is_empty())==bool(frame.alive),label+" exact retirement frame")
			near(float(bullet.age),float(frame.age),label+" source age",.000000001)
			near(float(bullet.fuse),float(frame.fuse),label+" source armed fuse",.000000001)
			near(float(bullet.get("beep",0)),float(frame.beep),label+" source beep timer",.000000001)
			vector(bullet.pos,frame.pos,label+" source throw position")
			vector(bullet.velocity,frame.vel,label+" source bounce velocity")
			near(bullet.mesh.rotation.x,frame.rotation[0],label+" source tumbling X")
			near(bullet.mesh.rotation.z,frame.rotation[1],label+" source tumbling Z")
			vector(bullet.mesh.scale/(1.25 if s.kind=="storm_pod" else 1.0),frame.scale,label+" source group scale (native pod mesh contains1.25 body scale)")
			expect(arena.contacts.size()==frame.contacts.size(),label+" original contact query count")
			for i in mini(arena.contacts.size(),frame.contacts.size()):expect(arena.contacts[i].skipGrates==frame.contacts[i].skipGrates,label+" thrown bomb/pod collide with grates")
			expect(weapons.bursts.size()==frame.bursts.size(),label+" source fuse explosion")
			for i in mini(weapons.bursts.size(),frame.bursts.size()):vector(weapons.bursts[i],frame.bursts[i],label+" bomb burst point")
			expect(weapons.clouds.size()==frame.clouds.size(),label+" source storm cloud creation")
			for i in mini(weapons.clouds.size(),frame.clouds.size()):vector(weapons.clouds[i],frame.clouds[i],label+" pod full-step cloud origin")
			var sounds:Array=arena.events.filter(func(e:Dictionary)->bool:return e.kind=="bomb_beep")
			expect(sounds.size()==frame.audio.size(),label+" source arming/beep audio count")
			for i in mini(sounds.size(),frame.audio.size()):
				near(float(sounds[i].data.get("volume",1)),float(frame.audio[i].get("volume",1)),label+" source beep volume")
				near(float(sounds[i].data.get("pitch",1)),float(frame.audio[i].get("pitch",1)),label+" source beep pitch")
			index+=1
	print("Source throwables: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
