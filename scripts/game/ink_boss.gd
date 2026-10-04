class_name InkBoss
extends Node3D

const Rules = preload("res://scripts/game/ink_rules.gd")
const SourceEvents=preload("res://scripts/game/ink_boss_events.gd")
const HazardVisuals=preload("res://scripts/fx/boss_hazard_visuals.gd")
const PhaseOverlay=preload("res://scripts/animation/ink_boss_phase.gd")
var _phase_overlay:InkBossPhase
var _source_events:InkBossEvents=SourceEvents.new()
const MOVE_TIMES: Dictionary = {"slam": [1.15, 1.9, 1.0], "barrage": [0.85, 0.0, 0.8], "sweep": [1.15, 2.1, 0.9], "charge": [1.15, 0.0, 0.9], "crablets": [0.9, 0.8, 0.6], "frenzy": [1.2, 3.0, 1.7]}
const SourceBrain=preload("res://scripts/game/ink_boss_brain.gd")
var brain:InkBossBrain
const SourceNav=preload("res://scripts/game/ink_boss_nav.gd")
var nav:InkBossNav
var _move_params:Dictionary={}
var _move_cooldowns:Dictionary={"crablets":0.0,"frenzy":0.0}
var _beam_lengths:Dictionary={}
var match_node: Node
var team_id: int = 1
var display_name: String = "HULLBREAKER"
var hp: float = 1.0
var max_hp: float = 1.0
var phase: int = 1
var dead: bool = false
var alive: bool = true
var difficulty: String = "normal"
var stunned: bool = false
var invuln: bool = false
var _intro_started: bool = false
var _intro_finished: bool = false
var _roar_time: float = 0.0
var move_id: String = ""
var move_phase: String = ""
var move_time: float = 0.0
var clock: float = 0.0
var turf_points: float = 0.0
var splats: int = 0
var velocity: Vector3 = Vector3.ZERO
var _model: Node3D
var _material: StandardMaterial3D
var _weak_material: StandardMaterial3D
var _telegraph: MeshInstance3D
var _beam: MeshInstance3D
var _hazards: Array[Dictionary] = []
var _visual_hazards:Array[Dictionary]=[]
var _crablets: Array[Dictionary] = []
var _crab_sequence:int=0
var _crab_pops:Array[Dictionary]=[]
var _claws: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _eye_positions: Array[Vector3] = [Vector3(-0.9, 4.0, 2.1), Vector3(0.9, 4.0, 2.1)]
var _wait: float = 2.4
var _paint_timer: float = 0.0
var _target: Vector3
var _origin: Vector3
var _direction: Vector3
var _timing: Array = []
var _performed: Dictionary = {}
var _last_move: String = ""
var _death_time: float = 0.0
var _flash: float = 0.0
var _channels0:Node3D
var _channels1:Node3D
var _tear:float=0.0
var _tear_velocity:float=0.0
var _source_anim: AnimationPlayer
var _source_sockets: Dictionary = {}
var _source_clip: String = ""
var _source_materials: Array[ShaderMaterial] = []
var _rain_pending: Dictionary = {}
var _rain_time: float = 0.0

func configure(game: Node, level: String = "normal") -> void:
	match_node = game
	difficulty = level
	var units: float = 0.0
	var actors = game.get("actors")
	if actors is Array:
		for actor in actors:
			units += 0.6 if bool(actor.get_meta("bot", not actor.is_local)) else 1.0
	max_hp = roundf(18000.0 * maxf(1.0, units) * (0.75 if level == "easy" else (1.3 if level == "hard" else 1.0)))
	hp = max_hp
	_material = _make_material(Color("a44b33"), 0.48)
	_weak_material = _make_material(Color("ffb51c"), 0.23)
	var colors = game.get("team_colors")
	if colors is Array and colors.size() > 1:
		_weak_material.albedo_color = colors[0]
		_weak_material.emission_enabled = true
		_weak_material.emission = colors[0]
		_weak_material.emission_energy_multiplier = 0.65
	_build_model()
	var stage = game.get("stage")
	var spawn:Vector3=Vector3(0,0,12)
	if is_instance_valid(stage):
		var stage_id=stage.get("stage_id")
		if stage_id is String:
			var baked:=SourceNav.new()
			if baked.configure(stage_id):nav=baked
		if nav:
			var point:Array=nav.metadata.spawn
			spawn=Vector3(float(point[0]),float(point[1]),float(point[2]))
			rotation.y=float(nav.metadata.yaw)
		else:
			var best_height:float=float(stage.call("ground_height",spawn.x,spawn.z,50.0))
			if is_finite(best_height):spawn.y=best_height
	global_position = spawn
	if nav:brain=SourceBrain.new();brain.configure(self,nav)
	visible=false
	_event("boss:spawn", {"boss": self})

func team_color() -> Color:
	var colors = match_node.get("team_colors")
	return colors[1] if colors is Array and colors.size() > 1 else Color("2f5bff")

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.25
	return material

