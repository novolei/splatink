class_name InkActor
extends CharacterBody3D

const Rules = preload("res://scripts/game/ink_rules.gd")
const SourcePhysics=preload("res://scripts/game/ink_actor_physics.gd")

var match_node: Node
var team_id: int = 0
var is_local: bool = false
var weapon_id: String = "shooter"
var display_name: String = "Squidkid"
var style: Dictionary = {}
var hp: float = 100.0
var ink: float = 100.0
var special_charge: float = 0.0
var splats: int = 0
var deaths: int = 0
var turf_points: float = 0.0
var alive: bool = true
var form: String = "kid"
var charge: float = 0.0
var aim_yaw: float = 0.0
var aim_pitch: float = 0.0
var aim_dir: Vector3 = Vector3(0, 0, 1)
var aim_point: Vector3 = Vector3.ZERO
var desired_velocity: Vector3 = Vector3.ZERO
var desired_facing: Vector3 = Vector3(0, 0, 1)
var firing: bool = false
var rolling: bool = false
var climbing: bool = false
var submerged: bool = false
var ground_team: int = -1
var respawn_timer: float = 0.0
var invuln: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO
var avatar: Node3D
var weapon_state: Dictionary = {}
var spawn_index: int = 0
var last_attacker: Node
var special_active: String = ""
var super_jump_state: Dictionary = {}
var clock: float = 0.0
var land_time: float = 99.0
var land_speed: float = 0.0
var smooth_y:float=0.0
var smooth_y_velocity:float=0.0
var hurt_flash:float=0.0
var fire_facing:float=0.0
var _face_target=null
var _ground_sampler: Callable = Callable()
var source_physics:InkActorPhysics
var grounded:bool=false
var _source_motion:InkActorPhysics.Motion=SourcePhysics.Motion.new()
var _remote_grounded:bool=false
var _remote_grounded_set:bool=false

var _capsule: CapsuleShape3D
var _collider: CollisionShape3D
var _last_damage: float = 10.0
var _last_fire: float = 10.0
var _damage_from_ink: float = 0.0
var _jump_buffer: float = 0.0
var _fire_buffer: float = 0.0
var _coyote: float = 0.0
var _emerge: float = 1.0
var _hard_land: float = 0.0
var _prev: Dictionary = {}
var _swim_press: float = -1.0
var _fire_press: float = -1.0
var _facing_velocity: float = 0.0
var _special_time: float = 0.0
var _special_start: Vector3
var _special_phase: String = ""
var _step_clock: float = 0.0
var _last_empty_click: float = -100.0
var _low_ink_announced: bool = false
var _climb_speed: float = 0.0
var _climb_exit: float = 0.0

func configure(game: Node, team: int, local_player: bool, selected_weapon: String, look: Dictionary) -> void:
	match_node = game
	team_id = team
	is_local = local_player
	weapon_id = selected_weapon
	style = look.duplicate(true)
	var ground_stage = game.get("stage")
	if is_instance_valid(ground_stage) and ground_stage.has_method("ground_height"):
		_ground_sampler = Callable(ground_stage,"ground_height")
	configure_source_physics(ground_stage)
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = acos(0.68)
	floor_snap_length = Rules.player("stepDown", 0.45)
	floor_stop_on_slope = true
	max_slides = 6
	safe_margin = 0.015
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Rules.player("radius", 0.38)
	_capsule.height = Rules.player("height", 1.45)
	_collider = CollisionShape3D.new()
	_collider.shape = _capsule
	_collider.position.y = _capsule.height * 0.5
	add_child(_collider)
	var avatar_script = load("res://scripts/characters/ink_avatar.gd")
	if avatar_script:
		avatar = avatar_script.new()
		add_child(avatar)
		if avatar.has_method("configure"):
			avatar.call("configure", team_color(), weapon_id, style)
	reset_weapon()

func team_color() -> Color:
	if is_instance_valid(match_node):
		var colors = match_node.get("team_colors")
		if colors is Array and colors.size() > team_id:
			return colors[team_id]
	return Color("ff8a14") if team_id == 0 else Color("2f5bff")

func enemy_color() -> Color:
	if is_instance_valid(match_node):
		var colors=match_node.get("team_colors")
		if colors is Array and colors.size()>1-team_id:return colors[1-team_id]
	return Color("2f5bff") if team_id==0 else Color("ff8a14")

func is_grounded() -> bool:
	if _remote_grounded_set:return _remote_grounded
	return grounded if source_physics else is_on_floor()

func set_remote_grounded(value:bool) -> void:
	_remote_grounded_set=true;_remote_grounded=value;grounded=value

func configure_source_physics(stage:Node,geometry:Dictionary={}) -> bool:
	source_physics=null
	if not is_instance_valid(stage):return false
	var level_blocks=stage.get("blocks");var level_faces=stage.get("faces")
	if not level_blocks is Array or level_blocks.is_empty() or not level_faces is Array:return false
	var source_geometry:Dictionary=geometry.duplicate()
	if not source_geometry.has("physics_fields"):
		var id=stage.get("stage_id")
		var path:String="res://assets/actor_physics/%s.bin"%str(id)
		if not FileAccess.file_exists(path):return false
		source_geometry.physics_fields=path
	source_physics=SourcePhysics.new()
	source_physics.configure(stage,stage.get("level_queries") as InkLevelQueries,source_geometry)
	_source_motion=SourcePhysics.Motion.new();grounded=false
	return true

func _sync_source_motion() -> void:
	_source_motion.position=global_position;_source_motion.velocity=velocity
	_source_motion.grounded=grounded;_source_motion.smooth_y=smooth_y

func _apply_source_motion() -> void:
	global_position=_source_motion.position;velocity=_source_motion.velocity
	grounded=_source_motion.grounded;smooth_y=_source_motion.smooth_y
	if _source_motion.landed:
		_source_surface()
		_on_land(-_source_motion.land_speed)

func _source_surface() -> void:
	ground_team=-1
	var ground:InkActorPhysics.GroundHit=_source_motion.ground
	if not grounded or not ground.hit or ground.face<0:return
	var stage=match_node.get("stage")
	var grid=stage.get("grid") if is_instance_valid(stage) else null
	if grid is PackedByteArray:
		var face:Dictionary=source_physics.faces[ground.face]
		if face.has("grid") and float(face.get("cu",0))>0 and float(face.get("cv",0))>0:
			var index:int=int(face.grid)+clampi(int(ground.v/float(face.cv)),0,int(face.nv)-1)*int(face.nu)+clampi(int(ground.u/float(face.cu)),0,int(face.nu)-1)
			if index>=0 and index<grid.size():ground_team=int(grid[index])-1
			return
	var point:Vector3=global_position;point.y=ground.y
	ground_team=int(match_node.call("sample_ink",point,ground.normal))

