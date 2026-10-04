extends SceneTree
const Queries=preload("res://scripts/game/ink_level_queries.gd")
class LevelStub:
	extends Node
	var blocks:Array=[]
	var faces:Array=[]
	var bounds:Dictionary={}
	var grid:PackedByteArray=[]
	var dead:PackedByteArray=[]
var checks:int=0
var failures:Array[String]=[]
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func v(array:Array)->Vector3:return Vector3(array[0],array[1],array[2])
func run()->void:
	for stage in ["tidewater","kelpline","halyard","cargo"]:
		var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json"%stage))
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/level_queries/%s.json"%stage))
		var level:=LevelStub.new();root.add_child(level)
		level.blocks=record.blocks;level.faces=record.faces;level.bounds=record.layout.bounds
		for block in level.blocks:block.center=v(block.center);block.half=v(block.half);block.axes=block.axes.map(func(axis):return v(axis))
		for face in level.faces:face.origin=v(face.origin);face.u=v(face.u);face.v=v(face.v);face.n=v(face.n)
		level.grid.resize(int(record.grid_length))
		for i in level.grid.size():level.grid[i]=(i*13+(i>>3))%3
		var file=FileAccess.open("res://assets/world/%s.bin"%stage,FileAccess.READ);file.seek(int(record.dead.offset));level.dead=file.get_buffer(int(record.dead.length));file.close()
		var queries:=Queries.new();queries.configure(level)
		expect(level.grid.size()==int(source.grid_length),stage+" authoritative CPU grid has source cell layout")
		for sample in source.queries:
			var point:Vector3=v(sample.pos);var radius:float=float(sample.radius)
			expect(queries.query_blocks(point.x-radius,point.z-radius,point.x+radius,point.z+radius)==PackedInt32Array(sample.blocks),stage+" source broadphase block order "+str(point))
			expect(absf(queries.ground_height(point.x,point.z,point.y+1.2)-float(sample.ground))<.00001,stage+" source floor height "+str(point))
			for team in 2:
				var stats:Dictionary=queries.region_stats(point,radius,team);var expected:Dictionary=sample.stats[team]
				expect(int(stats.n)==int(expected.n),stage+" source live turf sample count "+str(point)+" r"+str(radius))
				for key in ["own","enemy","empty"]:expect(absf(float(stats[key])-float(expected[key]))<.000001,stage+" source turf fraction "+key)
		level.queue_free()
	print("Level Queries source contract: %s checks, %s failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