func _part(parent: Node3D, mesh: Mesh, where: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = where
	parent.add_child(instance)
	return instance

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var path: String = "res://assets/characters/boss.glb"
	if ResourceLoader.exists(path):
		var colors = match_node.get("team_colors")
		var weak_color: Color = colors[0] if colors is Array and not colors.is_empty() else Color("ff8a14")
		var original: Node3D = InkAvatar.create_source_asset("boss", team_color(), weak_color)
		if original:
			_model.add_child(original)
			_phase_overlay=PhaseOverlay.new();_phase_overlay.configure(original)
			_channels0=original.find_child("BossChannels0",true,false) as Node3D
			_channels1=original.find_child("BossChannels1",true,false) as Node3D
			for child in original.find_children("*", "AnimationPlayer", true, false):
				_source_anim = child
				_source_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				for clip in _source_anim.get_animation_list():
					var looping:bool=str(clip).ends_with("_idle") or str(clip).ends_with("_run") or str(clip).ends_with("_stun")
					_source_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
				break
			for child in original.find_children("Socket_*", "Node3D", true, false):
				_source_sockets[str(child.name).trim_prefix("Socket_")] = child
			for child in original.find_children("*", "MeshInstance3D", true, false):
				if child.material_override is ShaderMaterial:
					_source_materials.append(child.material_override)
			_play_source_clip("boss_intro")
	else:
		_part(_model, _box(Vector3(4.4, 3.1, 5.9)), Vector3(0, 3.3, -0.4), _material)
		var dark: StandardMaterial3D = _make_material(Color("304455"), 0.6)
		for x in [-2.2, 2.2]:
			for z in [-2.7, 2.4]:
				_part(_model, _box(Vector3(0.14, 3.2, 0.16)), Vector3(x, 3.3, z), dark)
		for z in [-2.7, 2.4]:
			for y in [1.8, 4.8]:
				_part(_model, _box(Vector3(4.5, 0.14, 0.16)), Vector3(0, y, z), dark)
		for z in range(-2, 3):
			for x in [-2.23, 2.23]:
				_part(_model, _box(Vector3(0.10, 2.6, 0.07)), Vector3(x, 3.3, float(z)), dark)
		_part(_model, _ball(1.5), Vector3(0, 1.6, 2.5), _make_material(Color("975849"), 0.38))
		_part(_model, _ball(0.85), Vector3(0, 1.35, 2.2), _weak_material)
		for side in [-1.0, 1.0]:
			var eye := Node3D.new()
			eye.position = Vector3(side * 0.9, 3.1, 2.0)
			_model.add_child(eye)
			_part(eye, _box(Vector3(0.22, 1.3, 0.22)), Vector3(0, 0.4, 0), dark)
			_part(eye, _ball(0.36), Vector3(0, 1.0, 0.05), _weak_material)
			_part(eye, _ball(0.18), Vector3(0, 1.0, 0.32), dark)
			var claw := Node3D.new()
			claw.position = Vector3(side * 2.3, 1.6, 2.4)
			_model.add_child(claw)
			_part(claw, _box(Vector3(1.2, 0.7, 2.6)), Vector3(side * 0.4, 0, 0.9), _material)
			_part(claw, _ball(1.0 if side < 0 else 0.72), Vector3(side * 0.5, 0, 2.0), _material)
			_claws.append(claw)
			for i in range(3):
				var leg := Node3D.new()
				leg.position = Vector3(side * 1.8, 1.5, -1.9 + float(i) * 1.35)
				_model.add_child(leg)
				var limb: MeshInstance3D = _part(leg, _box(Vector3(2.3, 0.28, 0.32)), Vector3(side * 1.0, -0.25, 0), dark)
				limb.rotation.z = side * -0.4
				_part(leg, _box(Vector3(0.28, 1.2, 0.32)), Vector3(side * 2.0, -1.0, 0), _material)
				_legs.append(leg)
	_telegraph=MeshInstance3D.new();add_child(_telegraph);_telegraph.top_level=true
	HazardVisuals.configure_mesh(_telegraph,"mark",{},team_color())
	_telegraph.visible = false
	_beam=MeshInstance3D.new();add_child(_beam);_beam.top_level=true
	HazardVisuals.configure_mesh(_beam,"beam",{},team_color())
	_beam.visible = false

func update(dt: float) -> void:
	clock += dt
	if brain:brain.tick(dt)
	var previous_position:Vector3=global_position
	for key in _move_cooldowns:_move_cooldowns[key]=float(_move_cooldowns[key])-dt
	velocity = Vector3.ZERO
	_flash = maxf(0.0, _flash - dt * 4.0)
	for material in _source_materials:
		material.set_shader_parameter("uTime", clock)
		material.set_shader_parameter("hit_flash", _flash * 0.3)
		material.set_shader_parameter("uPhase", phase)
	if _source_anim and visible:
		_source_anim.advance(dt)
		for hook:Dictionary in _source_events.advance(dt):_dispatch_source_hook(hook)
	update_visual_channels(dt)
	_tick_crab_visuals(dt)
	if dead:
		_death_time += dt
		if not _source_anim:
			_model.rotation.z=move_toward(_model.rotation.z,.7,dt*.4)
			_model.position.y=move_toward(_model.position.y,-1.4,dt*.8)
		return
	var match_state:String=str(match_node.get("state"))
	if not _intro_started and clock>=1.8:
		_intro_started=true
		visible=true
		_play_source_clip("boss_intro",3.4,true)
		_event("boss:intro",{"boss":self,"dur":3.4})
	if _intro_started and not _intro_finished and clock>=5.2:
		_intro_finished=true
		_play_source_clip("boss_idle")
	if match_state!="playing":
		if match_state in ["finish","judge","results"]:
			move_id="";move_phase="";stunned=false;invuln=false
			_beam.visible=false;_telegraph.visible=false
			for hazard in _hazards:
				hazard.node.queue_free()
				if is_instance_valid(hazard.get("barrel")):hazard.barrel.queue_free()
			_hazards.clear()
		return
	_flush_rain(dt)
	if dead:return
	_tick_crablets(dt)
	if _roar_time>0:
		_roar_time-=dt
		invuln=true
		if _roar_time<=0:
			invuln=false
			_play_source_clip("boss_idle")
		return
	var fraction: float = hp / max_hp
	var next_phase: int = 3 if fraction <= 0.33 else (2 if fraction <= 0.66 else 1)
	if next_phase > phase and move_id.is_empty():
		phase = next_phase
		_wait = minf(_wait,.9*_pace())
		if phase>=2:_move_cooldowns.crablets=minf(float(_move_cooldowns.crablets),2.0)
		if phase>=3:_move_cooldowns.frenzy=minf(float(_move_cooldowns.frenzy),3.0)
		_roar_time=1.9
		invuln=true
		_event("boss:phase", {"boss": self, "phase": phase})
		_play_source_clip("boss_roar")
		return
	if not _source_anim:_model.position.y=sin(clock*2.0)*.08
	for i in range(_legs.size()):
		_legs[i].rotation.x = sin(clock * (3.0 + velocity.length()) + float(i) * PI) * 0.15
	if not move_id.is_empty():
		move_time += dt
		_tick_move(dt)
	else:
		if brain:brain.idle(dt)
		else:
			_wait-=dt;_seek(dt)
			if _wait<=0:_start_move()
		if move_id.is_empty():_play_source_clip("boss_run" if velocity.length()>.1 or (brain and brain.speed>.1) else "boss_idle")
	if nav:global_position.y=lerpf(global_position.y,nav.floor_at(global_position.x,global_position.z),minf(1,dt*5))
	velocity=(global_position-previous_position)/maxf(dt,.0001)
	_tick_hazards(dt)
	push_actors()

func update_visual_channels(dt:float) -> void:
	var substeps:int=2 if dt>1.0/90.0 else 1
	var step:float=dt/float(substeps)
	var tear_target:float=1.0 if phase>=3 or (dead and _death_time>1.9) else 0.0
	for index in substeps:
		_tear_velocity+=(60.0*(tear_target-_tear)-7.0*_tear_velocity)*step
		_tear+=_tear_velocity*step
	if _phase_overlay:_phase_overlay.apply(_tear,_channels1.position.x if is_instance_valid(_channels1) else 0.0)
	if is_instance_valid(_channels0):
		for material in _source_materials:
			material.set_shader_parameter("uGlowL",maxf(0,_channels0.position.x))
			material.set_shader_parameter("uCannon",clampf(_channels0.position.y,0,1.2))
			material.set_shader_parameter("uBelly",1.0 if phase>=3 else clampf(_channels0.position.z,0,1))
			material.set_shader_parameter("uOpen",clampf(_tear,0,1))

func _nearest_actor():
	var best = null
	var distance: float = INF
	var actors = match_node.get("actors")
	if actors is Array:
		for actor in actors:
			if not actor.alive or _safe_spawn(actor):
				continue
			var d: float = global_position.distance_to(actor.global_position)
			if d < distance:
				best = actor
				distance = d
	return best

func _seek(dt: float) -> void:
	var actor = _nearest_actor()
	if not actor:
		return
	var delta: Vector3 = actor.global_position - global_position
	delta.y = 0.0
	if delta.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(delta.x, delta.z), minf(1.0, dt * 2.0))
	if delta.length() > 10.0:
		var proposed: Vector3 = global_position + delta.normalized() * 2.1 * dt
		_move_safe(proposed, dt)

func _move_safe(proposed: Vector3, dt: float = 0.0166667) -> bool:
	var stage = match_node.get("stage")
	if not stage:
		return false
	var height: float = float(stage.call("ground_height", proposed.x, proposed.z, global_position.y + 1.2))
	if not is_finite(height) or height < -2.1 or absf(height - global_position.y) > 0.65:
		return false
	var hit: Dictionary = match_node.call("cast", global_position + Vector3.UP * 1.7, proposed + Vector3.UP * 1.7, [])
	if not hit.is_empty():
		return false
	proposed.y = height
	velocity = (proposed - global_position) / maxf(0.001, dt)
	global_position = proposed
	return true

func _pace() -> float:
	return 1.25 if difficulty=="easy" else (.85 if difficulty=="hard" else 1.0)

func phase_times(id:String,current_phase:int=1) -> Array:
	var pace:float=1.0 if current_phase==1 else (.88 if current_phase==2 else .78)
	var base:Array=MOVE_TIMES[id]
	return [maxf(.7,float(base[0])*pace),float(base[1])*pace,float(base[2])*pace]

func charge_time(length:float,speed:float) -> float:
	var acceleration_distance:float=.5*speed*.35
	return sqrt(2.0*length*.35/speed) if length<=acceleration_distance else .35+(length-acceleration_distance)/speed

func charge_distance(time:float,length:float,speed:float) -> float:
	if time<=0:return 0.0
	return minf(length,.5*(speed/.35)*time*time if time<.35 else .5*speed*.35+speed*(time-.35))

func _lane(yaw:float) -> Dictionary:
	if not nav:return {}
	var best:Dictionary={}
	var highest:float=-INF
	for offset in [0,.25,-.25,.5,-.5,.8,-.8,1.1,-1.1,1.45,-1.45,1.8,-1.8]:
		var angle:float=yaw+float(offset)
		if not nav.turn_ok(global_position.x,global_position.z,angle):continue
		var lane:Dictionary=nav.cast(global_position.x,global_position.z,angle,34)
		if float(lane.dist)<6:continue
		var score:float=minf(float(lane.dist),22)*.2-absf(float(offset))*1.6+(1.0 if lane.wall else 0.0)
		if score>highest:highest=score;best={"yaw":angle,"length":lane.dist,"wall":lane.wall}
	return best

