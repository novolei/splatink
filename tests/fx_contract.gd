extends SceneTree

const Fx = preload("res://scripts/fx/ink_fx.gd")
const Actor = preload("res://scripts/game/ink_actor.gd")
const Weapons = preload("res://scripts/game/ink_weapons.gd")

class NetworkStub:
	extends Node
	var active: bool = false

class BossStub:
	extends Node3D
	var dead:bool=false
	var clock:float=0
	var _hazards:Array[Dictionary]=[]
	var _visual_hazards:Array[Dictionary]=[]
	var move_id:String=""
	var move_phase:String=""
	var move_time:float=0
	var _move_params:Dictionary={}
	var _timing:Array=[]

class Arena:
	extends Node3D
	var team_colors: Array = [Color("ff8a14"),Color("2f5bff")]
	var settings: Dictionary = {"quality":"high","cameraShake":1.0}
	var state: String = "playing"
	var time_left: float = 180.0
	var camera: Camera3D
	var network: Node
	var local_player
	var projectiles
	var stage = null
	var boss = null
	var paint: Array = []
	var actors: Array = []
	func cast(from: Vector3,to: Vector3,_exclude: Array = [],_mask: int = 1) -> Dictionary:
		if from.y>=0 and to.y<0:
			return {"position":from.lerp(to,from.y/(from.y-to.y)),"normal":Vector3.UP}
		return {}
	func sample_ink(_point: Vector3,_normal: Vector3 = Vector3.UP) -> int:return -1
	func paint_splat(point: Vector3,normal: Vector3,radius: float,team: int,extra: Dictionary = {}) -> float:
		paint.append({"point":point,"normal":normal,"radius":radius,"team":team,"extra":extra})
		return radius*radius
	func notify_event(_kind: String,_data: Dictionary) -> void:pass

var failures: Array[String] = []
var checks: int = 0
var arena: Arena
var fx

func _initialize() -> void:call_deferred("run_contract")

func expect(condition: bool,description: String) -> void:
	checks+=1
	if not condition:
		failures.append(description)
		push_error(description)

func near(actual: float,expected: float,description: String,tolerance: float = .001) -> void:
	expect(absf(actual-expected)<tolerance,"%s: got %.6f, expected %.6f" % [description,actual,expected])

func finite_pool(pool) -> bool:
	for i in range(pool.multimesh.visible_instance_count):
		var transform:Transform3D=pool.multimesh.get_instance_transform(i)
		if not transform.is_finite():return false
	return true