func _source_probe_ground() -> void:
	source_physics.ground_probe(global_position,.4,.35,Rules.player("footRadius",.24),_source_motion.ground,form=="squid")
	_source_surface()

func _source_resolve(previous_y:float,stick:bool) -> void:
	_sync_source_motion()
	source_physics.resolve(global_position,velocity,form=="squid",previous_y,stick,grounded,smooth_y,_source_motion)
	_apply_source_motion()

func _controller_move(dt:float,stick:bool=false,force_air:bool=false) -> void:
	if source_physics:
		var previous_y:float=global_position.y
		global_position+=velocity*dt
		if force_air:grounded=false
		_source_resolve(previous_y,stick)
	else:move_and_slide()

func controller_cast(from:Vector3,to:Vector3,skip_grates:bool=false) -> Dictionary:
	if not source_physics:return match_node.call("cast",from,to,[get_rid()],1 if skip_grates else 5)
	var direction:Vector3=to-from;var distance:float=direction.length()
	if distance<=.000001:return {}
	var hit:InkActorPhysics.Hit=source_physics.raycast(from,direction/distance,distance,null,skip_grates)
	return {"position":hit.position,"normal":hit.normal,"block":hit.block,"face":hit.face,"u":hit.u,"v":hit.v} if hit.hit else {}

func _controller_ink(hit:Dictionary) -> int:
	if hit.is_empty():return -1
	if not source_physics:return int(match_node.call("sample_ink",hit.position,hit.normal))
	var id:int=int(hit.get("face",-1))
	if id<0:return -1
	var face:Dictionary=source_physics.faces[id]
	var stage=match_node.get("stage");var grid=stage.get("grid") if is_instance_valid(stage) else null
	if grid is PackedByteArray and face.has("grid"):
		if int(face.grid)<0 or float(face.get("cu",0))<=0 or float(face.get("cv",0))<=0:return -1
		var index:int=int(face.grid)+clampi(int(float(hit.v)/float(face.cv)),0,int(face.nv)-1)*int(face.nu)+clampi(int(float(hit.u)/float(face.cu)),0,int(face.nu)-1)
		return int(grid[index])-1 if index>=0 and index<grid.size() else -1
	return int(match_node.call("sample_ink",hit.position,hit.normal))

func reset_weapon() -> void:
	charge = 0.0
	rolling=false;firing=false
	weapon_state = {"cooldown": 0.0, "hold": false, "windup": -1.0, "burst": 0.0, "dodge": 0.0, "rolls": 0, "lock": 0.0, "roll_dir": Vector3.ZERO, "hand": 0, "bloom": 0.0, "roll_distance": 0.0, "flick_armed": true,"firing_time":0.0,"flick_recover":0.0,"roll_time":0.0}

func weapon_busy() -> bool:
	return charge>0 or float(weapon_state.get("windup",-1))>=0 or float(weapon_state.get("burst",0))>0 or float(weapon_state.get("dodge",0))>0 or float(weapon_state.get("lock",0))>0

func weapon_firing_pose() -> bool:
	return float(weapon_state.get("firing_time",0))>0 or weapon_busy() or rolling

func weapon_move_speed() -> float:
	var weapon:Dictionary=Rules.weapon(weapon_id)
	var run:float=Rules.player("runSpeed",6.0)
	var firing_speed:float=float(weapon.get("moveSpeedFiring",run))
	if float(weapon_state.get("lock",0))>0:return 0.0
	if float(weapon_state.get("burst",0))>0:return firing_speed
	if charge>0 and weapon_id=="splatling":return lerpf(run*.75,float(weapon.get("moveSpeedCharging",2.4)),minf(1,charge*2.5))
	if float(weapon_state.get("windup",-1))>=0 and weapon_id=="slosher":return firing_speed*.7
	if rolling:return lerpf(float(weapon.get("rollSpeed",5.2))*.5,float(weapon.get("rollSpeed",5.2)),smoothstep(0,.45,float(weapon_state.get("roll_time",0))))
	if float(weapon_state.get("windup",-1))>=0:return lerpf(firing_speed,firing_speed*.45,clampf(float(weapon_state.windup)/float(weapon.get("flickWindup",.22)),0,1))
	if float(weapon_state.get("flick_recover",0))>0:return lerpf(run,firing_speed*.6,float(weapon_state.flick_recover)/.18)
	if charge>0:return lerpf(run*.7,firing_speed,minf(1,charge*3))
	return firing_speed if float(weapon_state.get("firing_time",0))>0 else run

func set_weapon(id: String) -> void:
	weapon_id = id
	reset_weapon()
	if avatar and avatar.has_method("set_weapon"):
		avatar.call("set_weapon", id)
	elif avatar and avatar.has_method("configure"):
		avatar.call("configure", team_color(), id, style)

func spawn_at(where: Vector3, yaw: float = 0.0) -> void:
	global_position = where
	rotation.y = yaw
	aim_yaw = yaw
	aim_pitch = 0.0
	aim_dir = Vector3(sin(yaw),0,cos(yaw))
	velocity = Vector3.ZERO
	grounded=false;_remote_grounded_set=false;_source_motion=SourcePhysics.Motion.new()
	smooth_y=0.0;smooth_y_velocity=0.0
	hp = Rules.player("hp", 100.0)
	ink = Rules.player("inkMax", 100.0)
	special_charge = 0.0
	alive = true
	visible = true
	form = "kid"
	climbing = false
	submerged = false
	special_active = ""
	super_jump_state.clear()
	invuln = Rules.player("spawnInvuln", 1.6)
	_last_damage = 10.0
	_last_fire = 99.0
	last_attacker = null
	respawn_timer = 0.0
	_damage_from_ink = 0.0
	hurt_flash=0.0;fire_facing=0.0;_face_target=null;_facing_velocity=0.0
	land_time=99.0;land_speed=0.0;_hard_land=0.0;_coyote=0.0;_jump_buffer=0.0;_fire_buffer=0.0;_emerge=99.0;_climb_speed=0.0;_climb_exit=0.0
	_last_empty_click=-100.0;_low_ink_announced=false
	_prev.clear()
	ground_team = -1
	reset_weapon()
	if source_physics:
		source_physics.ground_probe(global_position,.3,.3,Rules.player("footRadius",.24),_source_motion.ground)
		if _source_motion.ground.hit and absf(_source_motion.ground.y-global_position.y)<.3:
			global_position.y=_source_motion.ground.y;grounded=true
		_sync_source_motion()
	if avatar:
		avatar.visible = true
		avatar.position.y=0.0
		if avatar.has_method("reset_presentation"):avatar.call("reset_presentation")