func _start_move(forced:String="") -> void:
	var target=brain.target if brain and is_instance_valid(brain.target) else _nearest_actor()
	if not target and forced.is_empty():_wait=.5;return
	_target=target.global_position if is_instance_valid(target) else global_position+global_basis.z*10
	var aimed_yaw:float=atan2(_target.x-global_position.x,_target.z-global_position.z)
	var lane:Dictionary=_lane(aimed_yaw)
	var weights:Array=[]
	var close:int=0;var distant:int=0
	for actor in match_node.get("actors"):
		if not actor.alive or actor.team_id!=0 or _in_pad(actor.global_position,1.0):continue
		var distance:float=Vector2(actor.global_position.x-global_position.x,actor.global_position.z-global_position.z).length()
		if distance<10.5:close+=1
		if distance>13:distant+=1
	var front:Vector3=global_position+global_basis.z*2
	var distance:float=Vector2(_target.x-front.x,_target.z-front.z).length()
	weights=[["slam",3.0+float(close)*.6 if distance<11 else .25],["barrage",1.3+float(distant)*.45+(1.0 if distance>12 else 0.0)],["sweep",2.1 if distance>5 and distance<17 else .4],["charge",(2.2 if distance>5.5 else 1.2) if not lane.is_empty() else 0.0]]
	if phase>=2 and float(_move_cooldowns.crablets)<=0 and _crablets.size()<3:weights.append(["crablets",2.4])
	if phase>=3 and float(_move_cooldowns.frenzy)<=0:weights.append(["frenzy",1.1+float(close)*.9])
	var total:float=0
	for weight in weights:
		if weight[0]==_last_move:weight[1]=float(weight[1])*.3
		total+=float(weight[1])
	var choice:float=randf()*total
	move_id="barrage"
	for weight in weights:
		choice-=float(weight[1])
		if choice<=0:move_id=str(weight[0]);break
	if not forced.is_empty():move_id=forced
	if move_id=="charge" and lane.is_empty():move_id="barrage"
	if not brain:
		if move_id in ["slam","sweep"] and (not nav or nav.turn_ok(global_position.x,global_position.z,aimed_yaw)):rotation.y=aimed_yaw
		elif move_id=="charge":rotation.y=float(lane.yaw)
	_last_move=move_id;move_time=0;stunned=false;_performed.clear();_beam_lengths.clear();_move_params.clear()
	_timing=phase_times(move_id,phase)
	_origin=global_position;_direction=global_basis.z
	match move_id:
		"slam":
			var point:Vector3=global_position+_direction*4.3
			point.y=nav.floor_at(point.x,point.z) if nav else global_position.y
			_move_params={"center":point,"rings":[0.0,.6] if phase>=3 else ([0.0,.9] if phase>=2 else [0.0]),"reach":_reach(point,19)}
			_timing[1]=1.2
		"barrage":
			var candidates:Array=[]
			for actor in match_node.get("actors"):
				if actor.alive and actor.team_id==0 and actor.super_jump_state.is_empty() and not _in_pad(actor.global_position,3.4):candidates.append(actor)
			candidates.sort_custom(func(a,b)->bool:return Vector2(a.global_position.x-global_position.x,a.global_position.z-global_position.z).length()>Vector2(b.global_position.x-global_position.x,b.global_position.z-global_position.z).length())
			var points:Array=[]
			for index in (4 if phase==1 else (5 if phase==2 else 7)):
				if candidates.is_empty():break
				var actor=candidates[index%candidates.size()]
				var angle:float=randf()*TAU
				var offset:float=randf_range(3,5.5) if index>=candidates.size() else 0.0
				var point:Vector3=actor.global_position+actor.velocity*.3+Vector3(cos(angle),0,sin(angle))*offset
				point.y=_ground(point.x,point.z,actor.global_position.y+1)
				if point.y<=Rules.player("waterY",-3.2) or _in_pad(point,2.9):point=actor.global_position;point.y=_ground(point.x,point.z,actor.global_position.y+1)
				if point.y<=Rules.player("waterY",-3.2) or _in_pad(point,2.9):continue
				points.append(point)
				_add_hazard("barrel",point,2.4,52,float(_timing[0])+float(points.size()-1)*.26,1.3,{"from":global_position-_direction*.6+Vector3.UP*5.4})
			if points.is_empty():move_id="";_wait=.5;return
			_move_params={"points":points}
			_timing[1]=float(points.size()-1)*.26+1.4
		"sweep":
			var span:float=1.9 if phase==1 else (2.2 if phase==2 else 2.5)
			var side:float=1.0 if randf()<.5 else -1.0
			_move_params={"from":global_position+_direction*3.3+Vector3.UP*2.3,"a0":aimed_yaw-side*span*.5,"a1":aimed_yaw+side*span*.5,"yaw":rotation.y}
		"charge":
			var cast_lane:Dictionary=nav.cast(global_position.x,global_position.z,rotation.y,34)
			if float(cast_lane.dist)<6:move_id="";_wait=.4;return
			var speed:float=13.0 if phase==1 else (14.5 if phase==2 else 16.0)
			_move_params={"length":float(cast_lane.dist),"wall":cast_lane.wall,"speed":speed,"yaw":rotation.y}
			_timing[1]=charge_time(float(cast_lane.dist),speed);_timing[2]=4.2 if phase==1 else (3.7 if phase==2 else 3.3)
		"crablets":_move_cooldowns.crablets=14*_pace()
		"frenzy":
			_move_params={"rot0":randf()*TAU,"spin":nav!=null and nav.wall_clear(global_position.x,global_position.z)>=5 and nav.floor_clear(global_position.x,global_position.z)>=3.9}
			_move_cooldowns.frenzy=11*_pace()
	move_phase="tele";_paint_timer=0
	_play_source_clip("boss_%s_tele"%move_id,float(_timing[0]))
	_prepare_move_visuals()
	_draw_move_visuals()
	_event("boss:move",{"boss":self,"id":move_id,"phase":"tele","dur":_timing[0]})

func _ground(x:float,z:float,maximum:float) -> float:
	var stage=match_node.get("stage")
	if is_instance_valid(stage) and stage.has_method("ground_height"):return float(stage.call("ground_height",x,z,maximum))
	var hit:Dictionary=match_node.call("cast",Vector3(x,maximum,z),Vector3(x,Rules.player("waterY",-3.2)-1,z),[])
	return float(hit.position.y) if not hit.is_empty() else -100.0

func _beam_length(angle:float) -> float:
	var key:int=int(floor(angle*90+.5))
	if not _beam_lengths.has(key):
		var quantized:float=float(key)/90
		var origin:Vector3=Vector3(_move_params.from);origin.y=_origin.y+1
		var hit:Dictionary=match_node.call("cast",origin,origin+Vector3(sin(quantized),0,cos(quantized))*17,[])
		_beam_lengths[key]=origin.distance_to(hit.position) if not hit.is_empty() else 17.0
	return float(_beam_lengths[key])

func _prepare_move_visuals() -> void:
	_telegraph.visible=false;_telegraph.scale=Vector3.ONE;_telegraph.global_rotation=Vector3.ZERO
	if move_id in ["sweep","frenzy"]:
		var center:Vector3=_move_params.from if move_id=="sweep" else _origin
		center.y=_origin.y+.05
		var maximum:float=17.0 if move_id=="sweep" else 8.8
		var reach:PackedFloat32Array=_reach(center,maximum)
		var low:float=minf(float(_move_params.a0),float(_move_params.a1)) if move_id=="sweep" else 0.0
		var high:float=maxf(float(_move_params.a0),float(_move_params.a1)) if move_id=="sweep" else TAU
		var segments:int=maxi(8,ceili(absf(high-low)/TAU*96))
		var radii:PackedFloat32Array=[]
		for index in range(segments+1):
			var angle:float=lerpf(low,high,float(index)/float(segments))
			var heading:int=int(floor(fposmod(angle,TAU)/TAU*96))%96
			radii.append(maxf(2,minf(_beam_length(angle),reach[heading])) if move_id=="sweep" else reach[heading])
		HazardVisuals.configure_mesh(_telegraph,"fan",{"a0":low,"a1":high,"radii":Array(radii)},team_color())
		_telegraph.global_position=center
	elif move_id=="charge":HazardVisuals.configure_mesh(_telegraph,"lane",{},team_color())
	elif move_id=="slam":HazardVisuals.configure_mesh(_telegraph,"mark",{},team_color())