func run_contract() -> void:
	arena=Arena.new()
	root.add_child(arena)
	arena.network=NetworkStub.new()
	arena.add_child(arena.network)
	arena.camera=Camera3D.new()
	arena.add_child(arena.camera)
	arena.camera.position=Vector3(0,5,-8)
	arena.camera.look_at(Vector3.ZERO)
	arena.camera.make_current()
	arena.local_player=Actor.new()
	arena.add_child(arena.local_player)
	arena.local_player.match_node=arena
	arena.local_player.is_local=true
	arena.local_player.reset_weapon()
	arena.actors.append(arena.local_player)
	arena.projectiles=Weapons.new()
	arena.add_child(arena.projectiles)
	arena.projectiles.configure(arena)
	fx=Fx.new()
	arena.add_child(fx)
	fx.configure(arena)
	await process_frame
	expect(fx.drops.capacity==2048,"High quality fixed drop capacity")
	expect(fx.rounds.multimesh.instance_count==700,"Source projectile instance capacity 700")
	expect(fx.screen.lens.MAX_PARTS==220,"Source lens capacity 220")
	for i in range(3000):fx.drops.drop(Vector3(0,1,0),Vector3.UP,arena.team_colors[0],.08,2.0)
	expect(fx.drops.alive.size()==2048,"Source drop replacement keeps capacity bounded")
	fx.drops.update(.01,arena.camera)
	expect(finite_pool(fx.drops),"All drop transforms finite at capacity")
	fx.clear()
	expect(fx.drops.alive.is_empty() and fx.drops._free.size()==2048,"Drop clear restores all reusable slots")
	for i in range(500):
		fx.rings.ring(Vector3.ZERO,Vector3.ZERO,Color.WHITE)
		fx.sheets.sheet(Vector3.ZERO,Vector3.ZERO,Color.WHITE,.1,1.0)
		fx.beams.line(Vector3.ZERO,Vector3.UP,Color.WHITE)
	expect(fx.rings._rings.size()==160,"Ring pool capacity remains bounded")
	expect(fx.sheets._sheets.size()==64,"Liquid sheet pool capacity remains bounded")
	expect(fx.beams._beams.size()==96,"Beam pool capacity remains bounded")
	fx.rings.update(.01)
	fx.sheets.update(.01)
	fx.beams.update(.01)
	expect(finite_pool(fx.rings) and finite_pool(fx.sheets) and finite_pool(fx.beams),"Zero-normal recipes produce finite transforms")
	for i in range(1500):
		fx.puffs.sprite(Vector3.ONE,Vector3.UP,Color.WHITE,.1,.2,1)
		fx.glows.sprite(Vector3.ONE,Vector3.UP,Color.WHITE,.1,.2,1)
	expect(fx.puffs._active.size()==384 and fx.glows._active.size()==768,"Source sprite replacement keeps both capacities bounded")
	fx.puffs.update(.01,arena.camera)
	fx.glows.update(.01,arena.camera)
	expect(finite_pool(fx.puffs) and finite_pool(fx.glows),"Sprite motion remains finite at capacity")
	fx.clear()
	fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,arena.team_colors[0],.08,1,1,1,1,0,true)
	fx.drops.update(.05,arena.camera)
	expect(arena.paint.size()==1,"Offline paint droplet leaves real turf")
	near(arena.paint[0].radius,.192,"Offline source droplet radius size times 2.4")
	expect(not bool(arena.paint[0].extra.get("cosmetic",false)),"Offline F_PAINT reaches CPU turf coverage")
	fx.clear()
	arena.paint.clear()
	arena.network.active=true
	fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,arena.team_colors[0],.08,1,1,1,1,0,true)
	fx.drops.update(.05,arena.camera)
	expect(arena.paint.is_empty(),"Online cosmetic paint drops cannot alter replicated turf")
	fx.clear()
	fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,arena.team_colors[0],.04,1)
	fx.drops.update(.05,arena.camera)
	expect(arena.paint.size()==1 and bool(arena.paint[0].extra.get("cosmetic",false)),"Ordinary ink bead lands as GPU speck")
	near(arena.paint[0].radius,.068,"Speck source radius times 1.7")
	fx.clear()
	arena.paint.clear()
	fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,Color(.66,.86,.95),.08,1,1,1,1,0,true)
	fx.drops.update(.05,arena.camera)
	expect(arena.paint.is_empty(),"Water and foam never acquire an ink team")
	fx.clear()
	fx.set_quality({"quality":"low"})
	expect(fx.max_drops==512 and fx.drops.collision_budget==8,"Low quality limits live drops and collision work")
	for i in range(1500):fx._drop(Vector3.ONE,Vector3.UP,arena.team_colors[0],.03)
	expect(fx.drops.alive.size()==512,"Facade honors soft mobile particle capacity")
	fx.clear()
	fx.set_quality({"quality":"high"})
	fx.on_event("damage",{"victim":arena.local_player,"attacker":arena.local_player,"amount":1.0,"pos":Vector3(0,1,0)})
	expect(fx.drops.alive.is_empty(),"Continuous damage updates screen state without inventing source confirmed-hit droplets")
	fx.on_event("hit",{"victim":arena.local_player,"attacker":arena.local_player,"damage":60.0,"killed":false,"pos":Vector3(0,1,0)})
	expect(fx.drops.alive.size()==14 and fx.sheets._sheets.size()==1,"Source confirmed sixty-damage hit emits fourteen directional beads and one liquid sheet")
	expect(fx.glows._active.size()==1 and fx.puffs._active.size()==1,"Source body hit flash and mist each occur once per hit")
	fx.clear()
	for kind in ["weapon:shot","weapon:flick","weapon:beam","impact:shot","explosion","special:slam","special_activate","squid_in","squid_out","actor:footstep","actor:land","actor:jump","actor:ledgepop","weapon:dodge","charger_full","splatling_ready","damage","hit","splatted","respawn","superjump","superjump:land","special_ready","empty_click","boss_slam","crablet_pop","boss_crash"]:
		fx.on_event(kind,{"actor":arena.local_player,"victim":arena.local_player,"attacker":arena.local_player,"pos":Vector3(0,1,0),"from":Vector3(0,1,0),"to":Vector3(0,1,5),"phase":"flight","team":0,"special":"slam","cause":"weapon","amount":40,"damage":40,"normal":Vector3.UP,"dir":Vector3(0,0,1)})
	fx.update(1.0/60.0,arena.actors)
	expect(fx.drops.alive.size()<=fx.max_drops,"All public events preserve particle bounds")
	expect(finite_pool(fx.drops) and finite_pool(fx.sheets) and finite_pool(fx.rings) and finite_pool(fx.beams),"All public recipes have finite transforms")
	fx.clear()
	for i in range(400):fx.screen.lens.splat(0,Vector2(.05,.9),.08)
	expect(fx.screen.lens.parts.size()<=220,"Lens splats recycle weakest records at capacity")
	fx.screen.lens.update(.05)
	var lens_finite:bool=true
	for i in range(fx.screen.lens.mesh.multimesh.visible_instance_count):
		if not fx.screen.lens.mesh.multimesh.get_instance_transform_2d(i).is_finite():lens_finite=false
	expect(lens_finite,"Lens slides/trails remain finite under recycle pressure")
	fx.clear()
	expect(fx.screen.lens.parts.is_empty(),"Clear removes lens field")
	fx.screen.s.floodMode="in"
	fx.screen._sim_flood(.24)
	near(float(fx.screen.s.flood),1.0,"Source splat flood reaches full cover at .24 seconds")
	fx.screen._sim_flood(1.06)
	near(float(fx.screen.s.flood),.17,"Source death flood recedes to 17 percent frame")
	fx.screen.s.floodMode="reveal"
	fx.screen.s.floodT=0.0
	fx.screen._sim_flood(.87)
	expect(fx.screen.s.floodMode=="" and float(fx.screen.s.flood)==0,"Respawn iris completes at .86 seconds")
	fx.clear()
	var empty:bool=true
	for pool in [fx.drops,fx.rounds,fx.rings,fx.sheets,fx.puffs,fx.glows,fx.beams]:
		if pool.multimesh.visible_instance_count!=0:empty=false
	expect(empty and fx._schedule.is_empty() and fx._actor_state.is_empty(),"Clear retires every render path and scheduled recipe")
	fx.boss_pool.ink(Vector3(0,2,0),1000,Vector3.UP,3,.4,.1,0)
	fx.boss_pool.steam(Vector3.ZERO,500,Vector3.UP,2)
	expect(fx.boss_pool.ink_count==320 and fx.boss_pool.steam_count==140,"Source Boss blob and steam pools recycle at320/140 capacity")
	fx.boss_pool.update(.016,arena.camera)
	expect(finite_pool(fx.boss_pool.ink_mesh) and finite_pool(fx.boss_pool.steam_mesh),"Source Boss blob/steam transforms stay finite under recycling")
	fx.clear();arena.paint.clear()
	fx.boss_pool.ink(Vector3(0,.01,0),1,Vector3.DOWN,1,0,.1,0,3)
	fx.boss_pool.update(.1,arena.camera)
	expect(fx.boss_pool._splat[0]==1 and arena.paint.is_empty(),"Boss model droplets land on their fixed plane without gameplay paint or world queries")
	near(fx.boss_pool._p[0].y,.02,"Source Boss blob ground offset")
	fx.clear();fx.on_event("boss:fx",{"name":"burst","pos":Vector3.ZERO})
	expect(fx.boss_pool.ink_count==90 and fx.boss_pool.steam_count==14,"Source death burst recipe emits90 glossy blobs and14 steam puffs")
	fx.clear();fx.boss_pool.geyser(Vector3(0,4.2,0));fx.boss_pool.update(.2,arena.camera)
	expect(fx.boss_pool.ink_count>0 and fx.boss_pool.steam_count>0,"Source death geyser emits both continuous pooled paths")
	fx.clear()
	expect(fx.boss_pool.ink_mesh.multimesh.visible_instance_count==0 and fx.boss_pool.steam_mesh.multimesh.visible_instance_count==0,"Boss FX clear retires both pools and geyser")
	var hazard_visuals=preload("res://scripts/fx/boss_hazard_visuals.gd")
	var reach:PackedFloat32Array=[];reach.resize(96);reach.fill(19);reach[0]=3.5
	var ring_mesh:ArrayMesh=hazard_visuals.ring_mesh(reach)
	var ring_arrays:Array=ring_mesh.surface_get_arrays(0)
	expect(ring_arrays[Mesh.ARRAY_VERTEX].size()==384 and ring_arrays[Mesh.ARRAY_INDEX].size()==576,"Source shockwave uses96 headings,384 vertices and576 indices")
	near(ring_arrays[Mesh.ARRAY_CUSTOM0][2],3.5,"Source GPU shockwave encodes per-heading floor clipping")
	var visual:=MeshInstance3D.new();arena.add_child(visual)
	hazard_visuals.configure_mesh(visual,"ring",{"reach":Array(reach)},arena.team_colors[1])
	visual.material_override.set_shader_parameter("uR",8.0)
	var packet:Dictionary=hazard_visuals.describe(visual)
	var proxy:=MeshInstance3D.new();arena.add_child(proxy)
	hazard_visuals.apply_description(proxy,packet,arena.team_colors[1])
	near(proxy.material_override.get_shader_parameter("uR"),8.0,"Source hazard LAN description retains displayed radius and GPU uniforms")
	expect(proxy.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]==ring_arrays[Mesh.ARRAY_CUSTOM0],"Source hazard LAN proxy retains exact floor reach geometry")
	var boss:=BossStub.new();arena.add_child(boss);arena.boss=boss
	boss._visual_hazards.append({"kind":"ring","pos":Vector3.ZERO,"display_radius":2.4,"reach":reach})
	fx._boss_hazard_effects()
	expect(fx.drops.alive.size()==5,"Source displayed shockwave throws five harmless drops from the reachable rim")
	fx.clear();reach.fill(1.0);boss._visual_hazards[0].reach=reach;fx._boss_hazard_effects()
	expect(fx.drops.alive.is_empty(),"Clipped source shockwave headings cannot spray beyond their floor")
	arena.boss=null;fx.clear()
	arena.local_player.climbing=true;arena.local_player.wall_normal=Vector3.LEFT
	fx.on_event("actor:climb",{"actor":arena.local_player,"on":true})
	expect(fx.drops.alive.size()==3,"Source wall attachment emits three harmless sliding droplets")
	expect(fx.rings._rings.size()==1,"Source wall attachment emits one wall-oriented ink ripple")
	fx.clear();fx.on_event("actor:climb",{"actor":arena.local_player,"on":false})
	expect(fx.drops.alive.is_empty() and fx.rings._rings.is_empty(),"Source climb detachment cannot replay attachment splashes")
	arena.local_player.climbing=false
	print("FX source contract: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
