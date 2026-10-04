extends SceneTree
## Run with a real renderer. Dummy RenderingServer readback cannot validate submission.
const DropPool=preload("res://scripts/fx/drop_pool.gd")
const STRIDE:int=20
const STATE_FIELDS:Array[String]=["_position","_velocity","_age","_life","_radius","_gravity","_stretch","_gloss","_growth","_seed","_flags","_colors","_probe_position","_paint"]

class SourcePool:
	extends InkDropPool
	var random_values:Array=[]
	var random_index:int=0
	func _random()->float:
		var index:int=random_index;random_index+=1
		return float(random_values[index]) if index<random_values.size() else .25

class Arena:
	extends Node3D
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
	var network=null
	var floor_y:float=-INF
	var casts:Array=[]
	var paints:Array=[]
	var landings:Array=[]
	var append_bead:bool=false
	func cast(a:Vector3,b:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:
		casts.append([a,b])
		if a.y>=floor_y and b.y<floor_y:return {"position":a.lerp(b,(a.y-floor_y)/(a.y-b.y)),"normal":Vector3.UP}
		return {}
	func paint_splat(p:Vector3,n:Vector3,r:float,t:int,options:Dictionary={})->float:
		paints.append([p,n,r,t,options.duplicate(true)]);return 0.0
	func on_land(pool:InkDropPool,p:Vector3,n:Vector3,c:Color,r:float,paint:bool,water:bool)->void:
		landings.append([p,n,c,r,paint,water,pool.landing_flags])
		if append_bead:
			pool.drop(p+n*.02,Vector3(1,2,-3),c,.015,.7,.2,1,0,0,false,true,InkDropPool.F_NOCOL)
	func reset_calls()->void:casts.clear();paints.clear();landings.clear()

var checks:int=0
var failures:Array[String]=[]
var timings:Array=[]
var source_frames:int=0
func _initialize()->void:call_deferred("run_contract")
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		if failures.size()<16:push_error(label)
		failures.append(label)
func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func make_arena()->Arena:
	var arena:=Arena.new();root.add_child(arena);return arena
func make_pool(arena:Arena,capacity:int,batch:bool)->SourcePool:
	var pool:=SourcePool.new();arena.add_child(pool);pool.initialize(capacity)
	# Explicitly exercise both paths even when the caller uses --fx-drop-batch.
	pool.batch_submission_enabled=batch;pool.profile_updates=true;pool.capture_render_packets=true
	pool.landed.connect(func(p:Vector3,n:Vector3,c:Color,r:float,paint:bool,water:bool):arena.on_land(pool,p,n,c,r,paint,water))
	return pool
func camera_for(arena:Arena)->Camera3D:
	var camera:=Camera3D.new();arena.add_child(camera);camera.position=Vector3(7,6,-9)
	camera.look_at(Vector3(0,1,0));return camera
func check_state(a:SourcePool,b:SourcePool,label:String)->void:
	expect(a.alive==b.alive and a._free==b._free,label+" exact active/free slot ordering")
	expect(a._recycle==b._recycle and a.random_index==b.random_index,label+" recycling and RNG consumption")
	for field:String in STATE_FIELDS:expect(a.get(field)==b.get(field),label+" bit-identical CPU "+field)
	expect(a.render_packets==b.render_packets,label+" diagnostic packets unchanged")
	expect(a.collision_checks==b.collision_checks and a.collision_checks<=a.collision_budget,label+" shared ray quota")
	for pool:SourcePool in [a,b]:
		expect(pool._batch_buffer.size()==pool.capacity*STRIDE,label+" fixed-capacity scratch buffer")
		for span:String in ["integrate_us","collision_land_us","draw_submit_us"]:expect(int(pool.profile_update[span])>=0,label+" finite nonnegative profile "+span)
	expect(int(a.profile_update.submission_calls)==a.alive.size()*3,label+" legacy native setter count")
	expect(int(b.profile_update.submission_calls)==(0 if b.alive.is_empty() else 1),label+" one bulk upload when visible")
func check_buffers(a:SourcePool,b:SourcePool,label:String)->bool:
	var legacy:PackedFloat32Array=a.multimesh.buffer
	var bulk:PackedFloat32Array=b.multimesh.buffer
	var size:int=a.capacity*STRIDE
	expect(legacy.size()==size and bulk.size()==size,label+" real renderer exposes full native instance buffers")
	if legacy.size()!=size or bulk.size()!=size:
		push_error("DropBatch requires a real rendering backend; do not accept dummy-renderer packet-only results.")
		return false
	var active_bytes:int=a.alive.size()*STRIDE*4
	expect(legacy.to_byte_array().slice(0,active_bytes)==bulk.to_byte_array().slice(0,active_bytes),label+" exact active GPU buffer bytes including row-major transform/linear RGBA/custom")
	expect(a.multimesh.visible_instance_count==b.multimesh.visible_instance_count,label+" identical visibility count")
	for i:int in a.alive.size():
		expect(a.multimesh.get_instance_transform(i)==b.multimesh.get_instance_transform(i),label+" decoded native transform")
		expect(a.multimesh.get_instance_color(i)==b.multimesh.get_instance_color(i),label+" decoded native raw linear color")
		expect(a.multimesh.get_instance_custom_data(i)==b.multimesh.get_instance_custom_data(i),label+" decoded native custom data")
	return true
func apply_operation(pool:SourcePool,operation:Dictionary)->void:
	var s:Dictionary=operation.input;pool.random_values=operation.random;pool.random_index=0
	pool.drop(vec(s.pos),vec(s.vel),Color(s.color[0],s.color[1],s.color[2]),float(s.size),float(s.life),float(s.gravity),float(s.stretch),0.0 if (int(s.flags)&16)!=0 else 1.0,0.0,bool(int(s.flags)&1),true,int(s.flags))
	expect(pool.random_index==pool.random_values.size(),"Original input consumes its unchanged seed sequence")
func source_trajectory_pairs()->bool:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fx_drops.json"))
	for trace:Dictionary in data.traces:
		var aa:=make_arena();var ab:=make_arena()
		var ca:=camera_for(aa);var cb:=camera_for(ab)
		var a:=make_pool(aa,int(trace.capacity),false);var b:=make_pool(ab,int(trace.capacity),true)
		aa.floor_y=float(trace.collider.floor) if trace.collider is Dictionary else -INF;ab.floor_y=aa.floor_y
		a.game=aa if trace.collider is Dictionary else null;b.game=ab if trace.collider is Dictionary else null
		for operation:Dictionary in trace.operations:apply_operation(a,operation);apply_operation(b,operation)
		var frame_index:int=0
		for frame:Dictionary in trace.frames:
			aa.reset_calls();ab.reset_calls()
			# Camera basis changes expose matrix transpose and projection errors.
			ca.rotation+=Vector3(.0003,.0017,.0001);cb.transform=ca.transform
			var dt:float=PackedByteArray(frame.dt_f64).decode_double(0)
			a.update(dt,ca);b.update(dt,cb)
			var label:String="%s f%d"%[trace.name,frame_index]
			check_state(a,b,label)
			expect(aa.casts==ab.casts and aa.paints==ab.paints and aa.landings==ab.landings,label+" unchanged contact/paint/event order")
			if not check_buffers(a,b,label):aa.free();ab.free();return false
			frame_index+=1;source_frames+=1
		a.clear();b.clear();expect(a.alive.is_empty() and b.alive.is_empty() and a._free==b._free,"Both clears retire the same slots")
		expect(a._batch_buffer.size()==int(trace.capacity)*STRIDE and b._batch_buffer.size()==int(trace.capacity)*STRIDE,"Clear retains preallocated buffers")
		aa.free();ab.free()
	return true
func callback_and_budget_pairs()->bool:
	var aa:=make_arena();var ab:=make_arena()
	var ca:=camera_for(aa);var cb:=camera_for(ab)
	var a:=make_pool(aa,64,false);var b:=make_pool(ab,64,true)
	aa.floor_y=0;ab.floor_y=0;aa.append_bead=true;ab.append_bead=true
	a.game=aa;b.game=ab;a.collision_budget=3;b.collision_budget=3
	for pool:SourcePool in [a,b]:
		for i:int in 24:pool.drop(Vector3(i*.02,.1,0),Vector3(0,-5,0),Color("ff8a14"),.03,1,1,1,1,0,true)
	for frame_index:int in 12:
		aa.reset_calls();ab.reset_calls();a.update(.025,ca);b.update(.025,cb)
		check_state(a,b,"callback f%d"%frame_index)
		expect(aa.casts==ab.casts and aa.paints==ab.paints and aa.landings==ab.landings,"Callback-appended beads retain same-iteration traversal and native ray quota")
		if not check_buffers(a,b,"callback f%d"%frame_index):aa.free();ab.free();return false
	# Toggling submission affects neither authoritative state nor visible bytes.
	a.batch_submission_enabled=true;b.batch_submission_enabled=false
	a.update(0,ca);b.update(0,cb)
	expect(a.alive==b.alive and a._position==b._position,"Live path toggle keeps simulation state")
	var same:bool=check_buffers(a,b,"live toggle")
	aa.free();ab.free();return same
func quantile(samples:Array,index:float)->int:
	var sorted:Array=samples.duplicate();sorted.sort();return int(sorted[mini(sorted.size()-1,floori(sorted.size()*index))])
func benchmark_submission()->void:
	var arena:=make_arena();var camera:=camera_for(arena);camera.make_current()
	var a:=make_pool(arena,2048,false);var b:=make_pool(arena,2048,true)
	a.capture_render_packets=false;b.capture_render_packets=false
	for count:int in [0,64,564,1167,1386,2048]:
		a.clear();b.clear()
		for pool:SourcePool in [a,b]:
			for i:int in count:
				pool.drop(Vector3((i%32)*.11,(i/32)*.04,0),Vector3((i%7)-3,2,(i%11)-5),Color(.3+(i%11)*.25,.2+(i%3)*.07,.7,float(i%5)/4.0),.04+(i%9)*.002,10000,1,1.3,1,0,false,true,DropPool.F_NOCOL)
			pool.update(1.0/60.0,camera)
		expect(check_buffers(a,b,"benchmark count%d"%count),"Benchmark begins from identical native buffers")
		var build:Array=[[],[]];var total:Array=[[],[]]
		for repetition:int in 48:
			# Alternate first path; both submissions share the same frozen CPU state.
			for order:int in 2:
				var mode:int=(repetition+order)%2;var pool:SourcePool=a if mode==0 else b
				var started:int=Time.get_ticks_usec();pool.update(0,camera);var elapsed:int=Time.get_ticks_usec()-started
				if repetition>=8:build[mode].append(int(pool.profile_update.draw_submit_us));total[mode].append(elapsed)
			await process_frame
		for mode:int in 2:
			timings.append({"count":count,"capacity":2048,"batch":mode==1,"samples":build[mode].size(),"draw_submit_median_us":quantile(build[mode],.5),"draw_submit_p95_us":quantile(build[mode],.95),"update_median_us":quantile(total[mode],.5),"update_p95_us":quantile(total[mode],.95),"submission_calls":(0 if count==0 else 1) if mode==1 else count*3})
		expect(check_buffers(a,b,"benchmark final count%d"%count),"Benchmark keeps final packets identical")
	arena.free()
func run_contract()->void:
	var fresh:=DropPool.new()
	expect(not fresh.batch_submission_enabled,"Production default remains legacy setters")
	fresh.free()
	if not source_trajectory_pairs():finish();return
	if not callback_and_budget_pairs():finish();return
	await benchmark_submission()
	finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures.size(),"source_frames":source_frames,"display_server":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"scope":"Identical frozen CPU snapshots; alternating setter/bulk order, 8 warmups and 40 samples. Real native MultiMesh buffer readback; no full-game FPS claim.","timings":timings}
	var file:=FileAccess.open("res://shots/drop_batch_benchmark.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Drop batch contract: %d checks, %d failures"%[checks,failures.size()]);print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