func _draw_move_visuals() -> void:
	if move_id.is_empty():_telegraph.visible=false;return
	var tele:float=float(_timing[0]);var act:float=float(_timing[1])
	var u:float=move_time;var k:float=clampf(u/tele,0,1)
	var material:ShaderMaterial=_telegraph.material_override as ShaderMaterial
	if material==null:return
	material.set_shader_parameter("uTime",clock);material.set_shader_parameter("uK",k);material.set_shader_parameter("uAlpha",1.0)
	match move_id:
		"slam":
			_telegraph.visible=u<tele+.15
			_telegraph.global_position=Vector3(_move_params.center)+Vector3.UP*.04
			_telegraph.global_rotation=Vector3.ZERO;_telegraph.scale=Vector3(3.3,1,3.3)
		"sweep":
			_telegraph.visible=u<=tele+act
			k=u/tele if u<tele else 1-(u-tele)/act
			material.set_shader_parameter("uAlpha",.55+.45*minf(1,k*1.5));material.set_shader_parameter("uK",clampf(k,0,1))
		"charge":
			_telegraph.visible=u<=tele+act
			var distance:float=charge_distance(u-tele,float(_move_params.length),float(_move_params.speed))
			_telegraph.global_position=_origin+_direction*distance+Vector3.UP*.05
			_telegraph.global_rotation=Vector3(0,float(_move_params.yaw),0)
			_telegraph.scale=Vector3(5,1,maxf(.5,float(_move_params.length)+4.2-distance))
			material.set_shader_parameter("uAlpha",.35+.65*k if u<tele else .9)
		"frenzy":
			_telegraph.visible=u<tele+act
			material.set_shader_parameter("uAlpha",.5+.5*k);material.set_shader_parameter("uTime",clock*(1 if u<tele else 2.5))
		_:_telegraph.visible=false

func _tick_move(dt:float) -> void:
	var tele:float=float(_timing[0]);var act:float=float(_timing[1]);var rec:float=float(_timing[2])
	var current:String="tele" if move_time<tele else ("act" if move_time<tele+act else "rec")
	if current!=move_phase:
		move_phase=current
		stunned=move_phase=="rec" and move_id in ["charge","frenzy"]
		_play_source_clip("boss_stun" if stunned else "boss_%s_%s"%[move_id,move_phase],act if move_phase=="act" else rec)
		_event("boss:move",{"boss":self,"id":move_id,"phase":move_phase,"dur":act if move_phase=="act" else rec})
		if stunned:_event("boss:stun",{"boss":self,"dur":rec})
	var t:float=move_time-tele
	var previous:float=t-dt
	match move_id:
		"slam":
			var point:Vector3=_move_params.center
			if t>=0:
				if not _performed.has("slam_impact"):
					_performed.slam_impact=true
					_damage_radius(point,3.65,48,"boss_slam",2.0)
					_paint(point,2.8)
					for index in 7:_paint(point+Vector3(cos(float(index)*.9),0,sin(float(index)*.9))*2.6,1.3)
					if not _source_anim:_event("boss:impact",{"boss":self,"pos":point,"strength":1.2,"socket":"clawL"})
				for index in _move_params.rings.size():
					var offset:float=float(_move_params.rings[index])
					var key:String="slam_%s"%index
					if t>=offset and not _performed.has(key):
						_performed[key]=true
						_add_hazard("ring",point,19,32,0,(19.0-2.4)/9.5,{"elapsed":t-offset,"ring_index":index})
		"sweep":
			if move_phase=="act":
				var angle:float=lerpf(float(_move_params.a0),float(_move_params.a1),smoothstep(0,1,clampf(t/act,0,1)))
				var direction:Vector3=Vector3(sin(angle),0,cos(angle))
				var begin:Vector3=_move_params.from
				var length:float=_beam_length(angle)
				var end:Vector3=begin+direction*length;end.y=_origin.y+.3
				_beam.visible=true;_beam.global_position=begin
				_beam.look_at(end,Vector3.UP,true)
				var width:float=.32+.06*sin(clock*40)
				_beam.scale=Vector3(width,width,begin.distance_to(end))
				var yaw:float=float(_move_params.yaw)+wrapf(angle-float(_move_params.yaw),-PI,PI)*.5
				if not nav or nav.turn_ok(global_position.x,global_position.z,yaw):rotation.y=yaw
				for actor in match_node.get("actors"):
					if not actor.alive or actor.team_id!=0 or actor.submerged or _safe_spawn(actor):continue
					var delta:Vector3=actor.global_position-begin
					var along:float=delta.dot(direction)
					var lateral:float=absf(delta.x*direction.z-delta.z*direction.x)
					if along>1.5 and along<length+.4 and lateral<.95+Rules.player("radius",.38) and actor.global_position.y<_origin.y+2.4:
						if match_node.call("cast",begin,actor.global_position+Vector3.UP*.9,[actor.get_rid()]).is_empty():actor.damage(170*dt*_damage_scale(),self,"boss_beam")
				for k in range(maxi(0,int(floor(previous/.06))+1),int(floor(t/.06))+1):
					var a:float=lerpf(float(_move_params.a0),float(_move_params.a1),smoothstep(0,1,float(k)*.06/act))
					var reach:float=_beam_length(a);var dir:Vector3=Vector3(sin(a),0,cos(a))
					_paint(Vector3(begin.x,_origin.y,begin.z)+dir*reach,1.05)
					if k%2:_paint(Vector3(begin.x,_origin.y,begin.z)+dir*reach*(.45+.4*fmod(float(k)*.37,1)),.8)
		"charge":
			var distance:float=charge_distance(t,float(_move_params.length),float(_move_params.speed))
			var previous_pos:Vector3=global_position
			global_position=_origin+_direction*distance
			velocity=(global_position-previous_pos)/maxf(dt,.0001)
			if move_phase=="act":
				for actor in match_node.get("actors"):
					if not actor.alive or actor.team_id!=0 or _safe_spawn(actor) or actor.global_position.y>=_origin.y+3.5:continue
					var key:String="charge_%s"%actor.get_instance_id()
					if _performed.has(key):continue
					for body:Vector2 in SourceNav.WALL_BODY:
						var center:Vector3=global_position+_direction*body.x
						if Vector2(actor.global_position.x-center.x,actor.global_position.z-center.z).length()>=body.y+.35:continue
						_performed[key]=true
						var side:float=1.0 if (actor.global_position-global_position).dot(Vector3(_direction.z,0,-_direction.x))>=0 else -1.0
						actor.velocity+=Vector3(_direction.z,0,-_direction.x)*side*9+_direction*5;actor.velocity.y=7
						actor.damage(55*_damage_scale(),self,"boss_charge")
						break
				for k in range(maxi(0,int(floor(previous/.09))+1),int(floor(t/.09))+1):
					var s:float=charge_distance(float(k)*.09,float(_move_params.length),float(_move_params.speed))
					_paint(_origin+_direction*(s-1)+Vector3(_direction.z,0,-_direction.x)*(1.3 if k%2 else -1.3),1)
		"crablets":
			if t>=0 and not _performed.has("brood"):
				_performed.brood=true
				var count:int=5 if phase>=3 else 3
				for index in count:
					var side:float=(float(index)-float(count-1)*.5)*1.1
					var back:Vector3=-global_basis.z
					var point:Vector3=global_position+back*3.6+Vector3(back.z,0,-back.x)*side
					point.y=_ground(point.x,point.z,global_position.y+1.5)
					if point.y<=Rules.player("waterY",-3.2) or _in_pad(point,.8):point=global_position+Vector3(back.z,0,-back.x)*side
					_spawn_crablet(point,rotation.y+PI+side*.4)
		"frenzy":
			if move_phase=="act":
				if bool(_move_params.spin):rotation.y+=dt*4.2*minf(1,minf(t/.4,(act-t)/.4))
				for actor in match_node.get("actors"):
					if not actor.alive or actor.team_id!=0 or _safe_spawn(actor) or actor.global_position.y>=_origin.y+3:continue
					if Vector2(actor.global_position.x-_origin.x,actor.global_position.z-_origin.z).length()<8.8 and match_node.call("cast",_origin+Vector3.UP*1.6,actor.global_position+Vector3.UP*.8,[actor.get_rid()]).is_empty():actor.damage(52*dt*_damage_scale(),self,"boss_frenzy")
				for k in range(maxi(0,int(floor(previous/.07))+1),int(floor(t/.07))+1):
					for index in 2:
						var angle:float=float(_move_params.rot0)+float(k)*.07*2.6+float(index)*PI+float(k%3)*.7
						var radius:float=8.8*(.35+.6*fmod(float(k)*.618+float(index)*.3,1))
						_paint(_origin+Vector3(sin(angle),0,cos(angle))*radius,.9)
	_draw_move_visuals()
	if move_phase=="rec":_beam.visible=false
	if move_time>=tele+act+rec:
		move_id="";move_phase="";stunned=false;_beam.visible=false;_telegraph.visible=false
		_wait=((1.05 if phase==1 else (.8 if phase==2 else .6))+randf()*(.8 if phase==1 else (.6 if phase==2 else .45)))*_pace()

