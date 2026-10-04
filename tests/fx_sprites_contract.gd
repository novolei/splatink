extends SceneTree

const Pool=preload("res://scripts/fx/sprite_pool.gd")
class SourcePool:
	extends InkSpritePool
	var random_values:Array=[]
	var random_index:int=0
	func _random()->float:
		var result:float=random_values[random_index]
		random_index+=1
		return result

var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,message:String)->void:
	checks+=1
	if not condition:
		if failures.size()<20:push_error(message)
		failures.append(message)
func near(actual:float,wanted:float,label:String,tolerance:float=.000005)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func check_vec(actual:Vector3,wanted:Array,label:String)->void:
	for axis in 3:near(actual[axis],float(wanted[axis]),label+" axis%d"%axis)

func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fx_sprites.json"))
	var camera:=Camera3D.new();root.add_child(camera)
	for trace in data.traces:
		var p:=SourcePool.new();root.add_child(p);p.initialize(int(trace.capacity),bool(trace.additive));p.capture_render_packets=true
		expect(p.multimesh.mesh.size==Vector2.ONE,"Original sprite quad width is size, not twice size")
		for operation in trace.operations:
			var s:Dictionary=operation.input;p.random_values=operation.random;p.random_index=0
			p.sprite(vec(s.pos),vec(s.vel),Color(s.col[0],s.col[1],s.col[2]),s.start,s.end,s.life,s.alpha,s.kind,s.drag,s.buoy,s.fadeIn,s.spin,s.wobble,s.fadeOut)
			expect(p.random_index==p.random_values.size(),"%s consumes original random sequence including overflow and upright ghost"%trace.name)
		var frame_index:int=0
		for frame in trace.frames:
			p.update(float(frame.dt),camera)
			expect(p._active.size()==int(frame.n),"%s frame%d expiry swap count"%[trace.name,frame_index])
			expect(p._active.size()+p._free.size()==p.capacity,"Source expiry and overflow preserve fixed allocation")
			for i in frame.records.size():
				if i>=p._active.size():break
				var got:Dictionary=p._records[p._active[i]]
				var want:Dictionary=frame.records[i]
				var label:String="%s f%d particle%d"%[trace.name,frame_index,i]
				check_vec(got.p,want.p,label+" position")
				check_vec(got.v,want.v,label+" velocity")
				var names:Array=["start","end","age","life","alpha","rotation","spin","drag","buoyancy","kind","fade_in","seed","wobble","fade_out"]
				for field_index in names.size():near(float(got[names[field_index]]),float(want.x[field_index]),label+" "+str(names[field_index]))
				var transform:Transform3D=p.render_packets[i].transform
				check_vec(transform.origin,want.position_size,label+" rendered position")
				near(transform.basis.x.length(),float(want.position_size[3]),label+" cubic size")
				var custom:Color=p.render_packets[i].custom
				near(custom.r,float(want.misc[2]),label+" lifetime fraction")
				near(custom.g,float(want.misc[1]),label+" seed")
				near(custom.b,float(want.misc[3]),label+" puff/glow kind")
				near(custom.a,float(want.color_alpha[3]),label+" source alpha envelope")
				expect(transform.is_finite(),label+" finite")
			frame_index+=1
		p.clear();expect(p._active.is_empty() and p._free.size()==p.capacity,"Clear restores every reusable sprite slot")
		p.free()
	print("Source sprite contract: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
