extends SceneTree

const Rig = preload("res://scripts/game/ink_camera_rig.gd")

class StageStub:
	extends Node
	var bounds: Dictionary = {"minX":-25,"maxX":25,"minZ":-44,"maxZ":44}
	var layout: Dictionary = {"spawnPads":[[0,2.2,-39.2],[0,2.2,39.2]],"bounds":bounds}
	func ground_height(_x: float,_z: float,_max_y: float = 50.0) -> float:return 0.0

class Arena:
	extends Node3D
	var stage: Node
	var settings: Dictionary = {"fov":82.0,"cameraShake":1.0}
	var _yaw: float = 0.0
	var _pitch: float = -.12
	var state: String = "playing"
	var paused: bool = false
	var local_player: Node3D
	var ray_count: int = 0
	var wall_limit: float = INF
	var wall_normal: Vector3 = Vector3(0,0,1)
	func cast(from: Vector3,to: Vector3,_exclude: Array = [],_mask: int = 1) -> Dictionary:
		ray_count+=1
		var distance: float = from.distance_to(to)
		if wall_limit<distance:return {"position":from.lerp(to,wall_limit/distance),"normal":wall_normal}
		return {}

class ActorStub:
	extends CharacterBody3D
	var team_id: int = 0
	var is_local: bool = true
	var alive: bool = true
	var form: String = "kid"
	var submerged: bool = false
	var climbing: bool = false
	var super_jump_state: Dictionary = {}
	var special_active: String = ""
	var land_time: float = 99.0
	var land_speed: float = 0.0
	var charge: float = 0.0
	var weapon_id: String = "shooter"
	var firing: bool = false

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:call_deferred("run_contract")

func expect(value: bool,description: String) -> void:
	checks+=1
	if not value:
		failures.append(description)
		push_error(description)

func near(value: float,wanted: float,description: String,tolerance: float = .00001) -> void:
	expect(absf(value-wanted)<tolerance,"%s got%.7f wanted%.7f"%[description,value,wanted])