func _reach(point:Vector3,radius:float) -> PackedFloat32Array:
	var result:PackedFloat32Array=[]
	for index in 96:
		var angle:float=(float(index)+.5)/96.0*TAU
		var distance:float=0
		while distance<radius and (distance<1.2 or not nav or nav.kind_at(point.x+sin(angle)*distance,point.z+cos(angle)*distance)==0):distance+=.35
		result.append(minf(distance,radius))
	return result

func _reach_at(extents:PackedFloat32Array,point:Vector3,target:Vector3) -> float:
	var angle:float=atan2(target.x-point.x,target.z-point.z)
	var index:int=int(floor((angle if angle>=0 else angle+TAU)/TAU*96))%96
	return extents[index]

func _add_hazard(kind:String,point:Vector3,radius:float,amount:float,delay:float,lifetime:float,extra:Dictionary={}) -> void:
	var reach:PackedFloat32Array=_reach(point,radius)
	var mesh:=MeshInstance3D.new();match_node.add_child(mesh);mesh.global_position=point+Vector3.UP*(.06 if kind=="ring" else .04)
	HazardVisuals.configure_mesh(mesh,"ring" if kind=="ring" else "mark",{"reach":Array(reach)} if kind=="ring" else {},team_color())
	if kind!="ring":mesh.scale=Vector3(radius,1,radius)
	var hazard:Dictionary={"kind":kind,"pos":point,"radius":radius,"damage":amount,"delay":delay,"life":lifetime,"time":0.0,"start":clock-float(extra.get("elapsed",0)),"hits":{},"node":mesh,"reach":reach,"ring_index":extra.get("ring_index",0)}
	if kind=="barrel":
		hazard["warning_start"]=minf(float(_timing[0])*.4,delay-.5) if not _timing.is_empty() else 0.0
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.42;cylinder.bottom_radius=.42;cylinder.height=.95;cylinder.radial_segments=16
		var material:StandardMaterial3D=_make_material(Color("8a4a32"),.55);material.metallic=.35;material.emission_enabled=true;material.emission=team_color();material.emission_energy_multiplier=.18
		hazard["barrel"]=_part(match_node,cylinder,Vector3(extra.get("from",global_position+Vector3.UP*5.4)),material)
		hazard["from"]=extra.get("from",global_position+Vector3.UP*5.4)
	_hazards.append(hazard)

func _tick_hazards(dt:float) -> void:
	for index in range(_hazards.size()-1,-1,-1):
		var hazard:Dictionary=_hazards[index]
		hazard.time=clock-float(hazard.start)
		var t:float=float(hazard.time)-float(hazard.delay)
		var previous:float=maxf(0,t-dt)
		if hazard.kind=="ring":
			var radius:float=2.4+9.5*maxf(0,t)
			var previous_radius:float=2.4+9.5*previous
			var material:ShaderMaterial=hazard.node.material_override
			material.set_shader_parameter("uR",radius);material.set_shader_parameter("uTime",clock)
			material.set_shader_parameter("uAlpha",1-smoothstep(15,19,radius))
			for actor in match_node.get("actors"):
				if not actor.alive or actor.team_id!=0 or _safe_spawn(actor):continue
				var delta:Vector3=actor.global_position-Vector3(hazard.pos)
				var distance:float=Vector2(delta.x,delta.z).length()
				var key:int=actor.get_instance_id()
				if distance>previous_radius-.8 and distance<radius+.8 and delta.y<.5 and delta.y>-.8 and distance<_reach_at(hazard.reach,hazard.pos,actor.global_position)+.3 and not hazard.hits.has(key):
					hazard.hits[key]=true;actor.damage(float(hazard.damage)*_damage_scale(),self,"boss_ring")
			var every:float=2.2/9.5
			for k in range(maxi(0,int(floor((t-dt)/every))+1),int(floor(t/every))+1):
				var r:float=2.4+2.2*float(k+1)
				if r>18:continue
				var count:int=roundi(r*1.4)
				for j in count:
					var angle:float=float(j)/float(count)*TAU+float(hazard.ring_index)*.4+float(k)
					var point:Vector3=Vector3(hazard.pos)+Vector3(cos(angle),0,sin(angle))*r
					if r<_reach_at(hazard.reach,hazard.pos,point):_paint(point,.75)
		elif hazard.kind=="barrel":
			hazard.node.visible=float(hazard.time)>float(hazard.get("warning_start",0))
			var material:ShaderMaterial=hazard.node.material_override
			material.set_shader_parameter("uTime",clock);material.set_shader_parameter("uK",clampf(1-(float(hazard.life)-t)/1.8,0,1))
			hazard.barrel.visible=t>=0 and t<float(hazard.life)
			if t>=0:
				var k:float=clampf(t/1.3,0,1)
				var from:Vector3=hazard.from;var to:Vector3=hazard.pos
				var peak:float=5+.35*Vector2(to.x-from.x,to.z-from.z).length()
				hazard.barrel.global_position=from.lerp(to,k)+Vector3.UP*peak*4*k*(1-k)
				hazard.barrel.rotation=Vector3(k*9+to.x,0,k*6)
			if t>=float(hazard.life):
				_damage_radius(hazard.pos,2.75,52,"boss_barrel",2.2)
				_paint(hazard.pos,2.2)
				for j in 4:
					var angle:float=float(j)*1.6+Vector3(hazard.pos).x
					_paint(Vector3(hazard.pos)+Vector3(cos(angle),0,sin(angle))*1.8,1)
		if t>=float(hazard.life):
			hazard.node.queue_free()
			if is_instance_valid(hazard.get("barrel")):hazard.barrel.queue_free()
			_hazards.remove_at(index)

func threat(point:Vector3,horizon:float=1.2) -> Dictionary:
	var result:Dictionary={"level":0.0,"ax":0.0,"az":0.0,"ringIn":-1.0,"cover":false,"lane":false,"beam":false}
	if _in_pad(point,.6):return result
	var escape:Vector3=Vector3.ZERO
	for hazard in _hazards:
		var delta:Vector3=point-Vector3(hazard.pos)
		var distance:float=Vector2(delta.x,delta.z).length()
		var t:float=clock-float(hazard.start)-float(hazard.delay)
		if hazard.kind=="barrel" and t>-.6 and t<float(hazard.life)+.05 and distance<3.4:
			escape+=Vector3(delta.x,0,delta.z).normalized()*.9;result.level=maxf(float(result.level),.9)
		elif hazard.kind=="ring":
			var radius:float=2.4+9.5*t
			var arrival:float=(distance-.55-radius)/9.5
			if radius<19 and arrival>-.1 and arrival<horizon and absf(delta.y)<=.8 and distance<_reach_at(hazard.reach,hazard.pos,point)+.3:result.ringIn=maxf(0,arrival) if float(result.ringIn)<0 else minf(float(result.ringIn),maxf(0,arrival))
	if not move_id.is_empty():
		var t:float=move_time-float(_timing[0])
		if move_id=="slam":
			var delta:Vector3=point-Vector3(_move_params.center)
			var distance:float=Vector2(delta.x,delta.z).length()
			if t<.1 and distance<4.5:escape+=Vector3(delta.x,0,delta.z).normalized();result.level=1.0
			var reach:PackedFloat32Array=PackedFloat32Array(_move_params.get("reach",[]))
			if reach.is_empty():reach=_reach(_move_params.center,19)
			if distance<=_reach_at(reach,_move_params.center,point)+.3 and absf(delta.y)<=.8:
				for offset in _move_params.rings:
					var radius:float=2.4+9.5*(t-float(offset))
					var arrival:float=(distance-.55-radius)/9.5
					if radius<19 and arrival>-.1 and arrival<horizon:result.ringIn=maxf(0,arrival) if float(result.ringIn)<0 else minf(float(result.ringIn),maxf(0,arrival))
		elif move_id=="sweep" and t<float(_timing[1]):
			var from:Vector3=_move_params.from
			if Vector2(point.x-from.x,point.z-from.z).length()<18.5:
				var start:float=float(_move_params.a0) if t<0 else lerpf(float(_move_params.a0),float(_move_params.a1),smoothstep(0,1,t/float(_timing[1])))
				var low:float=minf(start,float(_move_params.a1))-.2;var high:float=maxf(start,float(_move_params.a1))+.2
				var angle:float=atan2(point.x-from.x,point.z-from.z)
				while angle<low-PI:angle+=TAU
				while angle>high+PI:angle-=TAU
				if angle>=low and angle<=high:escape-=global_basis.z*.8;result.level=maxf(float(result.level),.8);result.beam=true;result.cover=true
		elif move_id=="charge" and t<float(_timing[1]):
			var delta:Vector3=point-_origin
			var along:float=delta.dot(_direction);var lateral:float=delta.dot(Vector3(_direction.z,0,-_direction.x))
			if along>charge_distance(maxf(0,t),float(_move_params.length),float(_move_params.speed))-3 and along<float(_move_params.length)+5 and absf(lateral)<3.6:escape+=Vector3(_direction.z,0,-_direction.x)*(1 if lateral>=0 else -1);result.level=1.0;result.lane=true
		elif move_id=="frenzy" and t<float(_timing[1]) and Vector2(point.x-_origin.x,point.z-_origin.z).length()<10.8:escape+=Vector3(point.x-_origin.x,0,point.z-_origin.z).normalized()*.9;result.level=maxf(float(result.level),.9);result.cover=true
	escape=escape.normalized();result.ax=escape.x;result.az=escape.z
	return result