func respawn() -> void:
	var point: Vector3 = match_node.call("spawn_for", team_id, spawn_index)
	var stage = match_node.get("stage")
	if is_instance_valid(stage):
		var layout:Dictionary=stage.get("layout")
		var pads:Array=layout.get("spawnPads",[])
		if pads.size()>team_id:
			var pad=pads[team_id]
			point=Vector3(float(pad[0]),float(pad[1]),float(pad[2])) if pad is Array else pad
	var angle:float=float(spawn_index)/4.0*TAU+.6
	var spawn_point:Vector3=point+Vector3(cos(angle)*1.1,4.5,sin(angle)*1.1)
	spawn_at(spawn_point, 0.0 if team_id == 0 else PI)
	velocity.y = -4.0
	trigger("spawn")
	_event("respawn", {"actor": self, "pos": global_position,"ground_pos":Vector3(spawn_point.x,point.y,spawn_point.z)})

func special_cost() -> float:
	return float(Rules.weapon(weapon_id).get("specialCost", 190.0))

func special_fraction() -> float:
	return clampf(special_charge / special_cost(), 0.0, 1.0)

func add_turf(area: float, fill_special: bool = true) -> void:
	if area <= 0.0:
		return
	turf_points += area
	var was_ready: bool = special_fraction() >= 1.0
	if fill_special and special_active.is_empty():
		special_charge = minf(special_cost(), special_charge + area)
	_event("turf", {"actor": self, "area": area})
	if not was_ready and special_fraction() >= 1.0:
		_event("special_ready", {"actor": self})

func spend_ink(amount: float) -> bool:
	if ink < amount:
		if is_local and clock - _last_empty_click > 0.45:
			_event("empty_click", {"actor": self})
			_event("low_ink", {"actor": self})
			_last_empty_click = clock
		return false
	ink -= amount
	_last_fire = 0.0
	return true

func damage(amount: float, attacker: Node = null, cause: String = "weapon") -> bool:
	if not alive or invuln > 0.0 or amount <= 0.0:
		return false
	var network = match_node.get("network") if is_instance_valid(match_node) else null
	if is_instance_valid(network) and network.get("active") and network.has_method("send_hit") and network.call("send_hit", attacker, self, amount, cause):
		return false
	if special_active == "slam":
		amount *= 0.25
	hp -= amount
	_last_damage = 0.0
	hurt_flash=minf(1.0,hurt_flash+amount/60.0)
	if is_instance_valid(attacker):last_attacker = attacker
	if cause!="ink":
		var incoming:Vector3=attacker.global_position-global_position if is_instance_valid(attacker) and attacker is Node3D and attacker!=self else Vector3.BACK
		var local:Vector3=incoming.rotated(Vector3.UP,-rotation.y);local.y=0;local=local.normalized() if local.length_squared()>.000001 else Vector3.ZERO
		trigger("hit", {"x":local.x,"z":local.z,"amp":clampf(amount / 60.0, 0.4, 1.2)})
	_event("damage", {"victim": self, "attacker": attacker, "amount": amount, "source": cause, "pos": global_position})
	if hp <= 0.0:
		splat(attacker, cause)
		return true
	return false

func take_damage(amount: float, attacker: Node = null, cause: String = "weapon") -> bool:
	return damage(amount, attacker, cause)

func splat(attacker: Node = null, cause: String = "weapon") -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	deaths += 1
	respawn_timer = Rules.player("respawnTime", 5.5)
	special_charge *= 0.5
	special_active = ""
	super_jump_state.clear()
	climbing=false
	velocity = Vector3.ZERO
	reset_weapon()
	if avatar:
		avatar.visible = false
	if is_instance_valid(attacker) and attacker is InkActor:
		attacker.splats += 1
		var area: float = match_node.call("paint_splat", global_position + Vector3.UP * 0.35, Vector3.UP, 1.7, attacker.team_id)
		attacker.add_turf(area)
	_event("splatted", {"victim": self, "attacker": attacker, "cause": cause, "pos": global_position, "team": team_id})

