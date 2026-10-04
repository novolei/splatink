extends SceneTree
const Physics=preload("res://scripts/game/ink_actor_physics.gd")
class LevelStub:
	extends Node
	var blocks:Array=[]
	var faces:Array=[]
	var bounds:Dictionary={}
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func vec(array:Array) -> Vector3:return Vector3(array[0],array[1],array[2])
func expect(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		if failures.size()<=32:push_error(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.00015) -> void:
	expect(absf(actual-wanted)<=tolerance,label+" got "+str(actual)+" expected "+str(wanted))
func vector_near(actual:Vector3,wanted:Array,label:String,tolerance:float=.00025) -> void:
	expect(actual.distance_to(vec(wanted))<=tolerance,label+" got "+str(actual)+" expected "+str(wanted))
func check_ground(actual,source:Dictionary,label:String) -> void:
	expect(actual.hit==bool(source.hit),label+" floor support")
	if not actual.hit or not bool(source.hit):return
	near(actual.y,float(source.y),label+" support height")
	vector_near(actual.normal,source.normal,label+" exact floor normal")
	expect(actual.block==int(source.block),label+" source winning block order")
	expect(actual.face==int(source.face),label+" paint face")
	expect(actual.center==bool(source.center),label+" center-vs-ring support priority")
	expect(actual.grate==bool(source.grate),label+" grate support")
	if actual.face>=0:
		near(actual.u,float(source.u),label+" floor paint U")
		near(actual.v,float(source.v),label+" floor paint V")
func run() -> void:
	for stage in ["fixtures","tidewater","kelpline","halyard","cargo"]:
		var probes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/actor_physics/%s.json"%stage))
		var record:Dictionary=probes.geometry if stage=="fixtures" else JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json"%stage))
		var canonical_geometry:Dictionary=record.duplicate(true)
		canonical_geometry.physics_fields=probes.fields
		var level:=LevelStub.new();root.add_child(level)
		level.blocks=record.blocks;level.faces=record.faces;level.bounds=record.bounds if stage=="fixtures" else record.layout.bounds
		for block in level.blocks:block.center=vec(block.center);block.half=vec(block.half);block.axes=block.axes.map(func(axis):return vec(axis))
		for face in level.faces:face.origin=vec(face.origin);face.u=vec(face.u);face.v=vec(face.v);face.n=vec(face.n)
		var physics:=Physics.new();physics.configure(level,null,canonical_geometry)
		var index:int=0
		for probe in probes.raycasts:
			var label:String=stage+" ray"+str(index);index+=1
			var hit=physics.raycast(vec(probe.origin),vec(probe.direction),float(probe.distance),null,bool(probe.skip))
			var wanted:Dictionary=probe.wanted
			expect(hit.hit==bool(wanted.hit),label+" collision/grate policy")
			if not hit.hit or not bool(wanted.hit):continue
			near(hit.distance,float(wanted.distance),label+" original OBB slab distance")
			vector_near(hit.position,wanted.position,label+" surface point")
			vector_near(hit.normal,wanted.normal,label+" surface normal")
			expect(hit.block==int(wanted.block),label+" nearest hit block")
			expect(hit.face==int(wanted.face),label+" correct paint face")
			near(hit.u,float(wanted.u),label+" paint U");near(hit.v,float(wanted.v),label+" paint V")
		index=0
		for probe in probes.ground:
			check_ground(physics.ground_probe(vec(probe.pos),float(probe.up),float(probe.down),float(probe.foot),null,bool(probe.squid)),probe.wanted,stage+" footprint"+str(index));index+=1
		index=0
		for probe in probes.body:
			var label:String=stage+" body"+str(index);index+=1
			var pos:Vector3=vec(probe.pos)
			var contact=physics.collide_body(pos,float(probe.radius),float(probe.lift),float(probe.height),null,bool(probe.horizontal),bool(probe.squid))
			var wanted:Dictionary=probe.wanted
			vector_near(contact.position,wanted.position,label+" iterative lifted body resolution")
			for field in ["ground","wall","ceiling"]:expect(bool(contact.get(field))==bool(wanted[field]),label+" "+field+" classification")
			for field in ["ground_block","wall_block"]:expect(int(contact.get(field))==int(wanted[field]),label+" "+field+" ordering")
			vector_near(contact.ground_normal,wanted.ground_normal,label+" ground normal")
			vector_near(contact.wall_normal,wanted.wall_normal,label+" wall-slide normal")
			expect(physics.body_fits(pos,float(probe.radius),float(probe.lift),float(probe.height),bool(probe.squid))==bool(probe.fits),label+" body headroom/clearance")
		index=0
		for probe in probes.motion:
			var label:String=stage+" resolve"+str(index);index+=1
			var motion=physics.resolve(vec(probe.pos),vec(probe.velocity),bool(probe.squid),float(probe.previous_y),bool(probe.stick),bool(probe.was_grounded))
			var wanted:Dictionary=probe.wanted
			vector_near(motion.position,wanted.position,label+" source body-before-feet displacement")
			vector_near(motion.velocity,wanted.velocity,label+" source wall/ceiling/ground velocity")
			expect(motion.grounded==bool(wanted.grounded),label+" grounded status")
			near(motion.smooth_y,float(wanted.smooth_y),label+" curb/ledge visual compensation")
			expect(motion.landed==bool(wanted.landed),label+" first-contact landing hook")
			near(motion.land_speed,float(wanted.land_speed),label+" landing impact speed")
			check_ground(motion.ground,wanted.ground,label)
		for trace in probes.traces:
			var motion=Physics.Motion.new()
			motion.position=vec(trace.initial.position);motion.grounded=bool(trace.initial.grounded)
			var ground:Dictionary=trace.initial.ground
			motion.ground.hit=bool(ground.hit);motion.ground.y=float(ground.y);motion.ground.normal=vec(ground.normal);motion.ground.block=int(ground.block);motion.ground.face=int(ground.face)
			motion.ground.normal64=PackedFloat64Array(ground.normal)
			motion.ground.u=float(ground.u);motion.ground.v=float(ground.v);motion.ground.center=bool(ground.center);motion.ground.grate=bool(ground.grate)
			index=0
			for frame in trace.frames:
				var label:String=stage+" "+str(trace.name)+" frame"+str(index);index+=1
				motion.velocity=vec(frame.velocity)
				physics.integrate(motion,1.0/60.0,bool(trace.squid),bool(frame.jumped),false,vec(frame.move))
				var wanted:Dictionary=frame.wanted
				vector_near(motion.position,wanted.position,label+" continuous source trajectory",.0005)
				vector_near(motion.velocity,wanted.velocity,label+" source roof/rail/ground momentum")
				expect(motion.grounded==bool(wanted.grounded),label+" support transition")
				near(motion.smooth_y,float(wanted.smooth_y),label+" original curb/lip compensation")
				near(motion.air_time,float(wanted.air_time),label+" source airborne clock")
				expect(motion.landed==bool(wanted.landed),label+" landing fired exactly once")
				near(motion.land_speed,float(wanted.land_speed),label+" landing impact")
				near(motion.roof_time,float(wanted.roof_time),label+" roof-slide clock")
				if motion.roof_time>0:
					vector_near(motion.roof_direction,wanted.roof_direction,label+" persistent source roof slide direction")
					near(motion.roof_stall,float(wanted.roof_stall),label+" blocked roof-slide turn clock")
		level.queue_free()
	print("Actor physics source contract: %s checks, %s failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