func push_actors() -> void:
	if dead or not visible or str(match_node.get("state"))!="playing":return
	for actor in match_node.get("actors"):
		var network=match_node.get("network")
		if is_instance_valid(network) and bool(network.get("active")) and network.has_method("owns_actor") and not bool(network.call("owns_actor",actor)):continue
		if not actor.alive or actor.global_position.y>global_position.y+4.2:continue
		for body:Vector2 in SourceNav.FLOOR_BODY:
			var center:Vector3=global_position+global_basis.z*body.x
			var delta:Vector3=actor.global_position-center;delta.y=0
			var radius:float=body.y+.75
			var distance:float=delta.length()
			if distance>=radius:continue
			var normal:Vector3=delta/distance if distance>.001 else global_basis.z
			actor.global_position.x=center.x+normal.x*radius;actor.global_position.z=center.z+normal.z*radius
			var inward:float=actor.velocity.dot(normal)
			if inward<0:actor.velocity-=normal*inward

func _spawn_crablet(point: Vector3,yaw:float=0.0) -> void:
	var root := Node3D.new()
	match_node.add_child(root)
	root.global_position = point
	root.rotation.y=yaw
	if ResourceLoader.exists("res://assets/characters/crablet.glb"):
		root.add_child(InkAvatar.create_source_asset("crablet", team_color(), _weak_material.albedo_color))
	else:
		_part(root, _ball(0.50), Vector3(0, 0.4, 0), _material)
		_part(root, _box(Vector3(0.9, 0.55, 1.1)), Vector3(0, 0.75, 0), _material)
		for x in [-0.2, 0.2]:
			_part(root, _ball(0.12), Vector3(x, 0.67, 0.45), _weak_material)
	var lighting_stage=match_node.get("stage")
	if is_instance_valid(lighting_stage):
		for property in lighting_stage.get_property_list():
			if str(property.name)=="lighting_theme":
				InkAvatar.configure_source_lighting(root,lighting_stage.get("lighting_theme"))
				break
	var id:int=_crab_sequence
	_crab_sequence+=1
	root.set_meta("crablet_id",id)
	_crablets.append({"id":id,"node": root, "hp": 30.0, "life": 12.0,"dead":false,"retarget":0.0,"target":null,"speed":0.0})
	_event("boss:crablet",{"boss":self,"id":id,"phase":"spawn","pos":point+Vector3.UP*.3})

func damage_crablet(index:int,amount:float,attacker:Node=null,weapon:String="shooter") -> void:
	if index<0 or index>=_crablets.size() or amount<=0.0:return
	var crab:Dictionary=_crablets[index]
	if bool(crab.get("dead",false)) or float(crab.hp)<=0.0:return
	var predicted:bool=_route_network_damage(attacker,amount,weapon,false,index)
	_event("boss:hit",{"boss":self,"damage":amount,"weak":false,"attacker":attacker,"local":is_instance_valid(attacker) and bool(attacker.get("is_local")),"crab":true,"predicted":predicted,"pos":crab.node.global_position+Vector3.UP*.4})
	if predicted:return
	crab.hp=float(crab.hp)-amount
	InkAvatar.hit_source_crablet(crab.node)
	if float(crab.hp)<=0.0:
		if is_instance_valid(attacker) and attacker.get("splats")!=null:attacker.set("splats",int(attacker.get("splats"))+1)
		_pop_crablet(crab,true)

func _pop_crablet(crab:Dictionary,killed:bool) -> void:
	if bool(crab.get("dead",false)):return
	crab.dead=true
	var point:Vector3=crab.node.global_position
	var team:int=0 if killed else 1
	_event("boss:crablet",{"boss":self,"id":int(crab.get("id",-1)),"phase":"pop","pos":point+Vector3.UP*.3,"killed":killed})
	if not killed and str(match_node.get("state"))=="playing":
		for actor in match_node.get("actors"):
			if not actor.alive or actor.team_id!=0 or _safe_spawn(actor):continue
			var delta:Vector3=actor.global_position-point
			if Vector2(delta.x,delta.z).length()<2.1 and absf(delta.y)<1.6:actor.damage(40.0*_damage_scale(),self,"crablet")
	if not _in_pad(point,.3):
		var ground:Dictionary=match_node.call("cast",point+Vector3.UP*.8,point-Vector3.UP*12.0,[])
		if not ground.is_empty() and Vector3(ground.position).y>-5.0:
			match_node.call("paint_splat",Vector3(ground.position)+Vector3.UP*.1,Vector3.UP,1.3 if killed else 1.7,team)
	InkAvatar.update_source_crablet(crab.node,0.0,0.0,true)
	_crab_pops.append({"node":crab.node,"time":0.0})

func _tick_crab_visuals(dt:float) -> void:
	for crab in _crablets:
		if not bool(crab.get("dead",false)) and is_instance_valid(crab.node):InkAvatar.update_source_crablet(crab.node,dt,float(crab.get("speed",0.0)),false)
	for index in range(_crab_pops.size()-1,-1,-1):
		var pop:Dictionary=_crab_pops[index]
		pop.time=float(pop.time)+dt
		if not is_instance_valid(pop.node):_crab_pops.remove_at(index);continue
		var finished:bool=InkAvatar.update_source_crablet(pop.node,dt,0.0,true)
		if finished or float(pop.time)>=.14:
			pop.node.queue_free()
			_crab_pops.remove_at(index)

func _exit_tree() -> void:
	for list in [_hazards,_crablets,_crab_pops]:
		for row in list:
			var node:Node=row.get("node") as Node
			if is_instance_valid(node) and not node.is_queued_for_deletion():node.queue_free()
			var barrel:Node=row.get("barrel") as Node
			if is_instance_valid(barrel) and not barrel.is_queued_for_deletion():barrel.queue_free()