## Called by the match's physics loop. No automatic physics tick: ownership is explicit.
func tick(dt: float, command: Dictionary) -> void:
	clock += dt
	land_time += dt
	desired_velocity = Vector3.ZERO
	if not alive:
		respawn_timer -= dt
		if respawn_timer <= 0.0 and str(match_node.get("state"))=="playing":
			respawn()
		return
	invuln = maxf(0.0, invuln - dt)
	_last_damage += dt
	_last_fire += dt
	_emerge += dt
	hurt_flash=maxf(0,hurt_flash-dt*.6)
	_hard_land = maxf(0.0, _hard_land - dt/maxf(.001,Rules.player("hardLandTime",.16)))
	var jump_pressed: bool = bool(command.get("jump", false)) and not bool(_prev.get("jump", false))
	var fire_pressed: bool = bool(command.get("fire", false)) and not bool(_prev.get("fire", false))
	var swim_pressed: bool = bool(command.get("swim", false)) and not bool(_prev.get("swim", false))
	var special_pressed: bool = bool(command.get("special", false)) and not bool(_prev.get("special", false))
	var sub_released: bool = bool(command.get("sub_released", false)) or (bool(_prev.get("sub", false)) and not bool(command.get("sub", false)))
	if swim_pressed:
		_swim_press = clock
	if fire_pressed:
		_fire_press = clock
	_jump_buffer = Rules.player("jumpBuffer", 0.13) if jump_pressed else maxf(0.0, _jump_buffer - dt)
	_fire_buffer = Rules.player("fireBuffer", 0.16) if fire_pressed else maxf(0.0, _fire_buffer - dt)
	_prev = command.duplicate()
	aim_dir = command.get("aim_dir", Vector3(sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), cos(aim_yaw) * cos(aim_pitch)))
	if aim_dir.length_squared() > 0.01:
		aim_dir = aim_dir.normalized()
		aim_yaw = float(command.get("aim_yaw", atan2(aim_dir.x, aim_dir.z)))
		aim_pitch = float(command.get("aim_pitch", asin(clampf(aim_dir.y, -1.0, 1.0))))
	aim_point = command.get("aim_point", global_position + Vector3.UP * 0.92 + aim_dir * float(Rules.weapon(weapon_id).get("range", 12.5)))
	if not super_jump_state.is_empty():
		_tick_super_jump(dt)
		_face(dt,command.get("move",Vector3.ZERO))
		_animate(dt)
		return
	if not special_active.is_empty():
		_tick_special(dt)
		_face(dt,command.get("move",Vector3.ZERO))
		_animate(dt)
		return
	if special_pressed and special_fraction() >= 1.0:
		start_special()
		_face(dt,command.get("move",Vector3.ZERO))
		_animate(dt)
		return
	if source_physics:_source_surface()
	else:
		var ground_hit: Dictionary = match_node.call("cast", global_position + Vector3.UP * 0.3, global_position - Vector3.UP * 0.55, [get_rid()], collision_mask)
		var ground_point: Vector3 = ground_hit.get("position", global_position)
		var normal: Vector3 = ground_hit.get("normal", Vector3.UP)
		ground_team = int(match_node.call("sample_ink", ground_point, normal))
	var fire_wins: bool = (bool(command.get("fire", false)) or _fire_buffer > 0.0) and _fire_press >= _swim_press
	var want_swim: bool = bool(command.get("swim", false)) and not fire_wins and not weapon_busy()
	var previous_form: String = form
	form = "squid" if want_swim else "kid"
	if previous_form != form:
		_emerge = 0.0
		_event("squid_in" if want_swim else "squid_out", {"actor": self, "pos": global_position})
	submerged = want_swim and is_grounded() and ground_team == team_id
	var on_enemy: bool = ground_team >= 0 and ground_team != team_id and is_grounded()
	var desired_move: Vector3 = command.get("move", Vector3.ZERO)
	desired_move.y = 0.0
	if desired_move.length() > 1.0:
		desired_move = desired_move.normalized()
	_update_capsule(want_swim)
	var was_grounded: bool = is_grounded()
	var previous_vy: float = velocity.y
	var previous_foot_y:float=global_position.y
	_coyote = Rules.player("coyoteTime", 0.12) if was_grounded else _coyote - dt
	var max_speed: float = Rules.player("swimSpeed", 11.8) if submerged else (Rules.player("squidDrySpeed", 2.9) if want_swim else weapon_move_speed())
	if on_enemy:
		max_speed = minf(max_speed,Rules.player("enemyInkSpeed", 1.9))
	if _hard_land > 0.0 and not want_swim:
		max_speed *= lerpf(1.0,Rules.player("hardLandSlow", 0.72),_hard_land)
	desired_velocity = desired_move * max_speed
	desired_facing = Vector3(sin(aim_yaw), 0, cos(aim_yaw)) if bool(command.get("fire",false)) or charge > 0 else (desired_move.normalized() if desired_move.length_squared() > .01 else global_basis.z)
	var steering_move:Vector3=Vector3.ZERO if float(weapon_state.get("lock",0))>0 and was_grounded else desired_move
	var was_climbing:bool=climbing
	if source_physics:climbing=_try_climb(want_swim,desired_move,dt,command)
	var horizontal: Vector3 = horizontal_velocity(steering_move, max_speed, want_swim, on_enemy, is_grounded(), dt)
	if float(weapon_state.get("lock", 0.0)) > 0.0 and was_grounded:
		horizontal = Vector3.ZERO
	if float(weapon_state.get("dodge", 0.0)) > 0.0:
		var u: float = clampf(1.0 - float(weapon_state["dodge"]) / 0.3, 0.0, 1.0)
		horizontal = weapon_state.get("roll_dir", Vector3.ZERO) * 14.0 * (1.0 - u * u)
	if _jump_buffer>0 and weapon_id == "dualies" and not want_swim and (float(weapon_state.get("firing_time",0))>0 or bool(command.get("fire", false))) and desired_move.length_squared() >= .09 and was_grounded and not bool(command.get("sub",false)):
		if match_node.get("projectiles").call("try_dodge", self, desired_move):
			_jump_buffer = 0.0
	if not source_physics or not climbing:
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	if not source_physics:climbing = _try_climb(want_swim, desired_move, dt, command)
	if climbing!=was_climbing:_event("actor:climb",{"actor":self,"on":climbing})
	var jumped:bool=false
	if not climbing:
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = (Rules.player("swimJumpVel", 9.4) if submerged else Rules.player("jumpVel", 8.4)) * (0.72 if on_enemy else 1.0)
			_jump_buffer = 0.0
			_coyote = 0.0
			jumped=true
			if source_physics:grounded=false
			trigger("jump")
			_event("actor:jump", {"actor": self, "pos": global_position, "swim": submerged})
		if not source_physics:
			if jumped or not was_grounded:velocity.y=air_vertical_velocity(velocity.y,dt)
			else:
				var floor_normal:Vector3=get_floor_normal()
				velocity.y=-(velocity.x*floor_normal.x+velocity.z*floor_normal.z)/maxf(.35,floor_normal.y)
			_try_step_up(horizontal, dt)
	if source_physics:
		_sync_source_motion()
		source_physics.integrate(_source_motion,dt,want_swim,jumped,climbing,desired_move)
		_apply_source_motion()
	else:
		var step_y:float=global_position.y-previous_foot_y
		move_and_slide()
		var floor_delta:float=global_position.y-previous_foot_y-step_y
		if is_on_floor():
			if was_grounded and absf(floor_delta)>.06 and get_floor_normal().y>.99:smooth_y-=floor_delta
			elif not was_grounded and floor_delta>.035:smooth_y-=floor_delta
	_spawn_barrier()
	if not source_physics and is_on_floor() and not was_grounded:
		_on_land(previous_vy)
	if on_enemy:
		var d: float = minf(Rules.player("enemyInkDps", 20.0) * dt, maxf(0.0, Rules.player("enemyInkDamageCap", 40.0) - _damage_from_ink))
		if invuln <= 0.0:
			_damage_from_ink += d
			hp = maxf(1.0, hp - d)
			hurt_flash=minf(1.0,hurt_flash+dt*.5)
		_last_damage = minf(_last_damage, 0.4)
	else:
		_damage_from_ink = maxf(0.0, _damage_from_ink - dt * 30.0)
	if _last_damage > Rules.player("regenDelay", 1.3):
		hp = minf(100.0, hp + (Rules.player("regenRateSwim", 60.0) if submerged else Rules.player("regenRate", 22.0)) * dt)
	var was_full: bool = ink >= 100.0
	if submerged or climbing:
		ink = minf(100.0, ink + Rules.player("inkRefillSwim", 42.0) * dt)
	elif want_swim:
		ink = minf(100.0, ink + Rules.player("inkRefillKid", 9.0) * 0.5 * dt)
	elif _last_fire > Rules.player("inkRefillDelay", 0.9) and not weapon_busy():
		ink = minf(100.0, ink + Rules.player("inkRefillKid", 9.0) * dt)
	if ink > 15.0:
		_low_ink_announced = false
	if not was_full and ink >= 100.0:
		_event("refill_full", {"actor": self})
	var weapon_cmd: Dictionary = command.duplicate()
	weapon_cmd["fire_pressed"] = fire_pressed or _fire_buffer > 0.0
	weapon_cmd["sub_released"] = sub_released and not want_swim
	weapon_cmd["fire"] = not want_swim and _emerge >= Rules.player("emergeDelay", 0.07) and (bool(command.get("fire", false)) or _fire_buffer > 0.0)
	weapon_cmd["sub"] = bool(command.get("sub", false)) and not want_swim
	if bool(weapon_cmd["fire"]):
		_fire_buffer = 0.0
	var manager = match_node.get("projectiles")
	if manager:
		manager.call("tick_actor", self, dt, weapon_cmd)
	if global_position.y < Rules.player("fallDeathY", -1.45):
		var safe_deck:bool=is_finite(source_physics.queries.ground_height(global_position.x,global_position.z,global_position.y+.6)) if source_physics else not match_node.call("cast",global_position+Vector3.UP*.3,global_position-Vector3.UP*2.0,[get_rid()]).is_empty()
		if not safe_deck:
			splat(last_attacker if _last_damage < 4.0 else null, "water")
			return
	_face(dt, desired_move, bool(weapon_cmd["fire"]))
	_animate(dt)

