extends SceneTree

const DropPool=preload("res://scripts/fx/drop_pool.gd")
class SourcePool:
	extends InkDropPool
	var random_values:Array=[]
	var random_index:int=0
	func _random()->float:
		var value:float=random_values[random_index];random_index+=1;return value
class Arena:
	extends Node3D
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
	var network=null
	var floor_y:float=-INF
	func cast(a:Vector3,b:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:
		if a.y>=floor_y and b.y<floor_y:return {"position":a.lerp(b,(a.y-floor_y)/(a.y-b.y)),"normal":Vector3.UP}
		return {}
	func paint_splat(_p:Vector3,_n:Vector3,_r:float,_t:int,_options:Dictionary={})->float:return 0

var checks:int=0
var failures:Array[String]=[]
var landings:Array=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<20:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.000005)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func vector(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)
func _land(pool,p:Vector3,n:Vector3,col:Color,size:float,_paint:bool,water:bool)->void:
	landings.append({"pos":p,"normal":n,"color":col,"size":size,"flags":int(pool.get("landing_flags")),"water":water})
func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fx_drops.json"))
	var arena:=Arena.new();root.add_child(arena)
	var camera:=Camera3D.new();arena.add_child(camera)
	for trace in data.traces:
		var pool:=SourcePool.new();arena.add_child(pool);pool.initialize(int(trace.capacity));pool.game=arena if trace.collider is Dictionary else null;pool.capture_render_packets=true
		pool.landed.connect(func(p:Vector3,n:Vector3,c:Color,s:float,paint:bool,water:bool):_land(pool,p,n,c,s,paint,water))
		arena.floor_y=float(trace.collider.floor) if trace.collider is Dictionary else -INF
		for operation in trace.operations:
			var s:Dictionary=operation.input;pool.random_values=operation.random;pool.random_index=0
			pool.call("drop",vec(s.pos),vec(s.vel),Color(s.color[0],s.color[1],s.color[2]),float(s.size),float(s.life),float(s.gravity),float(s.stretch),0.0 if (int(s.flags)&16)!=0 else 1.0,0.0,bool(int(s.flags)&1),true,int(s.flags))
			expect(pool.random_index==pool.random_values.size(),"Original drop seed consumes one source random value")
		var frame_index:int=0
		for frame in trace.frames:
			landings.clear();pool.update(PackedByteArray(frame.dt_f64).decode_double(0),camera)
			var label:String="%s f%d"%[trace.name,frame_index]
			expect(pool.alive.size()==int(frame.count),label+" source expiry/landing count")
			expect(pool.alive.size()+pool._free.size()==pool.capacity,label+" fixed allocation retained")
			near(float(pool.get("collision_checks")),float(frame.checks),label+" no-collide flag and contact budget")
			for i in mini(pool.alive.size(),frame.records.size()):
				var id:int=pool.alive[i];var r:Dictionary=frame.records[i]
				vector(pool._position[id],r.p,label+" source position")
				vector(pool._velocity[id],r.v,label+" source velocity")
				vector(pool._probe_position[id],r.probe,label+" last checked point")
				vector(Vector3(pool._colors[id].r,pool._colors[id].g,pool._colors[id].b),r.c,label+" source color")
				for entry in [["_radius",0],["_age",1],["_life",2],["_gravity",3],["_stretch",4],["_seed",5],["_flags",7]]:
					near(float(pool.get(entry[0])[id]),float(r.a[entry[1]]),label+" source "+str(entry[0]))
				var packet:Dictionary=pool.render_packets[i]
				near(float(packet.radius),float(r.position_radius[3]),label+" original grow and final .12s radius fade")
				near(float(packet.stretch),float(r.velocity_stretch[3]),label+" original speed stretch and 38Hz wobble")
				near(float(packet.gloss),float(r.color_gloss[3]),label+" matte material flag")
				expect((packet.transform as Transform3D).is_finite(),label+" finite submitted geometry")
			expect(landings.size()==frame.landings.size(),label+" source landing callback count")
			for i in mini(landings.size(),frame.landings.size()):
				var got:Dictionary=landings[i];var wanted:Dictionary=frame.landings[i]
				vector(got.pos,wanted.pos,label+" interpolated contact point")
				vector(got.normal,wanted.normal,label+" contact normal")
				near(got.size,wanted.size,label+" contact size")
				expect(got.flags==int(wanted.flags) and got.water==bool(wanted.water),label+" contact precedence and flags")
			frame_index+=1
		pool.clear();expect(pool.alive.is_empty() and pool._free.size()==pool.capacity,"Clear restores all drop slots")
		pool.free()
	print("Source drop contract: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