func _tick_crablets(dt: float) -> void:
	for i in range(_crablets.size() - 1, -1, -1):
		var crab: Dictionary = _crablets[i]
		if bool(crab.get("dead",false)):
			_crablets.remove_at(i)
			continue
		crab["life"] -= dt
		var root: Node3D = crab["node"]
		if float(crab.life)<=0.0:
			_pop_crablet(crab,false)
			_crablets.remove_at(i)
			continue
		crab.retarget=float(crab.get("retarget",0.0))-dt
		if float(crab.retarget)<=0.0:
			crab.retarget=.4
			crab.target=null
			var best:float=30.0
			for actor in match_node.get("actors"):
				if not actor.alive or actor.team_id!=0 or _in_pad(actor.global_position,.5):continue
				var distance:float=Vector2(actor.global_position.x-root.global_position.x,actor.global_position.z-root.global_position.z).length()
				if distance<best:best=distance;crab.target=actor
		var target=crab.get("target")
		if not is_instance_valid(target) or not target.alive:target=null
		var moved:bool=false
		if target:
			var dir: Vector3 = target.global_position - root.global_position
			var height_delta:float=dir.y
			dir.y = 0.0
			if dir.length()<1.05 and absf(height_delta)<1.3:
				_pop_crablet(crab,false)
			else:
				var stage = match_node.get("stage")
				var wanted:float=atan2(dir.x,dir.z)
				for offset in [0.0,.5,-.5,1.0,-1.0,1.6,-1.6]:
					var yaw:float=wanted+float(offset)
					var proposed:Vector3=root.global_position+Vector3(sin(yaw),0,cos(yaw))*(5.2 if phase==3 else 4.4)*dt
					if _in_pad(proposed,.8):continue
					if not is_instance_valid(stage) or not stage.has_method("ground_height"):continue
					var height:float=float(stage.call("ground_height",proposed.x,proposed.z,root.global_position.y+.7))
					if not is_finite(height) or height<=Rules.player("waterY",-1.6)+.3 or height<root.global_position.y-1.4:continue
					var solid:Dictionary=match_node.call("cast",root.global_position+Vector3.UP*.3,Vector3(proposed.x,height+.3,proposed.z),[])
					if not solid.is_empty():continue
					proposed.y=lerpf(root.global_position.y,height,minf(1,dt*12))
					root.global_position=proposed
					root.rotation.y+=wrapf(yaw-root.rotation.y,-PI,PI)*minf(1,dt*10)
					moved=true
					break
		crab.speed=lerpf(float(crab.get("speed",0.0)),(5.2 if phase==3 else 4.4) if moved else 0.0,minf(1,dt*8))
		if bool(crab.get("dead",false)) or float(crab.hp)<=0.0:
			if not bool(crab.get("dead",false)):_pop_crablet(crab,true)
			_crablets.remove_at(i)

# Radius/order and weak bias match bossModel.js HIT and Boss.segHit exactly.
const HIT_SPHERES:Array=[
	["shellF",1.8,false,Vector3(0,2.8701,.1952)],
	["shellR",1.8,false,Vector3(0,3.2848,-2.8269)],
	["body",1.05,false,Vector3(0,2.2,2.3)],
	["clawL",.85,false,Vector3(2.02,1.05,4.3)],
	["clawR",.55,false,Vector3(-1.8,1.6,4.3)],
	["eyeL",.4,true,Vector3(.64,3.64,3.1)],
	["eyeR",.4,true,Vector3(-.64,3.64,3.1)],
	["belly",.8,true,Vector3(0,1.25,2.25)],
	["crackL",.7,true,Vector3(1.12,3.5227,-1.4586)],
	["crackR",.7,true,Vector3(-1.12,3.5227,-1.4586)]
]

func hit_shapes() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if dead or not visible or (is_instance_valid(_channels1) and _channels1.position.y<-2.2):return result
	for entry in HIT_SPHERES:
		var socket:String=str(entry[0])
		var active:bool=true
		if socket=="belly":active=stunned or phase>=3 or (is_instance_valid(_channels0) and _channels0.position.z>.5)
		elif socket in ["crackL","crackR"]:active=_tear>.5 if is_instance_valid(_channels1) else phase>=3
		result.append({"socket":socket,"radius":float(entry[1]),"weak":bool(entry[2]),"active":active,"center":get_socket(socket,global_transform*Vector3(entry[3]))})
	return result

func segment_hit(begin:Vector3,finish:Vector3,pad:float=0.0) -> Dictionary:
	var delta:Vector3=finish-begin
	var length_squared:float=maxf(delta.length_squared(),.000000001)
	var best:Dictionary={}
	var best_key:float=INF
	for shape in hit_shapes():
		if not shape.active:continue
		var center:Vector3=shape.center
		var t:float=clampf((center-begin).dot(delta)/length_squared,0.0,1.0)
		var distance_squared:float=(begin+delta*t-center).length_squared()
		var radius:float=float(shape.radius)+pad
		if distance_squared>radius*radius:continue
		var entry:float=maxf(0.0,t-sqrt(maxf(0.0,radius*radius-distance_squared)/length_squared))
		var key:float=entry-(.02 if bool(shape.weak) else 0.0)
		if key>=best_key:continue
		best_key=key
		best={"t":entry,"weak":shape.weak,"point":begin+delta*entry,"distance":sqrt(length_squared)*entry,"socket":shape.socket,"center":center,"radius":shape.radius,"crab":-1}
	for index in _crablets.size():
		var crab:Dictionary=_crablets[index]
		if bool(crab.get("dead",false)) or float(crab.hp)<=0.0:continue
		var center:Vector3=crab.node.global_position+Vector3.UP*.35
		var t:float=clampf((center-begin).dot(delta)/length_squared,0.0,1.0)
		if (begin+delta*t-center).length_squared()>pow(.55+pad,2):continue
		if not best.is_empty() and t>=float(best.t):continue
		best={"t":t,"weak":false,"point":begin+delta*t,"distance":sqrt(length_squared)*t,"center":center,"radius":.55,"crab":index,"socket":"crab"}
	return best

func hit_segment(attacker:Node,hit:Dictionary,amount:float,weapon:String) -> void:
	if hit.is_empty():return
	if int(hit.get("crab",-1))>=0:damage_crablet(int(hit.crab),amount,attacker,weapon)
	else:damage(amount,attacker,weapon,bool(hit.get("weak",false)),hit.get("point"))

func ray_hit(attacker,begin:Vector3,finish:Vector3,amount:float,weapon:String) -> bool:
	var hit:Dictionary=segment_hit(begin,finish,.1 if weapon=="charger" else .09)
	if hit.is_empty():return false
	hit_segment(attacker,hit,amount,weapon)
	return true

func ray_distance(origin:Vector3,direction:Vector3,maximum:float) -> float:
	var best:float=-1.0
	for shape in hit_shapes():
		if not bool(shape.active):continue
		var offset:Vector3=origin-Vector3(shape.center)
		var bq:float=offset.dot(direction)
		var cq:float=offset.length_squared()-float(shape.radius)*float(shape.radius)
		var discriminant:float=bq*bq-cq
		if discriminant<0.0:continue
		var t:float=-bq-sqrt(discriminant)
		if t>0.0 and t<maximum and (best<0.0 or t<best):best=t
	return best

func roll_hit(point:Vector3,forward:Vector3,width:float) -> Dictionary:
	var center:Vector3=point+forward*.8+Vector3.UP*.45
	var radius:float=width*.5+.35
	for index in _crablets.size():
		var crab:Dictionary=_crablets[index]
		if bool(crab.get("dead",false)) or float(crab.hp)<=0.0:continue
		var pos:Vector3=crab.node.global_position
		if absf(pos.y-point.y)>1.0 or Vector2(pos.x-center.x,pos.z-center.z).length()>radius+.4:continue
		return {"crab":index,"point":pos+Vector3.UP*.35,"weak":false}
	var best:Dictionary={}
	var nearest:float=INF
	for shape in hit_shapes():
		if not shape.active or Vector3(shape.center).y-float(shape.radius)>center.y+.7:continue
		var pos:Vector3=shape.center
		var distance:float=Vector2(pos.x-center.x,pos.z-center.z).length()-float(shape.radius)
		if distance<radius and distance<nearest:
			nearest=distance
			best={"crab":-1,"point":Vector3(center.x,maxf(center.y,pos.y-float(shape.radius)*.5),center.z),"weak":shape.weak}
	return best

func splash(attacker,point:Vector3,radius:float,amount:float,weapon:String,minimum:float=-1.0) -> void:
	if dead or not is_instance_valid(attacker) or radius<=0.0:return
	for index in _crablets.size():
		var crab:Dictionary=_crablets[index]
		if bool(crab.get("dead",false)) or float(crab.hp)<=0.0:continue
		if point.distance_to(crab.node.global_position+Vector3.UP*.3)<radius+.4:damage_crablet(index,amount,attacker,weapon)
	var best:Dictionary={}
	var nearest:float=INF
	for shape in hit_shapes():
		if not shape.active or bool(shape.weak):continue
		var distance:float=maxf(0.0,point.distance_to(shape.center)-float(shape.radius))
		if distance<nearest:nearest=distance;best=shape
	if best.is_empty() or nearest>radius:return
	var center:Vector3=best.center
	var surface:Vector3=center.lerp(point,minf(.9,float(best.radius)/maxf(float(best.radius),center.distance_to(point))))
	var cover:Dictionary=match_node.call("cast",point+Vector3.UP*.3,surface,[])
	if not cover.is_empty():return
	damage(lerpf(amount,amount if minimum<0 else minimum,clampf(nearest/radius,0,1)),attacker,weapon,false)