## Source speed-and-heading steering: turns carve without losing ground speed; squid air preserves momentum.
func air_vertical_velocity(vertical:float,dt:float) -> float:
	var gravity:float=Rules.player("gravity",25.0)
	if vertical<0:gravity*=Rules.player("fallGravityMul",1.2)
	if absf(vertical)<Rules.player("apexBand",1.6):gravity*=Rules.player("apexGravityMul",.82)
	return maxf(-Rules.player("maxFall",40.0),vertical-gravity*dt)

func horizontal_velocity(movement: Vector3, top_speed: float, squid: bool, enemy: bool, grounded: bool, dt: float) -> Vector3:
	var current := Vector3(velocity.x, 0, velocity.z)
	var speed: float = current.length()
	var magnitude: float = minf(1.0, movement.length())
	if not grounded:
		var target: float = maxf(Rules.player("squidDrySpeed", 2.9), speed) if squid else maxf(top_speed, Rules.player("airMinSpeed", 4.6))
		var accel: float = Rules.player("squidAirAccel", 14.0) if squid else Rules.player("airAccel", 20.0)
		var decel: float = Rules.player("squidAirDecel", 3.0) if squid else Rules.player("airDecel", 4.0)
		return current.move_toward(movement.normalized() * target * magnitude if magnitude > 0.01 else Vector3.ZERO, (accel if magnitude > 0.01 else decel) * dt)
	var accel: float = Rules.player("swimAccel", 64.0) if submerged else (Rules.player("squidAccel", 34.0) if squid else Rules.player("runAccel", 70.0))
	var ease_in: float = Rules.player("swimAccelIn", 0.75) if submerged else (0.6 if squid else Rules.player("runAccelIn", 0.5))
	var in_knee: float = 3.0 if submerged else (1.0 if squid else Rules.player("runInKnee", 1.6))
	var out_knee: float = Rules.player("swimOutKnee", 0.22) if submerged else (0.3 if squid else Rules.player("runOutKnee", 0.28))
	var decel: float = Rules.player("swimDecel", 42.0) if submerged else (Rules.player("squidDecel", 26.0) if squid else Rules.player("runDecel", 58.0))
	var decel_min: float = 0.5 if squid else Rules.player("runDecelMin", 0.4)
	var decel_knee: float = 4.0 if submerged else (2.0 if squid else Rules.player("runDecelKnee", 2.2))
	var turn: float = Rules.player("swimTurn", 11.0) if submerged else (Rules.player("squidTurn", 13.0) if squid else Rules.player("turnRate", 15.0))
	if enemy:
		accel = minf(accel, Rules.player("enemyInkAccel", 30.0))
		decel = Rules.player("enemyInkDecel", 30.0)
	if magnitude < 0.01:
		var brake: float = decel * lerpf(decel_min, 1.0, smoothstep(0.0, decel_knee, speed)) * dt
		return current * maxf(0.0, speed - brake) / maxf(0.0001, speed)
	var target_direction: Vector3 = movement.normalized()
	var direction: Vector3 = current / speed if speed > 0.05 else target_direction
	var angle: float = acos(clampf(direction.dot(target_direction), -1.0, 1.0))
	if speed > 0.5 and angle > Rules.player("reverseAngle", 2.2):
		return current.move_toward(target_direction * top_speed * magnitude, maxf(Rules.player("reverseDecel", 78.0), decel) * dt * (0.5 if enemy else 1.0))
	var max_turn: float = turn * (1.0 + Rules.player("turnRateSlow", 1.5) * (1.0 - smoothstep(0.0, top_speed, speed)))
	var rotation_step: float = minf(angle, max_turn * dt)
	var turn_sign: float = 1.0 if direction.z * target_direction.x - direction.x * target_direction.z >= 0.0 else -1.0
	direction = direction.rotated(Vector3.UP, rotation_step * turn_sign)
	var wanted: float = top_speed * magnitude
	var next_speed: float
	if speed < wanted:
		var rate: float = accel * lerpf(ease_in, 1.0, smoothstep(0.0, in_knee, speed)) * clampf((wanted - speed) / maxf(0.001, out_knee * top_speed), Rules.player("runOutMin", 0.22), 1.0)
		next_speed = minf(wanted, speed + rate * dt)
	else:
		next_speed = maxf(wanted, speed - decel * lerpf(decel_min, 1.0, smoothstep(0.0, decel_knee, speed - wanted)) * dt)
	return direction * next_speed