func run_contract() -> void:
	var spring := Rig.Spring.new()
	near(spring.step(1,22,.016),1.0-(1.0+22*.016)*exp(-22*.016),"Exact source critically damped integration")
	var fine := Rig.Spring.new()
	var coarse := Rig.Spring.new()
	for i in 60:fine.step(1,22,1.0/60.0)
	for i in 30:coarse.step(1,22,1.0/30.0)
	near(fine.x,coarse.x,"Recoil spring position independent of frame rate")
	near(fine.v,coarse.v,"Recoil spring velocity independent of frame rate")
	var landing := Rig.Spring.new()
	landing.v=-.45
	for i in 60:landing.step_damped(0,13,.82,1.0/30.0)
	expect(is_finite(landing.x) and absf(landing.x)<.0001,"Source under-damped landing dip remains stable at30FPS")
	var arena := Arena.new()
	get_root().add_child(arena)
	var stage := StageStub.new()
	arena.add_child(stage)
	arena.stage=stage
	var actor := ActorStub.new()
	arena.add_child(actor)
	arena.local_player=actor
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.global_position=Vector3(0,6,-9)
	var rig := Rig.new()
	arena.add_child(rig)
	rig.configure(arena,camera)
	expect(rig.aim_camera!=camera and not rig.aim_camera.current,"Gameplay aim camera is independent and never renders")
	expect(rig._rays.size()==15,"Source camera avoidance uses center+six inner+eight outer rays")
	var probe: Dictionary = rig.camera_probe(Vector3(0,2,0),Vector3(0,0,-1),4.5)
	near(float(probe.hard),4.5,"Clear source boom keeps hard length")
	near(float(probe.soft),4.5,"Clear source boom keeps soft length")
	expect(arena.ray_count==15,"All original weighted probe rays are cast once")
	arena.wall_limit=1.3
	probe=rig.camera_probe(Vector3(0,2,0),Vector3(0,0,-1),4.5)
	near(float(probe.hard),1.0,"Source wall center uses30cm lens pad")
	near(float(probe.soft),1.0,"Soft probe never extends past hard limit")
	arena.wall_normal=Vector3.UP
	probe=rig.camera_probe(Vector3(0,2,0),Vector3.DOWN,4.5)
	expect(bool(probe.floor),"Source upward-facing center collision clamps boom against floor")
	arena.wall_limit=INF
	rig.follow(actor,true)
	near(rig.pivot.y,1.85,"Source kid follow pivot height")
	for i in 60:rig.update(1.0/60.0)
	var source_vfov: float = rad_to_deg(2.0*atan(tan(deg_to_rad(82.0)*.5)/(16.0/9.0)))
	near(camera.fov,source_vfov,"Original FOV usesfixed16:9 horizontal reference",.0001)
	expect(camera.global_transform.is_finite(),"Native follow camera transform remains finite")
	actor.velocity=Vector3(6,0,0)
	rig.update(.016)
	expect(rig.pivot.x>0.0,"Source velocity feed-forward leads lateral movement")
	actor.velocity=Vector3.ZERO
	rig.recoil(.012)
	near(rig.recoil_spring.v,.66,"Original blaster pitch impulse scales by55")
	rig.update(.016)
	near(rig.kick,.66*.016*exp(-22*.016),"Original blaster recoil has45ms rise spring",.0001)
	rig._trauma_in=0;rig.trauma=0
	rig.add_shake(.6,camera.global_position+Vector3.RIGHT*26.0)
	near(rig._trauma_in,0,"Source explosion shake iszeroat26metres")
	rig.add_shake(.6,camera.global_position+Vector3.RIGHT*4.0)
	near(rig._trauma_in,.45,"Near source explosion queues75percent trauma")
	rig.update(.01)
	near(rig.trauma,.14,"Source trauma enters over14unitspersecond")
	expect(rig.aim_camera.global_transform.is_finite(),"Shaken gameplay aim remains finite")
	rig.set_map(true)
	rig.update(.42)
	expect(rig.map_k>.99 and camera.global_position.distance_to(rig.aim_camera.global_position)>20.0,"Source map crane preserves independent gameplay pose")
	near(camera.fov,30,"Full source diorama lens is30degrees",.001)
	var gameplay_direction: Vector3 = -rig.aim_camera.global_basis.z
	var map_direction: Vector3 = -camera.global_basis.z
	expect(gameplay_direction.distance_to(map_direction)>.3,"Diorama direction never replaces gameplay aim ray")
	expect(map_direction.is_equal_approx(Vector3.DOWN),"Production Tab map looks exactly vertically downward")
	expect(camera.global_basis.y.is_equal_approx(Vector3.BACK),"Team0 vertical map puts enemy positiveZ at screen top")
	rig.set_map(true,Vector2(.8,-.7));rig.update(.1)
	near(rig.map_k,1.0,"Held production map remains fully open across settled frames")
	expect((-camera.global_basis.z).is_equal_approx(Vector3.DOWN),"Virtual cursor cannot tilt the requested vertical map")
	rig.dio_flip=true;rig.update(.1)
	expect(camera.global_basis.y.is_equal_approx(Vector3.FORWARD),"Team1 vertical map flips its screen up without parallel look warning")
	rig.dio_flip=false
	for aspect: float in [16.0/9.0,.5,2.4]:
		rig._fit_diorama(stage.bounds,aspect)
		var pose: Transform3D = rig._dio_pose(rig._dio_distance,rig._dio_z_shift,stage.bounds,0,rig.DIO_PITCH)
		var fitted: bool = true
		for x: float in [-25.0,25.0]:
			for z: float in [-44.0,44.0]:
				for y: float in [-1.2,6.0]:
					var pixel: Vector2 = rig._project_ndc(Vector3(x,y,z),pose,aspect)
					fitted=fitted and absf(pixel.x)<.925 and pixel.y>-.73 and pixel.y<.75
		expect(fitted,"Source diorama fitsfloorandrooftops aspect%.3f"%aspect)
	rig.set_map(false)
	rig.update(.34)
	near(rig.map_k,0,"Source diorama returns in.34seconds")
	arena.paused=true;rig.set_map(true)
	expect(not rig.map_open,"Paused match cannot open production map")
	arena.paused=false;arena.state="judge";rig.set_map(true)
	expect(not rig.map_open,"Nonplaying match cannot open production map")
	arena.state="playing";rig.set_map(true);arena.state="finish";rig.update(.01)
	expect(not rig.map_open,"Match state transition closes an already open production map")
	arena.state="playing"
	actor.alive=false
	rig.spectate(actor)
	rig.update(.1)
	expect(rig.mode=="spectate" and bool(rig._blend.active),"Death camera usesoriginal.55secondposeblend")
	actor.alive=true
	rig.follow(actor,true)
	rig.update(.1)
	near(float(rig._blend.duration),.7,"Respawn blend usesoriginal.7seconds")
	rig.overview()
	rig.update(.1)
	near(float(rig._blend.duration),1.2,"Judge crane usesoriginal1.2secondmodeblend")
	expect(rig._overview_springs.size()==3,"Judge crane hasthreeexactsourceposition springs")
	rig.intro(actor)
	expect(rig.mode=="path" and Vector3(rig._path.from).is_equal_approx(Vector3(18,26,30)),"Team0originalstageintro starts enemybase")
	actor.team_id=1
	rig.intro(actor)
	expect(Vector3(rig._path.from).is_equal_approx(Vector3(-18,26,-30)),"Team1originalstageintro mirrorsaroundcentre")
	arena.state="menu"
	actor.is_local=false
	actor.rotation.y=.7
	rig.follow(actor,true)
	near(rig.yaw,.7,"Source attract follow starts on actor facing")
	near(rig.pitch,-.28,"Source attract follow uses gentle downward pitch")
	actor.rotation.y=1.0
	rig.update(.1)
	near(rig.yaw,lerpf(.7,1.0,1.0-exp(-.2)),"Attract follow yaw continuously tracks source actor at2persecond")
	actor.position=Vector3(2,3,4)
	rig.boss_finish(actor)
	expect(rig.mode=="orbit" and Vector3(rig._orbit.center).is_equal_approx(Vector3(2,5.2,4)),"Boss finish camera orbits source chest centre")
	near(float(rig._orbit.radius),15,"Boss finish source radius")
	near(float(rig._orbit.height),5.5,"Boss finish source height")
	print("CAMERA CONTRACT: %d checks, %d failures"%[checks,failures.size()])
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