func damage(amount: float, attacker: Node = null, weapon: String = "shooter", weak: bool = false, point:Variant=null) -> void:
	if dead or amount <= 0.0:
		return
	var hit_position:Vector3=point if point is Vector3 else global_position+Vector3.UP*2.0
	if invuln or not visible or (is_instance_valid(match_node) and str(match_node.get("state"))!="playing"):
		if is_instance_valid(attacker) and bool(attacker.get("is_local")):_event("boss:hit",{"boss":self,"attacker":attacker,"damage":0.0,"weak":weak,"local":true,"blocked":true,"pos":hit_position,"has_point":point is Vector3})
		return
	if _route_network_damage(attacker, amount, weapon, weak):
		return
	var multiplier: float = 0.3 if weapon == "roller" else (0.6 if weapon == "slam" else (0.75 if weapon == "bomb" else 1.0))
	amount *= multiplier * (2.5 if weak else 1.0) * (1.25 if stunned else 1.0)
	# applyDamage counts only HP actually removed, including the finishing shot.
	amount = minf(amount,hp)
	if is_instance_valid(attacker):
		if brain:brain.note_damage(attacker,amount)
		attacker.set_meta("boss_damage",float(attacker.get_meta("boss_damage",0.0))+amount)
		if weak:
			attacker.set_meta("weak_hits",int(attacker.get_meta("weak_hits",0))+1)
	hp = maxf(0.0, hp - amount)
	_flash = 1.0
	_event("boss:hit", {"boss": self, "attacker": attacker, "damage": amount, "weak": weak,"local":is_instance_valid(attacker) and bool(attacker.get("is_local")),"pos":hit_position,"has_point":point is Vector3})
	_event("boss:hp", {"boss": self, "hp": hp, "max": max_hp})
	if hp <= 0.0:
		dead = true
		_play_source_clip("boss_dead")
		alive = false
		_beam.visible = false
		_telegraph.visible = false
		for h in _hazards:
			h.node.queue_free()
			if is_instance_valid(h.get("barrel")):h.barrel.queue_free()
		_hazards.clear()
		for crab in _crablets:
			if not bool(crab.get("dead",false)) and is_instance_valid(crab.node):
				_event("boss:fx",{"boss":self,"name":"retire","pos":crab.node.global_position+Vector3.UP*.3})
				crab.dead=true;InkAvatar.update_source_crablet(crab.node,0,0,true)
				_crab_pops.append({"node":crab.node,"time":0.0})
		_crablets.clear()
		_event("boss:defeat", {"boss": self, "by": attacker})
		_event("shake",{"amount":.9,"pos":global_position})
		_rain_pending.clear()

func rain(attacker:Node,point:Vector3,radius:float,amount:float) -> void:
	if dead or not is_instance_valid(attacker) or amount<=0.0:return
	if Vector2(global_position.x-point.x,global_position.z-point.z).length()>radius+2.4:return
	var key:int=attacker.get_instance_id()
	if not _rain_pending.has(key):_rain_pending[key]={"actor":attacker,"amount":0.0}
	_rain_pending[key].amount+=amount

func _flush_rain(dt:float) -> void:
	_rain_time-=dt
	if _rain_time>0.0 or _rain_pending.is_empty():return
	_rain_time=.3
	for row in _rain_pending.values():
		if is_instance_valid(row.actor):damage(float(row.amount),row.actor,"storm",false)
	_rain_pending.clear()

func _route_network_damage(attacker, amount: float, weapon: String, weak: bool, crab: int = -1) -> bool:
	var network = match_node.get("network") if is_instance_valid(match_node) else null
	return is_instance_valid(network) and network.get("active") and network.has_method("send_boss_hit") and network.call("send_boss_hit", attacker, amount, weapon, weak, crab)

func _damage_scale() -> float:
	return 0.7 if difficulty == "easy" else (1.2 if difficulty == "hard" else 1.0)

func _safe_spawn(actor) -> bool:
	return _in_pad(actor.global_position,.6)

func _in_pad(point:Vector3,margin:float=0.0) -> bool:
	var stage=match_node.get("stage")
	if is_instance_valid(stage):
		var layout:Dictionary=stage.get("layout")
		var radius:float=float(layout.get("spawnBarrier",4.2))+margin
		for pad in layout.get("spawnPads",[]):
			if Vector2(point.x-float(pad[0]),point.z-float(pad[2])).length()<radius:return true
		return false
	var fallback:Vector3=match_node.call("spawn_for",0,0)
	return Vector2(point.x-fallback.x,point.z-fallback.z).length()<4.2+margin

func _damage_radius(point:Vector3,radius:float,amount:float,cause:String,height:float=2.0) -> void:
	for actor in match_node.get("actors"):
		if not actor.alive or actor.team_id!=0 or _safe_spawn(actor):continue
		var delta:Vector3=actor.global_position-point
		if Vector2(delta.x,delta.z).length()<radius and (absf(delta.y)<height if cause=="boss_barrel" else delta.y<height):actor.damage(amount*_damage_scale(),self,cause)

func _paint(point: Vector3, radius: float) -> void:
	if _in_pad(point,.3):return
	var hit:Dictionary=match_node.call("cast",point+Vector3.UP*1.5,point-Vector3.UP*2.5,[])
	if not hit.is_empty() and Vector3(hit.position).y>=Rules.player("waterY",-3.2):
		var area:float=match_node.call("paint_splat",Vector3(hit.position)+Vector3(hit.normal)*.08,hit.normal,radius,1)
		add_turf(area)

func add_turf(area: float) -> void:
	turf_points += maxf(0.0, area)

func get_socket(socket: String, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var node = _source_sockets.get(socket)
	return node.global_position if is_instance_valid(node) else fallback

func _play_source_clip(wanted: String,actual_duration:float=-1.0,restart:bool=false) -> void:
	if not _source_anim or (_source_clip == wanted and not restart):
		return
	var variant:String="boss_p%s_%s"%[phase,wanted.trim_prefix("boss_")] if phase>1 else wanted
	var selected:String=wanted
	for clip in _source_anim.get_animation_list():
		if str(clip).get_slice("/",str(clip).get_slice_count("/")-1)==variant:selected=variant;break
	for clip in _source_anim.get_animation_list():
		if str(clip).get_slice("/", str(clip).get_slice_count("/") - 1) == selected:
			_source_anim.play(clip, 0.12)
			_source_clip = wanted
			_source_events.play(selected,actual_duration,phase)
			_source_anim.speed_scale=_source_events.scale
			return

func _dispatch_source_hook(hook:Dictionary) -> void:
	var socket:String=str(hook.get("socket",""))
	var point:Vector3=get_socket(socket,global_position)
	var kind:String=str(hook.kind)
	var strength:float=float(hook.get("strength",1.0))
	if kind=="foot":
		var raw:Array=hook.get("pos",[0,0,0])
		var local_point:=Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
		# The baked run root advanced at 3 m/s; keep only its procedural local foot placement.
		if _source_clip=="boss_run":local_point.z-=float(hook.time)*3.0
		point=global_transform*local_point
		_event("boss:foot",{"boss":self,"leg":int(hook.get("leg",0)),"pos":point,"strength":strength})
		if strength>.5:_event("shake",{"amount":.12*strength,"pos":point})
	elif kind=="impact":
		if socket=="clawL":point.y=global_position.y+.05
		elif socket=="body":point.y=global_position.y+.2
		_event("boss:impact",{"boss":self,"socket":socket,"pos":point,"strength":strength})
		_event("shake",{"amount":.5*strength,"pos":point})
	else:
		_event("boss:fx",{"boss":self,"name":str(hook.get("name","")),"socket":socket,"pos":point,"data":hook.get("data")})

func _event(kind: String, data: Dictionary = {}) -> void:
	Rules.emit_event(match_node, kind, data)