func _update_capsule(squid: bool) -> void:
	var target_height: float = 0.55 if squid else 1.45
	collision_mask = 1 if squid else 5
	if not _capsule or not _collider:return
	if not source_physics and is_equal_approx(_capsule.height, target_height):
		return
	if source_physics:
		var radius:float=Rules.player("radius",.38)
		var lift:float=Rules.player("squidBodyLift",.16) if squid else Rules.player("stepUp",.35)
		var bottom:float=lift+radius;var top:float=maxf(bottom,target_height-radius)
		_capsule.radius=radius;_capsule.height=top-bottom+radius*2.0
		_collider.position.y=(bottom+top)*.5
	else:
		_capsule.radius = 0.25 if squid else 0.38
		_capsule.height = target_height
		_collider.position.y = target_height * 0.5

func _on_land(previous_vertical:float) -> void:
	land_time=0.0
	land_speed=maxf(0.0,-previous_vertical)
	if land_speed>Rules.player("hardLandSpeed",11.5):
		_hard_land=clampf((land_speed-Rules.player("hardLandSpeed",11.5))/6.0+.5,0.0,1.0)
	if land_speed>3.0:
		trigger("land",land_speed)
		_event("actor:land",{"actor":self,"pos":global_position,"speed":land_speed,"surface":ground_team})

func _spawn_barrier() -> void:
	var stage = match_node.get("stage")
	if not stage:
		return
	var layout = stage.get("layout")
	if not layout is Dictionary or not layout.has("spawnPads"):
		return
	var pad: Array = layout["spawnPads"][1 - team_id]
	var center := Vector3(float(pad[0]), float(pad[1]), float(pad[2]))
	var delta: Vector3 = global_position - center
	var distance: float = Vector2(delta.x, delta.z).length()
	var radius: float = float(layout.get("spawnBarrier", 4.2))
	if global_position.y > center.y - 1.0 and distance < radius:
		var direction: Vector3 = Vector3(delta.x, 0, delta.z).normalized() if distance > 0.01 else Vector3(0, 0, 1)
		global_position.x = center.x + direction.x * radius
		global_position.z = center.z + direction.z * radius
		var inward:float=velocity.dot(direction)
		if inward<0.0:velocity-=direction*inward*1.6

func _try_step_up(horizontal: Vector3, dt: float) -> void:
	if not is_on_floor() or horizontal.length_squared() < 0.1:
		return
	var forward: Vector3 = horizontal.normalized() * 0.45
	var low: Dictionary = match_node.call("cast", global_position + Vector3.UP * 0.08, global_position + Vector3.UP * 0.08 + forward, [get_rid()])
	if low.is_empty():
		return
	var high: Dictionary = match_node.call("cast", global_position + Vector3.UP * 0.38, global_position + Vector3.UP * 0.38 + forward, [get_rid()])
	if high.is_empty():
		var top: Dictionary = match_node.call("cast", global_position + forward + Vector3.UP * 0.38, global_position + forward + Vector3.UP * 0.04, [get_rid()])
		if not top.is_empty() and Vector3(top.get("normal", Vector3.UP)).y > 0.68:
			var next_y:float=float(top["position"].y)+.015
			var delta_y:float=next_y-global_position.y
			global_position.y=next_y
			if absf(delta_y)>.06:smooth_y-=delta_y

func _try_climb(squid: bool, movement: Vector3, dt: float, cmd: Dictionary) -> bool:
	_climb_exit = maxf(0.0, _climb_exit - dt)
	if not squid or _climb_exit > 0.0:
		_climb_speed = 0.0
		return false
	if not climbing and movement.length() < 0.2:
		return false
	var direction: Vector3 = -wall_normal if climbing else movement.normalized()
	direction.y = 0.0
	var start: Vector3 = global_position + Vector3.UP * 0.3
	var hit: Dictionary = controller_cast(start,start+direction*(Rules.player("radius",.38)+.35))
	if hit.is_empty():
		if climbing:
			_ledge_pop(direction)
		return false
	var normal: Vector3 = hit["normal"]
	var inked: bool = absf(normal.y) < 0.5 and _controller_ink(hit)==team_id
	var into: float = -movement.normalized().dot(normal) if movement.length() > 0.01 else 0.0
	if not climbing and (not inked or into <= Rules.player("climbAttachDot", 0.5)):
		return false
	if not inked:
		velocity.y = minf(velocity.y, 1.5)
		velocity += normal * 1.2
		_climb_speed = 0.0
		_climb_exit = 0.2
		return false
	if into < Rules.player("climbDetachDot", -0.45):
		velocity = normal * 3.2 + Vector3.UP * 3.2
		_climb_speed = 0.0
		_climb_exit = 0.3
		return false
	if not climbing:
		_climb_speed = maxf(0.0, velocity.y)
	wall_normal = normal
	var upper: Dictionary = controller_cast(global_position+Vector3.UP*.85,global_position+Vector3.UP*.85+direction*(Rules.player("radius",.38)+.45))
	var capped: bool = not upper.is_empty() and absf(Vector3(upper["normal"]).y) < 0.5 and _controller_ink(upper)!=team_id
	var want: float = 0.0 if capped else Rules.player("climbSpeed", 7.5) * clampf(into, 0.0, 1.0) * minf(1.0, movement.length())
	if upper.is_empty() and want > 0.0:
		want = minf(want, sqrt(2.0 * Rules.player("gravity", 25.0) * Rules.player("apexGravityMul", 0.82) * (Rules.player("ledgePopClear", 0.42) + 0.3)))
	_climb_speed = move_toward(_climb_speed, want, Rules.player("climbAccel", 46.0) * dt * (1.0 if want > _climb_speed else 1.6))
	var side: Vector3 = movement - normal * movement.dot(normal)
	velocity = side * Rules.player("climbSideSpeed", 5.2) - normal * 1.2
	velocity.y = _climb_speed
	return true

func _ledge_pop(direction: Vector3) -> void:
	var probe: Vector3 = global_position + direction * 0.70 + Vector3.UP * 1.4
	var top_hit: Dictionary = controller_cast(probe,probe-Vector3.UP*2.0,true)
	var top: float = float(top_hit["position"].y) if not top_hit.is_empty() and Vector3(top_hit["normal"]).y > 0.68 else global_position.y + 0.3
	var rise: float = maxf(0.25, top + Rules.player("ledgePopClear", 0.42) - global_position.y)
	velocity = direction * Rules.player("ledgePopCarry", 2.5)
	velocity.y = maxf(sqrt(2.0 * Rules.player("gravity", 25.0) * Rules.player("apexGravityMul", 0.82) * rise), minf(_climb_speed, 6.5))
	_climb_speed = 0.0
	_climb_exit = 0.3
	if source_physics:grounded=false
	_event("actor:ledgepop", {"actor": self, "pos": global_position})

