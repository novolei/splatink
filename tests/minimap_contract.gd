extends SceneTree

const Minimap = preload("res://scripts/game/ink_minimap.gd")

class StageStub:
	extends Node
	var stage_id: String = "tidewater"
	var grid: PackedByteArray = PackedByteArray()
	var team_colors: Array = [Color("ff8a14"),Color("2f5bff")]
	var layout: Dictionary = {"spawnPads":[[0,2.2,-39.2],[0,2.2,39.2]],"spawnBarrier":4.2}

class Arena:
	extends Node
	var state: String = "playing"
	var options: Dictionary = {"time_of_day":"day"}
	var projectiles = null

class ActorStub:
	extends Node3D
	var team_id: int = 0
	var super_jump_state: Dictionary = {"to":Vector3(5,0,-10)}

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:call_deferred("run_contract")

func expect(condition: bool,description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func run_contract() -> void:
	for id: String in ["tidewater","kelpline","halyard","cargo"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/minimap/%s.json"%id))
		expect(not data.is_empty(),"Original %s metadata exists"%id)
		expect(int(data.width)==roundi((float(data.bounds.maxX)-float(data.bounds.minX))*7.0),"%s width is original 7px per metre"%id)
		expect(int(data.height)==roundi((float(data.bounds.maxZ)-float(data.bounds.minZ))*7.0),"%s height is original 7px per metre"%id)
		for viewer: Dictionary in data.viewers:
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(viewer.projection))
			expect(bytes.size()==int(data.width)*int(data.height)*16,"%s viewer%d field has one RGBA float record per pixel"%[id,int(viewer.team)])
			var mapping: PackedFloat32Array = bytes.to_float32_array()
			var finite: bool = true
			var valid: bool = true
			var claimed: int = 0
			for offset in range(0,mapping.size(),4):
				var cell: int = roundi(mapping[offset])
				finite = finite and is_finite(mapping[offset]) and is_finite(mapping[offset+1])
				if cell < 0:
					continue
				claimed += 1
				var final_cell: int = cell+roundi(mapping[offset+2])+roundi(mapping[offset+3])
				valid = valid and final_cell<int(data.grid_length) and mapping[offset+1]>=0.0 and mapping[offset+1]<=65535.0
			expect(finite and valid,"%s viewer%d bilinear neighbours remain in the actual CPU turf grid"%[id,int(viewer.team)])
			expect(claimed==int(viewer.turf_pixels),"%s viewer%d painted top-face pixel count matches original source"%[id,int(viewer.team)])
			for theme: String in ["day","sunset"]:
				var image: Image = (load(str(viewer.bases[theme])) as Texture2D).get_image()
				expect(image!=null and image.get_width()==int(data.width) and image.get_height()==int(data.height),"%s viewer%d %s static source base dimensions"%[id,int(viewer.team),theme])
	var stage := StageStub.new()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/minimap/tidewater.json"))
	stage.grid.resize(int(metadata.grid_length))
	stage.grid.fill(0)
	get_root().add_child(stage)
	var arena := Arena.new()
	get_root().add_child(arena)
	var map := Minimap.new()
	get_root().add_child(map)
	map.configure(stage,arena,0)
	expect(map._built and map.get_texture()!=null,"Native facade builds original map viewport")
	expect(map.to_uv(Vector3(25,0,44)).is_equal_approx(Vector2.ZERO),"Team 0 original max X/Z corner is top left")
	expect(map.to_uv(Vector3(-25,0,-44)).is_equal_approx(Vector2.ONE),"Team 0 min X/Z corner is bottom right")
	var target := Vector3(6,0,-23)
	expect(map.world_at(map.to_canvas(target.x,target.z)).is_equal_approx(target),"Team 0 world projection is invertible")
	map.set_viewer_team(1)
	expect(map.to_uv(Vector3(25,0,44)).is_equal_approx(Vector2.ONE),"Team 1 original map orientation is flipped")
	expect(map.world_at(map.to_canvas(target.x,target.z)).is_equal_approx(target),"Team 1 world projection is invertible")
	expect(map.flash_time>map.FLASH_LIFE,"Viewer change never triggers freshly painted flash")
	stage.grid[100]=1
	map.update(.15)
	expect(map._snapshot[100]==1 and is_zero_approx(map.flash_time),"Native ownership upload triggers original claim flash")
	map.update(.46)
	expect(map.flash_time>map.FLASH_LIFE,"Claim flash fades after original .45 seconds")
	arena.options.time_of_day="dusk"
	map.update(0.0)
	expect(map._theme=="sunset","Dusk picks exact original sunset raster")
	var actor := ActorStub.new()
	get_root().add_child(actor)
	map.on_event("superjump",{"actor":actor,"phase":"flight","to":target})
	expect(map.effects.size()==1 and (map.effects[0].pos as Vector3).is_equal_approx(target),"Superjump marks destination rather than departure")
	map.on_event("superjump:land",{"actor":actor})
	expect(is_equal_approx(float(map.effects[0].life),.35),"Landing shortens destination marker to original .35 seconds")
	for i in 80:
		map.on_event("explosion",{"kind":"bomb","pos":Vector3(i,0,0),"team":i%2,"radius":3.1})
	expect(map.effects.size()==map.EFFECT_CAPACITY,"Transient map effects remain bounded")
	map.update(1.0)
	expect(map.effects.is_empty(),"Expired effects are reclaimed")
	arena.state="attract"
	map.on_event("respawn",{"actor":actor})
	expect(map.effects.is_empty(),"Attract mode suppresses live match effects")
	map.clear()
	expect(map.effects.is_empty() and is_zero_approx(map.time),"Minimap clear resets its live layer")
	map.set_active(false)
	var hidden_time:float=map.time
	stage.grid[100]=2
	map.update(.3)
	expect(is_equal_approx(map.time,hidden_time) and map._snapshot[100]==1,"Hidden minimap performs no live or ownership updates")
	expect(map._viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hidden minimap suspends its GPU render target")
	map.set_active(true)
	expect(map._snapshot[100]==2 and map.flash_time>map.FLASH_LIFE,"Visible map uploads current turf quietly")
	print("MINIMAP CONTRACT: %d checks, %d failures"%[checks,failures.size()])
	actor.queue_free()
	map.queue_free()
	arena.queue_free()
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
