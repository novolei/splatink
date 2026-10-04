extends SceneTree

const Nav=preload("res://scripts/game/ink_boss_nav.gd")
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:
	call_deferred("run_contract")

func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures.append(label);push_error(label)

func near(actual:float,expected:float,label:String)->void:
	expect(absf(actual-expected)<.0001,"%s: got %.6f expected %.6f"%[label,actual,expected])

func run_contract()->void:
	for stage in ["tidewater","kelpline","halyard","cargo"]:
		var nav:=Nav.new()
		expect(nav.configure(stage),"%s original baked fields load"%stage)
		expect(nav.fields.size()==nav.nx*nav.nz*5,"%s source geometry field dimensions"%stage)
		near(nav.area,float(nav.plan_ids.size())*.25,"%s original home-ground area"%stage)
		for probe in nav.metadata.probes:
			var x:float=float(probe.x);var z:float=float(probe.z)
			var label:String="%s source cell%d"%[stage,int(probe.i)]
			expect(nav.cell(x,z)==int(probe.i),label+" world-grid round trip")
			expect(nav.kind_at(x,z)==int(probe.kind),label+" floor/wall/drop/pad classification")
			near(nav.floor_at(x,z),float(probe.floor),label+" curb height policy")
			near(nav.wall_clear(x,z),float(probe.wall),label+" wall clearance")
			near(nav.floor_clear(x,z),float(probe.drop),label+" edge clearance")
			expect(nav.is_plan(x,z)==bool(probe.plan),label+" home component")
			expect(nav.pose_ok(x,z,float(nav.metadata.yaw))==bool(probe.pose),label+" full footprint collision")
			expect(nav.turn_ok(x,z,float(nav.metadata.yaw))==bool(probe.turn),label+" rotating claws clearance")
			var lane:Dictionary=nav.cast(x,z,float(nav.metadata.yaw),34)
			near(float(lane.dist),float(probe.lane.dist),label+" charge lane length")
			expect(bool(lane.wall)==bool(probe.lane.wall),label+" wall-bonk distinction")
		for fixture in nav.metadata.paths:
			var from:Vector2=Vector2(float(fixture.start[0]),float(fixture.start[1]))
			var to:Vector2=Vector2(float(fixture.end[0]),float(fixture.end[1]))
			var route:PackedVector2Array=nav.find_path(from,to)
			var expected:Array=fixture.path
			expect(route.size()==expected.size(),"%s weighted A* exact source string-pulled waypoint count"%stage)
			for index in mini(route.size(),expected.size()):
				expect(route[index].distance_to(Vector2(float(expected[index][0]),float(expected[index][1])))<.0001,"%s exact source A* waypoint%d"%[stage,index])
				if index>0:expect(nav.line_ok(route[index-1],route[index]),"%s source path remains on body-safe floor"%stage)
		var spawn:Array=nav.metadata.spawn
		expect(nav.turn_ok(float(spawn[0]),float(spawn[2]),float(nav.metadata.yaw)),"%s original spawn permits its starting body heading"%stage)
		expect(nav.kind_at(-10000,-10000)==2 and nav.wall_clear(-10000,-10000)==0,"%s off-stage cells cannot support a Boss"%stage)
	print("Boss navigation source contract: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