func _face(dt: float, movement: Vector3, _aim: bool=false) -> void:
	fire_facing=maxf(0,fire_facing-dt)
	var target=null
	var speed:float=Vector2(velocity.x,velocity.z).length()
	var omega:float=Rules.player("faceOmega",20)
	var rate:float=Rules.player("faceMaxRate",12.5)
	var max_acc:float=Rules.player("faceMaxAcc",170)
	if not special_active.is_empty() or not super_jump_state.is_empty():
		if speed>.6:target=atan2(velocity.x,velocity.z)
	elif weapon_firing_pose() or fire_facing>0 or bool(_prev.get("sub",false)):
		target=aim_yaw;omega=Rules.player("aimFaceOmega",36);rate=Rules.player("aimFaceMaxRate",24);max_acc=Rules.player("aimFaceMaxAcc",380)
	elif climbing:target=atan2(-wall_normal.x,-wall_normal.z);omega=26;rate=18
	else:
		if Vector2(movement.x,movement.z).length()>.2:target=atan2(movement.x,movement.z)
		elif speed>.6:target=atan2(velocity.x,velocity.z)
		if form!="kid":omega=Rules.player("squidFaceOmega",26);rate=Rules.player("swimFaceMaxRate",14) if submerged else Rules.player("squidFaceMaxRate",17);max_acc=Rules.player("squidFaceMaxAcc",260)
	var target_rate:float=0.0
	if target!=null and _face_target!=null:
		var difference:float=wrapf(float(target)-float(_face_target),-PI,PI)
		if absf(difference)<.12:target_rate=clampf(difference/maxf(dt,.0001),-rate,rate)
	_face_target=target
	var acceleration:float=-2*omega*_facing_velocity if target==null else omega*omega*wrapf(float(target)-rotation.y,-PI,PI)+2*omega*(target_rate-_facing_velocity)
	_facing_velocity=clampf(_facing_velocity+clampf(acceleration,-max_acc,max_acc)*dt,-rate,rate)
	if absf(_facing_velocity)<.00001:_facing_velocity=0
	rotation.y=wrapf(rotation.y+_facing_velocity*dt,-PI,PI)

func _animate(dt: float) -> void:
	smooth_visual(dt)
	if not avatar or not avatar.has_method("animate"):
		return
	if avatar.has_method("restore_presentation"):avatar.call("restore_presentation")
	avatar.position.y=smooth_y
	var local_move: Vector3 = global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var intent: Dictionary = {"desired_velocity": desired_velocity, "desired_facing": desired_facing, "moving": desired_velocity.length_squared() > .01,"ground_sampler":_ground_sampler}
	var state: Dictionary = {"time": clock, "is_local": is_local, "velocity": velocity, "hurt": 1.0 - hp / 100.0, "speed": Vector2(velocity.x, velocity.z).length(), "local_move": Vector2(local_move.x, local_move.z), "localMove": {"x": local_move.x, "z": local_move.z}, "grounded": is_grounded(), "vy": velocity.y, "aim_pitch": aim_pitch, "aimPitch": aim_pitch, "firing": firing, "charge": charge, "rolling": rolling, "form": "swim" if submerged else form, "wall_normal": wall_normal, "wallNormal": wall_normal, "ink": ink / 100.0, "low_ink": ink < 15.0, "lowInk": ink < 15.0, "special": special_fraction(), "invuln": invuln > 0.0, "hp": hp / 100.0, "turnRate": _facing_velocity, "subAim": bool(_prev.get("sub", false)), "surface": 1 if ground_team == team_id else (2 if ground_team >= 0 else 0)}
	state.merge(intent)
	state["aim_dir"]=aim_dir;state["aim_point"]=aim_point;state["aim_yaw"]=aim_yaw
	state["hurt_flash"]=hurt_flash;state["hurtFlash"]=hurt_flash
	state["hurt_color"]=enemy_color()
	state["superJump"]=not super_jump_state.is_empty()
	state["form"]="climb" if climbing else ("swim" if submerged else form)
	state["hurt"]=maxf(hurt_flash,1.0-hp/Rules.player("hp",100.0)) if hp<Rules.player("hp",100.0) else 0.0
	state["low_ink"]=ink<18;state["lowInk"]=ink<18
	state["subAim"]=bool(weapon_state.get("aiming_sub",false))
	avatar.call("animate", dt, state)
	if is_grounded() and form == "kid" and state["speed"] > 1.0:
		_step_clock += dt * float(state["speed"])
		if _step_clock > 1.8:
			_step_clock = 0.0
			_event("actor:footstep", {"actor": self, "pos": global_position, "surface": state["surface"]})

func smooth_visual(dt:float) -> void:
	var acceleration:float=-24.0*24.0*smooth_y-2.0*24.0*smooth_y_velocity
	smooth_y_velocity+=acceleration*dt
	smooth_y+=smooth_y_velocity*dt
	smooth_y=clampf(smooth_y,-.7,.7)
	if absf(smooth_y)<.0001 and absf(smooth_y_velocity)<.001:smooth_y=0.0;smooth_y_velocity=0.0

func visual_position() -> Vector3:
	return global_position+Vector3.UP*smooth_y

## Camera-only opt-in presentation pose. Gameplay retains visual_position and tick muzzle caches.
func presentation_position() -> Vector3:
	if avatar and avatar.has_method("presentation_position") and avatar.get("presentation_active")==true:
		return avatar.call("presentation_position")
	return visual_position()

func trigger(kind: String, arg = null) -> void:
	if avatar and avatar.has_method("trigger"):
		avatar.call("trigger", kind, arg)

func start_special() -> void:
	special_charge = 0.0
	special_active = str(Rules.weapon(weapon_id).get("special", "slam"))
	_special_time = 0.0
	_special_start = global_position
	form = "kid"
	climbing = false
	submerged = false
	reset_weapon()
	var throw_pitch:float=clampf(aim_pitch+.28,-.3,1.1)
	var throw_velocity:=Vector3(sin(aim_yaw)*cos(throw_pitch)*16.0+velocity.x*.4,sin(throw_pitch)*16.0+1.5,cos(aim_yaw)*cos(throw_pitch)*16.0+velocity.z*.4)
	_event("special_activate", {"actor": self, "special": special_active, "pos": global_position,"throw_velocity":throw_velocity,"muzzle":global_position+Vector3.UP*1.45,"dir":throw_velocity.normalized()})
	if special_active == "storm":
		_special_phase = "throw"
		trigger("throw")
		var manager = match_node.get("projectiles")
		if manager:
			manager.call("throw_storm", self)
	else:
		_special_phase = "rise"
		velocity = Vector3(velocity.x * 0.3, 11.5, velocity.z * 0.3)
		if source_physics:grounded=false
		trigger("special_leap")

func _tick_special(dt: float) -> void:
	_special_time += dt
	if special_active == "storm":
		velocity.x *= exp(-6.0 * dt)
		velocity.z *= exp(-6.0 * dt)
		var stick:bool=is_grounded()
		velocity.y = 0.0 if stick else velocity.y - Rules.player("gravity", 25.0) * dt
		_controller_move(dt,stick)
		if _special_time > 0.35:
			special_active = ""
		return
	var slam: Dictionary = Rules.section("SPECIALS").get("slam", {})
	if _special_phase == "rise":
		velocity.y -= Rules.player("gravity", 25.0) * 0.9 * dt
		var move: Vector3 = _prev.get("move", Vector3.ZERO)
		velocity.x = lerpf(velocity.x, move.x * 2.5, 1.0 - exp(-6.0 * dt))
		velocity.z = lerpf(velocity.z, move.z * 2.5, 1.0 - exp(-6.0 * dt))
		if _special_time > float(slam.get("rise", 0.55)):
			_special_phase = "hang"
			_special_time = 0.0
			velocity = Vector3(0, 0.6, 0)
	elif _special_phase == "hang":
		velocity.y = 0.4
		if _special_time > float(slam.get("hang", 0.25)):
			_special_phase = "fall"
			_special_time = 0.0
			velocity = Vector3(0, -34, 0)
			trigger("special_slam")
	else:
		velocity.y = -34.0
	_controller_move(dt,false,true)
	if _special_phase == "fall" and (is_grounded() or _special_time > 1.2):
		var manager = match_node.get("projectiles")
		if manager:
			manager.call("explode", global_position, self, float(slam.get("radius", 5.2)), float(slam.get("damageMax", 180.0)), float(slam.get("damageMin", 55.0)), float(slam.get("radius", 5.2)), "slam")
		_event("special:slam", {"actor": self, "pos": global_position, "radius": slam.get("radius", 5.2)})
		special_active = ""
		invuln = 0.3

func can_super_jump() -> bool:
	return alive and special_active.is_empty() and super_jump_state.is_empty() and is_instance_valid(match_node) and str(match_node.get("state"))=="playing"

func super_jump(target) -> bool:
	if not can_super_jump():
		return false
	super_jump_state = {"target": target, "phase": "charge", "time": 0.0, "from": global_position, "to": global_position, "duration": 1.15}
	form = "squid"
	if climbing:_event("actor:climb",{"actor":self,"on":false})
	climbing=false;_climb_speed=0.0
	reset_weapon()
	_event("superjump", {"actor": self, "phase": "charge", "pos": global_position})
	return true

func _tick_super_jump(dt: float) -> void:
	super_jump_state["time"] += dt
	var t: float = float(super_jump_state["time"])
	if super_jump_state["phase"] == "charge":
		velocity = Vector3.ZERO
		form="squid"
		if source_physics:_source_probe_ground()
		if t <= 0.75:
			return
		var target = super_jump_state["target"]
		if target is InkActor and (not is_instance_valid(target) or not target.alive):
			super_jump_state.clear()
			return
		var destination: Vector3 = target.global_position if target is Node3D else target
		if target is InkActor:
			var offset:Vector3=global_position-target.global_position;offset.y=0
			var distance:float=offset.length()
			var near:Vector3=target.global_position+offset/maxf(.000001,distance)*1.1+Vector3.UP*.6
			var landing:Dictionary=controller_cast(near,near-Vector3.UP*2.5)
			if not landing.is_empty() and Vector3(landing.normal).y>.6 and (not source_physics or not source_physics.point_inside(Vector3(landing.position)+Vector3.UP*.5,.3)):
				destination=landing.position
		super_jump_state["from"]=global_position
		super_jump_state["to"] = destination
		super_jump_state["phase"] = "flight"
		super_jump_state["time"] = 0.0
		super_jump_state["duration"] = 1.15 + minf(0.6, global_position.distance_to(destination) / 80.0)
		invuln = maxf(invuln,float(super_jump_state["duration"]) + 0.2)
		_event("superjump", {"actor": self, "phase": "flight", "pos": global_position, "to": destination})
		return
	var k: float = minf(1.0, t / float(super_jump_state["duration"]))
	var a: Vector3 = super_jump_state["from"]
	var b: Vector3 = super_jump_state["to"]
	var horizontal_k:float=2*k*k if k<.5 else 1.0-pow(-2*k+2,2)/2
	var next_position:Vector3=a.lerp(b,horizontal_k)+Vector3.UP*sin(PI*pow(k,.86))*(11.0+a.distance_to(b)*.08)
	velocity=(next_position-global_position)/maxf(dt,.001)
	global_position=next_position
	form = "kid" if k > 0.82 else "squid"
	if k >= 1.0:
		super_jump_state.clear()
		velocity = Vector3(0, -12, 0)
		form="kid";_emerge=.05
		if source_physics:
			grounded=false
			_source_resolve(global_position.y+.4,false)
			if not grounded:
				grounded=true;_source_resolve(global_position.y,true)
				if not grounded:velocity.y=-6
		else:
			trigger("land", 12.0);land_time=0.0;land_speed=12.0
		add_turf(float(match_node.call("paint_splat", global_position + Vector3.UP * 0.3, Vector3.UP, 1.4, team_id)))
		if is_local:
			_event("shake",{"amount":.35})
		_event("superjump:land", {"actor": self, "pos": global_position})
		if avatar and avatar.has_method("reset_presentation"):
			# Reset the teleport history after the landing event without erasing
			# the absorption impulse that the production ground resolve just fired.
			avatar.position.y=smooth_y;avatar.call("reset_presentation",true)

func _event(kind: String, data: Dictionary = {}) -> void:
	Rules.emit_event(match_node, kind, data)


