class_name InkWeapons
extends Node3D

const Rules = preload("res://scripts/game/ink_rules.gd")
const Cloud = preload("res://scripts/game/ink_cloud.gd")
const AimQueries = preload("res://scripts/game/ink_player_controller.gd")
const CAPACITY: int = 256

var match_node: Node
var bullets: Array[Dictionary] = []
var storms: Array[Dictionary] = []
var _mesh_pool: Array[MeshInstance3D] = []
var _sphere: SphereMesh
var _bomb_geometry: SphereMesh
var _bomb_cap: CylinderMesh
var _bomb_cap_material: StandardMaterial3D
var _materials: Array[StandardMaterial3D] = []
var _attack_id: int = 0
var _hit_records: Dictionary = {}
var clock: float = 0.0
var _replaying: bool = false
var _replay_muzzle: Vector3 = Vector3.ZERO
var _replay_direction: Vector3 = Vector3.BACK

func configure(game: Node) -> void:
	match_node = game
	_sphere = SphereMesh.new()
	_sphere.radius = 0.10
	_sphere.height = 0.20
	_sphere.radial_segments = 10
	_sphere.rings = 5
	_bomb_geometry=SphereMesh.new()
	_bomb_geometry.radius=.2;_bomb_geometry.height=.4;_bomb_geometry.radial_segments=20;_bomb_geometry.rings=14
	_bomb_cap=CylinderMesh.new()
	_bomb_cap.top_radius=.07;_bomb_cap.bottom_radius=.09;_bomb_cap.height=.12;_bomb_cap.radial_segments=12
	_bomb_cap_material=StandardMaterial3D.new()
	_bomb_cap_material.albedo_color=Color("2a2a30");_bomb_cap_material.roughness=.4;_bomb_cap_material.metallic=.6
	for i in range(2):
		var material := StandardMaterial3D.new()
		var colors = game.get("team_colors")
		material.albedo_color = colors[i] if colors is Array and colors.size() > i else (Color("ff8a14") if i == 0 else Color("2f5bff"))
		material.roughness = 0.18
		material.clearcoat_enabled = true
		material.clearcoat = 0.8
		_materials.append(material)
	for i in range(CAPACITY):
		var instance := MeshInstance3D.new()
		instance.mesh = _sphere
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visible = false
		add_child(instance)
		_mesh_pool.append(instance)

func clear() -> void:
	for b in bullets:
		_release_visual(b)
	bullets.clear()
	for storm in storms:
		if is_instance_valid(storm.get("node")):
			storm["node"].queue_free()
	storms.clear()
	_hit_records.clear()

func tick_actor(actor, dt: float, cmd: Dictionary) -> void:
	if not actor.alive:
		return
	var state: Dictionary = actor.weapon_state
	var was_dodging:bool=float(state["dodge"])>0
	state["cooldown"] = float(state["cooldown"]) - dt
	if not was_dodging:state["lock"] = maxf(0.0, float(state["lock"]) - dt)
	state["dodge"] = maxf(0.0, float(state["dodge"]) - dt)
	state["firing_time"]=maxf(0,float(state.get("firing_time",0))-dt)
	state["flick_recover"]=maxf(0,float(state.get("flick_recover",0))-dt)
	if not bool(cmd.get("fire", false)) and float(state["dodge"]) <= 0.0 and int(state["rolls"]) > 0 and float(state["lock"]) <= 0.0:
		state["rolls"] = 0
	var fire: bool = bool(cmd.get("fire", false))
	if not fire:
		state["bloom"] = maxf(0.0, float(state["bloom"]) - dt / 0.28)
	var released: bool = not fire and bool(state["hold"])
	var weapon: Dictionary = Rules.weapon(actor.weapon_id)
	actor.rolling = false
	if was_dodging:
		actor.fire_facing=.5;state["firing_time"]=.35
		state["roll_paint"] = float(state.get("roll_paint", 0.0)) - dt
		if float(state["roll_paint"]) <= 0.0:
			state["roll_paint"] = 0.045
			if actor.is_grounded():_paint(actor, actor.global_position + Vector3.UP * 0.3, Vector3.UP, 0.62,{"kind":"trail"})
		if float(state["dodge"])<=0:state["lock"]=float(weapon.get("lockTime",.5))
		state["hold"] = fire
		_tick_sub(actor,cmd)
		actor.firing=actor.weapon_firing_pose()
		return
	if actor.weapon_id=="dualies" and float(state["lock"])>0:actor.fire_facing=.5;state["firing_time"]=maxf(.3,float(state["firing_time"]))
	if float(state["windup"]) >= 0.0:
		state["windup"] += dt
		actor.fire_facing=.4 if actor.weapon_id=="roller" else .5
		if actor.weapon_id=="slosher":state["firing_time"]=.35
		if actor.weapon_id == "roller" and float(state["windup"]) >= float(weapon.get("flickWindup", 0.22)):
			_flick(actor, weapon)
			state["windup"] = -1.0
			state["firing_time"]=.25;state["flick_recover"]=.18
		elif actor.weapon_id == "slosher" and float(state["windup"]) >= float(weapon.get("windup", 0.13)):
			_slosh(actor, weapon)
			state["windup"] = -1.0
		state["hold"]=fire;_tick_sub(actor,cmd);actor.firing=actor.weapon_firing_pose()
		return
	match actor.weapon_id:
		"charger":
			if fire and float(state["cooldown"]) <= 0.0 and (float(state.get("charge_time",0))>0 or actor.ink >= float(weapon.get("inkFull", 18.0)) * 0.2):
				state["charge_time"] = minf(1.0, float(state.get("charge_time", 0.0)) + dt / float(weapon.get("chargeTime", 1.0)))
				var ct: float = float(state["charge_time"])
				actor.charge = minf(clampf(actor.ink / float(weapon.get("inkFull", 18.0)), 0.0, 1.0), ct * 1.25 if ct < 0.2 else 0.25 + (ct - 0.2) * 0.9375)
				actor.fire_facing=.4
				if actor.charge >= 1.0 and float(state.get("full_announced", 0.0)) == 0.0:
					state["full_announced"] = 1.0
					_event("charger_full", {"actor": actor, "pos": actor.global_position})
			elif float(state.get("charge_time",0))>0:
				_charger(actor, weapon)
				actor.charge = 0.0
				state["charge_time"] = 0.0
				state["cooldown"] = 0.28
				state["full_announced"] = 0.0
				state["firing_time"]=.35
		"splatling":
			var was_streaming:bool=float(state["burst"])>0
			if fire and not was_streaming and (actor.charge>0 or actor.ink>=float(weapon.get("inkPerShot",.6))*5) and float(state["cooldown"]) <= 0.0:
				actor.charge = minf(1.0, actor.charge + dt / float(weapon.get("chargeTime", 0.85)))
				actor.fire_facing=.45
				if actor.charge >= 1.0 and not bool(state.get("full_announced", false)):
					state["full_announced"] = true
					_event("splatling_ready", {"actor": actor, "pos": actor.global_position})
			elif not was_streaming and actor.charge>0:
				state["burst"] = lerpf(float(weapon.get("burstMin", 0.3)), float(weapon.get("burstMax", 1.7)), actor.charge)
				state["burst_duration"] = state["burst"]
				state["cooldown"] = 0.0
				state["bloom"]=0.0
			if was_streaming:
				state["burst"] = maxf(0.0, float(state["burst"]) - dt)
				actor.charge = float(state["burst"]) / maxf(0.01, float(state.get("burst_duration", 1.7)))
				state["firing_time"]=.3;actor.fire_facing=.5
				var burst_guard: int = 0
				while float(state["cooldown"]) <= 0.0 and burst_guard < 3 and actor.ink>=float(weapon.get("inkPerShot",.6)) and float(state["burst"])>0:
					burst_guard += 1
					_shot(actor, weapon, "splatling")
				if actor.ink < 0.6:
					state["burst"] = 0.0
				if float(state["burst"]) <= 0.0:
					actor.charge = 0.0
					state["full_announced"] = false
					state["cooldown"] = maxf(0.22, float(state["cooldown"]))
					_event("splatling_wind", {"actor": actor, "pos": actor.global_position})
		"roller":
			if fire and float(state["windup"]) < 0.0:
				if bool(cmd.get("fire_pressed", false)) and float(state["cooldown"]) <= 0.0:
					if actor.spend_ink(float(weapon.get("flickInk", 9.0))):
						state["windup"] = 0.0
						state["cooldown"] = float(weapon.get("flickInterval", 0.62))
						actor.trigger("flick")
				elif actor.is_grounded() and float(state["cooldown"]) <= 0.25:
					_roll(actor, weapon, dt)
			if not actor.rolling:state["roll_time"]=0.0
		"slosher":
			if float(state["windup"])>=0:state["firing_time"]=.35;actor.fire_facing=.5
			if fire and float(state["cooldown"]) <= 0.0 and float(state["windup"]) < 0.0:
				if actor.spend_ink(float(weapon.get("inkPerShot", 7.5))):
					state["windup"] = 0.0
					state["cooldown"] = float(weapon.get("fireInterval", 0.62))
					actor.trigger("shoot")
					state["firing_time"]=.35;actor.fire_facing=.5
					_event("slosh_throw", {"actor": actor, "pos": _muzzle(actor)})
		_:
			if fire:state["firing_time"]=.35;actor.fire_facing=.5
			var guard: int = 0
			while fire and float(state["cooldown"]) <= 0.0 and guard < 3:
				guard += 1
				_shot(actor, weapon, actor.weapon_id)
	if not fire and float(state["burst"]) <= 0.0:
		state["cooldown"] = maxf(0.0, float(state["cooldown"]))
	state["hold"] = fire
	_tick_sub(actor,cmd)
	actor.firing=actor.weapon_firing_pose()

func _tick_sub(actor,cmd:Dictionary) -> void:
	var state:Dictionary=actor.weapon_state
	if bool(cmd.get("sub",false)) and not bool(state.get("aiming_sub",false)):
		state["aiming_sub"]=true
		if actor.ink<70 and actor.is_local:_event("low_ink",{"actor":actor,"need":70})
	if bool(state.get("aiming_sub",false)):actor.fire_facing=.3
	if bool(cmd.get("sub_released",false)) and bool(state.get("aiming_sub",false)):
		state["aiming_sub"]=false
		if actor.ink>=70 and actor.spend_ink(70):_spawn_bomb(actor)
	if not bool(cmd.get("sub",false)) and not bool(cmd.get("sub_released",false)):state["aiming_sub"]=false

func try_dodge(actor, direction: Vector3) -> bool:
	var state: Dictionary = actor.weapon_state
	var weapon:Dictionary=Rules.weapon(actor.weapon_id)
	if actor.weapon_id != "dualies" or not actor.alive or actor.form=="squid" or direction.length()<.3 or int(state["rolls"])>=int(weapon.get("rolls",2)) or float(state["dodge"]) > 0.0 or not actor.spend_ink(float(weapon.get("rollInk",7))):
		return false
	state["rolls"] += 1
	state["dodge"] = 0.30
	state["lock"] = 0.0
	state["roll_dir"] = direction.normalized()
	state["cooldown"] = 0.30
	var local_dir: Vector3 = actor.global_basis.inverse() * Vector3(state["roll_dir"])
	actor.trigger("dodge", {"x": local_dir.x, "z": local_dir.z, "t": 0.3})
	_event("weapon:dodge", {"actor": actor, "pos": actor.global_position, "dir": direction})
	_event("dualies_roll", {"actor": actor, "pos": actor.global_position})
	return true

func _muzzle(actor) -> Vector3:
	if _replaying:return _replay_muzzle
	var center:Vector3=actor.global_position+Vector3.UP*(.4 if actor.form=="squid" else 1.05)
	var origin:Vector3=center+actor.aim_dir*.3
	if actor.avatar and actor.avatar.has_method("get_muzzle"):
		origin=actor.avatar.call("get_muzzle")
		var ready:float=float(actor.avatar.call("aim_ready")) if actor.avatar.has_method("aim_ready") else 1.0
		if ready<.98 and actor.avatar.has_method("get_aim_muzzle"):
			origin=origin.lerp(actor.avatar.call("get_aim_muzzle",actor.aim_pitch),1.0-ready)
	if not origin.is_finite() or origin.distance_squared_to(center)>2.5:
		return center+actor.aim_dir*.3
	if not _world_cast(actor,center,origin,true).is_empty():
		return center+actor.aim_dir*.3
	return origin

func _muzzle_hand(actor,hand:int) -> Vector3:
	if _replaying:return _replay_muzzle
	var center:Vector3=actor.global_position+Vector3.UP*1.05
	if hand!=0 and actor.avatar and actor.avatar.has_method("get_muzzle_hand"):
		var physical:Vector3=actor.avatar.call("get_muzzle_hand",1)
		if physical.is_finite() and physical.distance_squared_to(center)<2.5:return physical
	var origin:Vector3=_muzzle(actor)
	if hand==0:return origin
	var local:Vector3=(origin-actor.global_position).rotated(Vector3.UP,-actor.rotation.y)
	local.x=-local.x
	origin=actor.global_position+local.rotated(Vector3.UP,actor.rotation.y)
	if not _world_cast(actor,center,origin,true).is_empty():return center+actor.aim_dir*.3
	return origin

func _world_cast(actor,from:Vector3,to:Vector3,skip_grates:bool=true) -> Dictionary:
	if is_instance_valid(actor) and actor.has_method("controller_cast"):
		return actor.call("controller_cast",from,to,skip_grates)
	var excluded:Array=[actor.get_rid()] if is_instance_valid(actor) and actor is PhysicsBody3D else []
	return match_node.call("cast",from,to,excluded,1 if skip_grates else 5)

func _world_los(actor,from:Vector3,to:Vector3) -> bool:
	# Physics.los clips the final five centimeters and lets ink pass grates.
	# A nonpositive clipped ray cannot contain a source hit.
	var direction:Vector3=to-from
	var distance:float=direction.length()
	if distance<=.05:return true
	return _world_cast(actor,from,from+direction*((distance-.05)/distance),true).is_empty()

func _aim_from(actor,origin:Vector3) -> Vector3:
	var delta:Vector3=actor.aim_point-origin
	return actor.aim_dir if delta.length()<2.0 or delta.dot(actor.aim_dir)<0.0 else delta.normalized()

func _spread(direction:Vector3,degrees:float) -> Vector3:
	if degrees<=0.0:return direction
	var radius:float=deg_to_rad(degrees)*sqrt(randf())
	var angle:float=randf()*TAU
	var tangent:=Vector3(-direction.z,0,direction.x)
	if tangent.length_squared()<.0001:tangent=Vector3.RIGHT
	tangent=tangent.normalized()
	var vertical:Vector3=direction.cross(tangent)
	return (direction+tangent*cos(angle)*tan(radius)+vertical*sin(angle)*tan(radius)*.55).normalized()

func spread_degrees(w:Dictionary,kind:String,grounded:bool,bloom:float,locked:bool=false) -> float:
	if kind=="blaster":return float(w.get("spread",1.2)) if grounded else float(w.get("spreadAir",4.0))
	if kind=="dualies" and locked:return float(w.get("spreadLock",2.2))
	var base:float=float(w.get("spreadGround",5.5)) if grounded else float(w.get("spreadAir",11.0))
	return base*lerpf(float(w.get("spreadFirst",.45)),1.0,bloom)

## Match the source's 60 Hz integrator when compensating the muzzle-to-reticle arc.
func ballistic_direction(origin: Vector3, direction: Vector3, target: Vector3, speed: float, straight: float, gravity: float, drag: float, max_distance: float) -> Vector3:
	var horizontal_distance: float = Vector2(target.x - origin.x, target.z - origin.z).length()
	var horizontal_direction: float = Vector2(direction.x, direction.z).length()
	if horizontal_distance < 1.5 or horizontal_distance > max_distance or gravity == 0.0 or horizontal_direction < 0.0001:
		return direction
	var height: float = target.y - origin.y
	var original_pitch: float = atan2(direction.y, horizontal_direction)
	var p0: float = original_pitch
	var e0: float = trajectory_height(p0, horizontal_distance, speed, straight, gravity, drag) - height
	if absf(e0) < 0.01:
		return direction
	var p1: float = p0 - atan2(e0, horizontal_distance)
	var e1: float = trajectory_height(p1, horizontal_distance, speed, straight, gravity, drag) - height
	for iteration in range(4):
		if absf(e1) < 0.005 or absf(e1 - e0) < 0.000001:
			break
		var p2: float = p1 - e1 * (p1 - p0) / (e1 - e0)
		p0 = p1
		e0 = e1
		p1 = clampf(p2, -1.2, 1.2)
		e1 = trajectory_height(p1, horizontal_distance, speed, straight, gravity, drag) - height
	if absf(e1) > 0.25 or absf(p1 - original_pitch) > 0.35:
		return direction
	return Vector3(direction.x / horizontal_direction * cos(p1), sin(p1), direction.z / horizontal_direction * cos(p1))

func trajectory_height(pitch: float, distance: float, speed: float, straight: float, gravity: float, drag: float) -> float:
	const STEP: float = 1.0 / 60.0
	var vh: float = cos(pitch) * speed
	var vy: float = sin(pitch) * speed
	var x: float = 0.0
	var y: float = 0.0
	var age: float = 0.0
	for iteration in range(90):
		age += STEP
		var old_x: float = x
		var old_y: float = y
		if age > straight:
			vy -= gravity * STEP
			vh *= 1.0 - drag * STEP
			vy *= 1.0 - drag * STEP
		x += vh * STEP
		y += vy * STEP
		if x >= distance:
			return lerpf(old_y, y, (distance - old_x) / maxf(0.000001, x - old_x))
		if vh < 0.5:
			break
	return -1000.0

func _shot(actor, w: Dictionary, kind: String) -> void:
	var cost: float = float(w.get("inkPerShot", 0.95))
	if not actor.spend_ink(cost):
		actor.weapon_state["cooldown"] = float(w.get("fireInterval", 0.1))
		return
	var s: Dictionary = actor.weapon_state
	var interval: float = float(w.get("fireInterval", 0.1))
	if kind == "dualies" and float(s["lock"]) > 0.0:
		interval = float(w.get("lockInterval", 0.07))
	s["cooldown"] += interval
	var spread:float=spread_degrees(w,kind,actor.is_grounded(),float(s["bloom"]),float(s["lock"])>0.0)
	s["spread"]=spread
	s["bloom"] = minf(1.0, float(s["bloom"]) + float(w.get("bloomPerShot", 0.3)))
	var origin:Vector3
	if kind == "dualies":
		s["hand"] = 1 - int(s["hand"])
		origin=_muzzle_hand(actor,int(s["hand"]))
	else:origin=_muzzle(actor)
	var dir:Vector3=_aim_from(actor,origin)
	if kind != "blaster":
		dir = ballistic_direction(origin, dir, actor.aim_point, float(w.get("projSpeed", 34.0)), float(w.get("straightTime", 0.13)), 28.0, 0.8, float(w.get("range", 12.5)))
	dir=_spread(dir,spread)
	_attack_id += 1
	var blast: bool = kind == "blaster"
	var trail_every: float = 2.2 if blast else float(w.get("trailEvery", 1.05))
	_spawn_bullet({"pos": origin, "velocity": dir.normalized() * float(w.get("projSpeed", 34.0)), "owner": actor, "team": actor.team_id, "kind": kind, "life": float(w.get("range", 10.5)) / float(w.get("projSpeed", 23.0)) if blast else 1.2, "range": INF, "damage": float(w.get("directDamage", w.get("damage", 36.0))), "radius": float(w.get("impactRadius", 0.85)), "straight": 99.0 if blast else float(w.get("straightTime", 0.13)), "trail_radius": 0.45 if blast else float(w.get("trailRadius", 0.44)), "trail_every": trail_every, "trail": -1.5 if blast else -(2.5 - trail_every), "attack": _attack_id, "gravity": 0.0 if blast else 28.0, "drag": 0.0 if blast else 0.8, "weapon": w})
	actor.trigger("shoot", {"hand": s["hand"]})
	_event("weapon:shot", {"actor": actor, "weapon": actor.weapon_id, "kind": kind, "pos": origin, "dir": dir, "hand": s["hand"]})
	if kind == "blaster" and actor.is_local:
		_event("recoil",{"actor":actor,"amount":.012})
	_event("shoot_blaster" if kind == "blaster" else ("shoot_dualies" if kind == "dualies" else ("shoot_splatling" if kind == "splatling" else "shoot_shooter")), {"actor": actor, "pos": origin,"hand":s["hand"]})

func _flick(actor, w: Dictionary) -> void:
	_attack_id += 1
	var count: int = int(w.get("flickDrops", 9))
	for i in range(count):
		var t: float = float(i) / float(maxi(1, count - 1)) * 2.0 - 1.0
		var facing: float = atan2(_replay_direction.x, _replay_direction.z) if _replaying else actor.rotation.y
		var angle: float = facing + t * deg_to_rad(float(w.get("flickSpreadDeg", 34.0))) * 0.5 + randf_range(-0.025, 0.025)
		var up: float = asin(clampf(_replay_direction.y, -1.0, 1.0)) if _replaying else clampf(actor.aim_pitch, -0.2, 0.5) + 0.32
		var speed: float = float(w.get("flickSpeed", 17.0)) * (0.82 + 0.28 * (1.0 - absf(t)) + randf() * 0.08)
		var cu: float = cos(up + randf_range(-0.06, 0.06))
		var forward := Vector3(sin(facing), 0, cos(facing))
		var origin: Vector3 = _replay_muzzle if _replaying else actor.global_position + forward * 0.6 + Vector3.UP * 1.3
		_spawn_bullet({"pos": origin, "velocity": Vector3(sin(angle) * cu * speed, sin(up) * speed, cos(angle) * cu * speed), "owner": actor, "team": actor.team_id, "kind": "flick", "life": 1.4, "range": INF, "damage": float(w.get("flickDamageNear", 125.0)), "damage_far": float(w.get("flickDamageFar", 30.0)), "radius": randf_range(0.85, 1.15), "straight": 0.0, "trail_radius": 0.45, "trail_every": 1.8, "attack": _attack_id, "gravity": 26.0, "drag": 0.4, "weapon": w})
	_event("roller_flick", {"actor": actor, "pos": actor.global_position})
	var flick_dir: Vector3 = Vector3(sin(actor.rotation.y), sin(clampf(actor.aim_pitch,-.2,.5)+.32), cos(actor.rotation.y)).normalized()
	_event("weapon:flick", {"actor": actor, "weapon": actor.weapon_id, "pos": actor.global_position + Vector3(sin(actor.rotation.y)*.6,1.3,cos(actor.rotation.y)*.6), "dir": flick_dir})
	if actor.is_local:
		_event("recoil",{"actor":actor,"amount":.007})

func _slosher_actor(actor, w: Dictionary) -> void:
	_slosh(actor, w)

func _slosh(actor, w: Dictionary) -> void:
	_attack_id += 1
	var count: int = int(w.get("drops", 8))
	var origin: Vector3 = _muzzle(actor)
	var delta: Vector3 = actor.aim_point - origin
	var distance: float = Vector2(delta.x, delta.z).length()
	var yaw: float = atan2(delta.x, delta.z) if distance > 0.3 else actor.aim_yaw
	distance = clampf(distance, 1.2, float(w.get("range", 9.5)))
	var height: float = clampf(delta.y, -4.0, 5.0)
	var gravity: float = float(w.get("grav", 22.0))
	var speed: float = float(w.get("projSpeed", 15.0))
	var pitch: float = 0.32
	var denominator: float = 2.0 * cos(pitch) * cos(pitch) * (distance * tan(pitch) - height)
	var target_speed: float = sqrt(gravity * distance * distance / denominator) if denominator > 0.001 else INF
	if target_speed <= speed:
		speed = maxf(5.5, target_speed)
	else:
		var discriminant: float = pow(speed, 4.0) - gravity * (gravity * distance * distance + 2.0 * height * speed * speed)
		pitch = clampf(atan((speed * speed - sqrt(discriminant)) / (gravity * distance)) if discriminant >= 0.0 else PI / 4.0, 0.32, 1.2)
	for i in range(count):
		var k: float = float(i) / float(maxi(1, count - 1))
		var sp: float = speed * (1.0 - 0.18 * k)
		var pt: float = pitch - 0.04 * k
		var yw: float = yaw + (0.0 if i == 0 else (1.0 if i % 2 else -1.0) * 0.028 * minf(1.0, float(i) / 3.0))
		_spawn_bullet({"pos": origin, "velocity": Vector3(sin(yw) * cos(pt) * sp, sin(pt) * sp + gravity / 120.0, cos(yw) * cos(pt) * sp), "owner": actor, "team": actor.team_id, "kind": "slosher", "life": 2.4, "delay": float(i) * 0.012, "range": INF, "damage": float(w.get("damageHead", 70.0)) if i == 0 else float(w.get("damageTail", 34.0)), "head": i == 0, "radius": float(w.get("impactRadius", 1.05)) * (1.0 if i == 0 else 0.78 - 0.22 * k), "straight": 0.0, "trail": -0.8, "trail_radius": float(w.get("trailRadius", 0.5)), "trail_every": float(w.get("trailEvery", 1.4)) if i < 3 else 0.0, "attack": _attack_id, "gravity": gravity, "drag": 0.0, "weapon": w})
	_event("weapon:shot", {"actor": actor, "weapon": actor.weapon_id, "kind": "slosher", "pos": origin, "dir": Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))})

func _roll(actor, w: Dictionary, dt: float) -> void:
	var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	if actor.ink <= 0.5:
		return
	actor.rolling = true
	actor._last_fire = 0.0
	var s: Dictionary = actor.weapon_state
	s["roll_time"]=float(s.get("roll_time",0))+dt
	s["roll_distance"] += speed * dt
	var forward := Vector3(sin(actor.rotation.y), 0, cos(actor.rotation.y))
	if float(s["roll_distance"]) >= 0.28:
		actor.ink = maxf(0.0, actor.ink - float(s["roll_distance"]) * float(w.get("rollInkPerMeter", 1.1)))
		s["roll_distance"] = 0.0
		var perpendicular := Vector3(forward.z, 0, -forward.x)
		for stripe in range(-1, 2):
			var p: Vector3 = actor.global_position + forward * 0.75 + perpendicular * float(stripe) * float(w.get("rollWidth", 1.9)) * 0.33 + Vector3.UP * 0.35
			_paint(actor, p, Vector3.UP, 0.62, {"kind": "roll", "stretch": forward})
	for target in _actors():
		if target == actor or not target.alive or target.team_id == actor.team_id:
			continue
		var delta: Vector3 = target.global_position - actor.global_position
		var fwd: float = delta.dot(forward)
		var lateral: float = absf(delta.x * forward.z - delta.z * forward.x)
		var key: String = "roll:%s:%s" % [actor.get_instance_id(), target.get_instance_id()]
		if fwd > -0.2 and fwd < 1.35 and lateral < float(w.get("rollWidth", 1.9)) * 0.5 + 0.35 and absf(delta.y) < 1.2 and speed > 1.0 and clock - float(_hit_records.get(key, -9.0)) > 0.5:
			_hit_records[key] = clock
			apply_hit(actor,target,float(w.get("rollDamage",140.0)),"roller")
	var boss = match_node.get("boss")
	if is_instance_valid(boss) and boss.has_method("roll_hit"):
		var boss_hit:Dictionary=boss.call("roll_hit",actor.global_position,forward,float(w.get("rollWidth",1.9)))
		var key:String="roll:%s:boss" % actor.get_instance_id()
		if not boss_hit.is_empty():
			if int(boss_hit.get("crab",-1))>=0:key+="_%s" % boss._crablets[int(boss_hit.crab)].id
			if clock-float(_hit_records.get(key,-9.0))>.5:
				_hit_records[key]=clock
				boss.call("hit_segment",actor,boss_hit,float(w.get("rollDamage",140.0)),"roller")

func _charger(actor, w: Dictionary) -> void:
	var fraction: float = maxf(0.12, actor.charge)
	actor.ink = maxf(0.0, actor.ink - float(w.get("inkFull", 18.0)) * fraction)
	actor._last_fire = 0.0
	var origin: Vector3 = _muzzle(actor)
	var reach: float = lerpf(float(w.get("rangeMin", 11.0)), float(w.get("rangeMax", 27.0)), fraction)
	var direction:Vector3=_aim_from(actor,origin)
	var finish: Vector3 = origin + direction * reach
	var hit: Dictionary = _world_cast(actor,origin,finish,true)
	if not hit.is_empty():
		finish = hit["position"]
	var dmg: float = float(w.get("damageMax", 160.0)) if fraction >= 0.999 else lerpf(float(w.get("damageMin", 40.0)), float(w.get("damageMax", 160.0)) * 0.62, fraction)
	var nearest = null
	var nearest_distance: float = INF
	for target in _actors():
		if target != actor and target.alive and target.team_id != actor.team_id:
			var distance: float = _segment_actor(origin, finish, target, .38+.14, .38+.12)
			if distance < nearest_distance:
				nearest = target
				nearest_distance = distance
	var boss = match_node.get("boss")
	var boss_hit: bool = false
	if is_instance_valid(boss) and boss.has_method("segment_hit"):
		var shape_hit:Dictionary=boss.call("segment_hit",origin,finish,.1)
		if not shape_hit.is_empty() and float(shape_hit.distance)<nearest_distance:
			boss_hit=true
			nearest=null
			finish=shape_hit.point
			boss.call("hit_segment",actor,shape_hit,dmg,"charger")
	if nearest:
		finish=origin+direction*nearest_distance
	if nearest and not boss_hit:
		apply_hit(actor,nearest,dmg,"charger")
	var s: float = 1.2
	while s < origin.distance_to(finish) - 0.3:
		var point: Vector3 = origin + direction * s
		var floor_hit: Dictionary = _world_cast(actor,point,point-Vector3.UP*3.5,true)
		if not floor_hit.is_empty():
			_paint(actor, floor_hit["position"] + floor_hit["normal"] * 0.1, floor_hit["normal"], float(w.get("lineRadius", 0.55)) * (0.8 + fraction * 0.4), {"stretch": direction, "stretchAmt": 1.2})
		s += float(w.get("lineSplatEvery", 1.2))
	if not hit.is_empty() and not nearest and not boss_hit:
		_paint(actor, finish + hit["normal"] * 0.12, hit["normal"], float(w.get("impactRadius", 1.2)) * (0.6 + fraction * 0.4), {"stretch": direction, "stretchAmt": 0.6})
	actor.trigger("charge_release")
	_event("shoot_charger", {"actor": actor, "pos": origin,"charge":fraction})
	_event("weapon:beam", {"actor": actor, "from": origin, "to": finish, "charge": fraction})
	if actor.is_local:
		_event("recoil",{"actor":actor,"amount":.005+fraction*.013})

func _spawn_bomb(actor) -> void:
	_attack_id += 1
	_spawn_bullet({"pos": actor.global_position + Vector3.UP * 1.35, "velocity": _throw_velocity(actor, 13.5), "owner": actor, "team": actor.team_id, "kind": "bomb", "life": 8.0, "range": INF, "damage": 0.0, "radius": 0.0, "straight": 0.0, "trail_radius": 0.0, "trail_every": 0.0, "attack": _attack_id, "gravity": 24.0, "fuse": -1.0, "beep": 0.0, "weapon": {}})
	actor.trigger("throw")
	_event("bomb_throw", {"actor": actor, "pos": actor.global_position})
	_event("bomb:throw",{"actor":actor,"pos":actor.global_position+Vector3.UP*1.35,"velocity":_throw_velocity(actor,13.5),"kind":"bomb","fuse":-1.0,"team":actor.team_id,"radius":3.1})

func _throw_velocity(actor, speed: float) -> Vector3:
	var pitch: float = clampf(actor.aim_pitch + 0.28, -0.3, 1.1)
	return Vector3(sin(actor.aim_yaw) * cos(pitch) * speed + actor.velocity.x * 0.4, sin(pitch) * speed + 1.5, cos(actor.aim_yaw) * cos(pitch) * speed + actor.velocity.z * 0.4)

func throw_storm(actor) -> void:
	_attack_id += 1
	var vel: Vector3 = _throw_velocity(actor, 16.0)
	_spawn_bullet({"pos": actor.global_position + Vector3.UP * 1.45, "velocity": vel, "owner": actor, "team": actor.team_id, "kind": "storm_pod", "life": 1.1, "range": INF, "damage": 0.0, "radius": 0.0, "straight": 0.0, "trail_radius": 0.0, "trail_every": 0.0, "attack": _attack_id, "gravity": 24.0, "fuse": -1.0, "weapon": {}})

func _spawn_bullet(data: Dictionary) -> void:
	if _replaying:data["ghost"]=true
	if bullets.size() >= CAPACITY:
		return
	var mesh: MeshInstance3D
	for candidate in _mesh_pool:
		if not candidate.visible:
			mesh = candidate
			break
	if not mesh:
		return
	mesh.visible = true
	mesh.layers=1
	mesh.rotation=Vector3.ZERO
	mesh.mesh=_bomb_geometry if str(data.kind) in ["bomb","storm_pod"] else _sphere
	mesh.material_override = _materials[int(data["team"]) % 2]
	var cap:MeshInstance3D=mesh.get_meta("bomb_cap") as MeshInstance3D if mesh.has_meta("bomb_cap") else null
	if str(data.kind)=="bomb" and not cap:
		cap=MeshInstance3D.new();cap.mesh=_bomb_cap;cap.material_override=_bomb_cap_material;cap.position.y=.2
		mesh.add_child(cap);mesh.set_meta("bomb_cap",cap)
	if cap:cap.visible=str(data.kind)=="bomb"
	mesh.position = data["pos"]
	mesh.scale = Vector3.ONE * (1.0 if data["kind"] == "bomb" else (1.25 if data["kind"]=="storm_pod" else (1.4 if data["kind"] == "blaster" else 0.75)))
	data["spin"]=Vector3(4,6,0) if data.kind=="storm_pod" else Vector3(randf()*8,randf()*8,0) if data.kind=="bomb" else Vector3.ZERO
	data["mesh"] = mesh
	data["age"] = 0.0
	data["lifetime"] = float(data["life"])
	data["seed"] = randf()
	data["start"] = data["pos"]
	var kind: String = str(data["kind"])
	data["size"] = float(data.get("size",.26 if kind=="blaster" else (.2 if bool(data.get("head",false)) else .14) if kind=="slosher" else .15))
	data["source_weapon"] = "drop" if kind=="flick" else ("blast" if kind=="blaster" else kind)
	data["vis"] = 0.2 if kind == "blaster" else (0.088 if kind == "dualies" else (0.086 if kind == "splatling" else (0.19 if bool(data.get("head", false)) else 0.1)))
	data["tail0"] = 0.5 if kind == "blaster" else (0.7 if kind == "slosher" else (0.4 if kind == "flick" else 0.8))
	data["tail_k"] = 0.9 if kind == "blaster" else (1.5 if kind == "slosher" else (1.6 if kind == "splatling" else 1.3))
	data["wob"] = 0.12 if kind == "slosher" else (0.085 if kind == "blaster" else (0.1 if kind == "flick" else 0.035))
	data["wob_f"] = 15.0 if kind == "slosher" else (17.0 if kind == "blaster" else (19.0 if kind == "flick" else 26.0))
	data["nose"] = 0.0 if kind == "flick" else (0.1 if kind == "slosher" else (0.15 if kind == "blaster" else 0.3))
	data["sats"] = 4 if kind == "blaster" else (2 if kind in ["dualies", "splatling", "flick", "slosher"] else 3)
	data["distance"] = 0.0
	data["trail"] = float(data.get("trail", 0.0))
	bullets.append(data)

func update(dt: float) -> void:
	clock += dt
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		if float(b.get("delay", 0.0)) > 0.0:
			b["delay"] = float(b["delay"]) - dt
			b["mesh"].visible = true
			if float(b["delay"]) > 0.0:continue
		var old: Vector3 = b["pos"]
		b["age"] += dt
		b["life"] = float(b.lifetime)-float(b.age)
		var vel: Vector3 = b["velocity"]
		if float(b["age"]) > float(b["straight"]):
			vel.y -= float(b["gravity"]) * dt
			vel *= 1.0 - float(b.get("drag", 0.0)) * dt
		b["velocity"] = vel
		var next: Vector3 = old + vel * dt
		var owner = b["owner"]
		var world_hit: Dictionary = {}
		var target_hit = null
		var target_dist: float = INF
		if b["kind"] not in ["bomb", "storm_pod"]:
			for target in _actors():
				if target != owner and target.alive and target.team_id != int(b["team"]):
					if absf(target.global_position.x-next.x)>3 or absf(target.global_position.z-next.z)>3:continue
					var dist: float = _segment_actor(old, next, target, .38*.95+float(b.size))
					if is_finite(dist):
						target_dist = dist
						target_hit = target
						break
			var boss = match_node.get("boss")
			var shape_hit:Dictionary={}
			if target_hit==null and not bool(b.get("ghost",false)) and is_instance_valid(boss) and boss.has_method("segment_hit"):
				shape_hit=boss.call("segment_hit",old,next,float(b.size)*.6)
			if not shape_hit.is_empty():
				var boss_damage: float = float(b["damage"])
				var boss_key: String = "%s:boss" % b["attack"]
				if int(shape_hit.get("crab",-1))>=0:boss_key="%s:crab:%s"%[b.attack,boss._crablets[int(shape_hit.crab)].id]
				var flick_key: String = "flick:boss:%s" % (owner.get_instance_id() if is_instance_valid(owner) else 0)
				if b["kind"] == "slosher" and _hit_records.has(boss_key):
					boss_damage = 0.0
				elif b["kind"] == "flick":
					boss_damage = lerpf(boss_damage, float(b["damage_far"]), clampf(Vector3(b.start).distance_to(shape_hit.point) / 7.0, 0.0, 1.0))
					if clock - float(_hit_records.get(flick_key, -9.0)) < 0.3:
						boss_damage *= 0.12
				if boss_damage>0:boss.call("hit_segment",owner,shape_hit,boss_damage,str(b.source_weapon))
				_hit_records[boss_key] = clock
				if b["kind"] == "flick" and boss_damage > 0 and clock - float(_hit_records.get(flick_key, -9.0)) >= 0.3:
					_hit_records[flick_key] = clock
				_impact(b, shape_hit.point, -vel.normalized(), boss)
				_remove_bullet(i)
				continue
		if target_hit != null:
			var contact:Vector3=old+vel.normalized()*target_dist
			var dmg: float = float(b["damage"])
			if b["kind"] == "flick":
				dmg = lerpf(dmg, float(b["damage_far"]), clampf(Vector3(b.start).distance_to(contact) / 7.0, 0.0, 1.0))
			var hit_key: String = "%s:%s" % [b["attack"], target_hit.get_instance_id()]
			if b["kind"] != "slosher" or not _hit_records.has(hit_key):
				_hit_records[hit_key] = clock
				if not bool(b.get("ghost",false)):
					apply_hit(owner,target_hit,dmg,str(b.source_weapon))
			_impact(b, contact, -vel.normalized(), target_hit)
			_remove_bullet(i)
			continue
		world_hit=_world_cast(owner,old,next,b.kind not in ["bomb","storm_pod"])
		if not world_hit.is_empty():
			if b["kind"] == "storm_pod":
				# Original storm capsules open at their integrated endpoint; the
				# contact is detected before a bomb would snap onto the hit surface.
				b.pos=next
				spawn_storm(owner,next,vel,bool(b.get("ghost",false)))
				_remove_bullet(i)
				continue
			next = world_hit["position"]
			if b["kind"] == "bomb":
				var n: Vector3 = world_hit["normal"]
				b["velocity"] = (vel - n * vel.dot(n) * 1.35) * (0.45 if n.y > 0.6 else 0.6)
				next += n * 0.21
				if n.y > 0.6 and float(b["fuse"]) < 0.0:
					b["fuse"] = 0.95
					_event("bomb_beep", {"pos": next,"volume":.6})
					_event("bomb:arm",{"actor":owner,"pos":next,"team":b.team,"radius":3.1})
			else:
				_impact(b, next, world_hit["normal"])
				_remove_bullet(i)
				continue
		if world_hit.is_empty() and str(b.kind)=="bomb":
			var boss=match_node.get("boss")
			if is_instance_valid(boss) and boss.has_method("segment_hit"):
				var boss_shape:Dictionary=boss.call("segment_hit",old,next,.2)
				if not boss_shape.is_empty() and int(boss_shape.get("crab",-1))<0:
					var normal:Vector3=(next-Vector3(boss_shape.center)).normalized()
					next=Vector3(boss_shape.center)+normal*(float(boss_shape.radius)+.22)
					var inward:float=vel.dot(normal)
					if inward<0.0:b.velocity=(vel-normal*inward*1.35)*.55
		var traveled: float = old.distance_to(next)
		b["distance"] += traveled
		if not bool(b.get("ghost",false)) and float(b["trail_every"]) > 0.0:
			b["trail"] += vel.length() * dt
		if not bool(b.get("ghost",false)) and float(b["trail_every"]) > 0.0 and float(b["trail"]) > float(b["trail_every"]) and float(b["trail_radius"]) > 0.0:
			b["trail"] = 0.0
			var floor_hit: Dictionary = _world_cast(owner,next,next-Vector3.UP*4.0,true)
			if not floor_hit.is_empty():
				_paint(owner, floor_hit["position"] + floor_hit["normal"] * 0.1, floor_hit["normal"], float(b["trail_radius"]) * randf_range(0.8, 1.2), {"kind": "trail"})
		b["pos"] = next
		b["mesh"].position = next
		if vel.length_squared() > 0.01 and b["kind"] not in ["bomb","storm_pod"]:
			var visual_direction:Vector3=vel.normalized()
			b["mesh"].look_at(next + visual_direction,Vector3.RIGHT if absf(visual_direction.y)>.99 else Vector3.UP)
			b["mesh"].scale = Vector3(0.65, 0.65, 1.2)
		if b["kind"] == "bomb" and float(b["fuse"]) >= 0.0:
			b["fuse"] -= dt
			var fuse_k:float=1.0-float(b.fuse)/.95
			b["mesh"].scale=Vector3.ONE*(1.0+fuse_k*.35+sin(float(b.age)*40.0)*.03*fuse_k)
			b.beep=float(b.get("beep",0.0))-dt
			if float(b.beep)<=0:
				b.beep=.3-fuse_k*.2
				_event("bomb_beep",{"pos":next,"volume":.35+fuse_k*.4,"pitch":1.0+fuse_k*.25})
			if float(b["fuse"]) <= 0.0:
				explode(next,owner,3.1,180.0,35.0,2.7,"bomb",null,-1.0,bool(b.get("ghost",false)))
				_remove_bullet(i)
				continue
		var expired:bool=b.kind!="bomb" and float(b.age)>float(b.lifetime)
		if expired or float(b["distance"]) >= float(b["range"]):
			if b["kind"] == "blaster":
				_impact(b,next,Vector3.UP,null,false)
			elif b["kind"] == "storm_pod":
				spawn_storm(owner,next,vel,bool(b.get("ghost",false)))
			_remove_bullet(i)
			continue
		elif next.y < Rules.player("waterY", -1.6) - 1.8:
			_remove_bullet(i)
			continue
		if b.kind in ["bomb","storm_pod"] and is_instance_valid(b.get("mesh")):
			var spin_scale:float=.2 if float(b.get("fuse",-1))>=0 else 1.0
			b.mesh.rotation.x+=Vector3(b.spin).x*dt*spin_scale
			b.mesh.rotation.z+=Vector3(b.spin).y*dt*spin_scale
	_tick_storms(dt)
	if int(clock * 60.0) % 120 == 0:
		for key in _hit_records.keys():
			if clock - float(_hit_records[key]) > 3.0:
				_hit_records.erase(key)

func _impact(b: Dictionary, pos: Vector3, normal: Vector3, direct = null, world_impact: bool = true) -> void:
	var owner = b["owner"]
	var ghost: bool = bool(b.get("ghost",false))
	if b["kind"] == "blaster":
		var w: Dictionary = b["weapon"]
		if direct==null and world_impact and not ghost:
			_paint(owner,pos+normal*.14,normal,float(b["radius"])*randf_range(.85,1.15),{"stretch":Vector3(b["velocity"]).normalized(),"stretchAmt":.7})
		if direct==null and world_impact:
			_event("impact:shot",{"actor":owner,"pos":pos,"normal":normal,"team":b["team"],"kind":"blaster","radius":b["radius"]})
			_event("splat_big",{"actor":owner,"pos":pos,"volume":.6})
		explode(pos,owner,float(w.get("splashRadius",2.6)),float(w.get("splashDamageMax",70.0)),float(w.get("splashDamageMin",30.0)),float(w.get("impactRadius",1.5)),"blaster",direct,float(w.get("burstRadius",1.9)),ghost)
	else:
		var direction: Vector3 = Vector3(b["velocity"]).normalized()
		if direct == null and not ghost and b["kind"] == "slosher":
			direction.y = 0.0
			direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3(0, 0, 1)
			_paint(owner, pos + normal * 0.14, normal, float(b["radius"]) * randf_range(0.85, 1.15) * 1.12, {"stretch": direction, "stretchAmt": 1.25})
		elif direct == null and not ghost:
			_paint(owner, pos + normal * 0.14, normal, float(b["radius"]) * randf_range(0.85, 1.15), {"stretch": direction, "stretchAmt": 0.7})
		if b["kind"] == "slosher" and bool(b.get("head", false)) and not ghost:
			_slosh_splash(b, pos, direct)
		_event("impact:shot", {"actor": owner, "pos": pos, "normal": normal, "radius": b["radius"], "team": b["team"], "head": b.get("head", false), "kind": b["kind"], "dir": Vector3(b["velocity"]).normalized(), "victim": direct})
		if direct==null:
			var streamed: bool = str(b["kind"]) in ["shooter","dualies","splatling"]
			if not streamed or randf()<.45:
				_event("splat_small",{"pos":pos,"actor":owner,"volume":.35 if streamed else .6})

func _slosh_splash(b: Dictionary, point: Vector3, direct) -> void:
	var w: Dictionary = b["weapon"]
	var radius: float = float(w.get("splashRadius", 1.1)) + 0.3
	for target in _actors():
		if target == direct or not target.alive or target.team_id == int(b["team"]):
			continue
		var center: Vector3 = target.global_position + Vector3.UP * 0.6
		var key: String = "%s:%s" % [b["attack"], target.get_instance_id()]
		if center.distance_to(point) > radius or _hit_records.has(key):
			continue
		if not _world_los(b.owner,point+Vector3.UP*.25,center):
			continue
		_hit_records[key] = clock
		apply_hit(b["owner"],target,float(w.get("splashDamage",26.0)),"slosher")
	var boss = match_node.get("boss")
	var boss_key: String = "%s:boss" % b["attack"]
	if is_instance_valid(boss) and boss != direct and boss.has_method("splash") and not _hit_records.has(boss_key):
		_hit_records[boss_key] = clock
		boss.call("splash", b["owner"], point, radius, float(w.get("splashDamage", 26.0)), "slosher")
	_event("slosh_land", {"pos": point, "actor": b["owner"]})

func explode(pos: Vector3, owner, radius: float, damage_max: float, damage_min: float, paint_radius: float, kind: String, skip = null, fx_radius: float = -1.0, visual_only: bool = false) -> void:
	if not is_instance_valid(owner):
		return
	if visual_only:
		_event("explosion",{"actor":owner,"pos":pos,"radius":radius if fx_radius<0 else fx_radius,"team":owner.team_id,"kind":kind,"ghost":true})
		_event("bomb_explode" if kind=="bomb" else "blaster_boom",{"pos":pos,"actor":owner,"volume":.7 if kind=="blaster" else 1.0})
		return
	if kind in ["bomb", "slam"]:
		_paint(owner,pos+Vector3.UP*(.3 if kind=="slam" else .2),Vector3.UP,paint_radius*(.72 if kind=="slam" else 1.0),{},kind!="slam")
		var count: int = 9 if kind == "slam" else 5
		for i in range(count):
			var angle: float = float(i) / float(count) * TAU + randf() * 0.3 if kind == "slam" else randf() * TAU
			var spread: float = paint_radius * randf_range(0.55, 0.85) if kind == "slam" else paint_radius * randf_range(0.6, 1.0)
			var blob: float = randf_range(1.1, 1.7) if kind == "slam" else randf_range(0.7, 1.2)
			_paint(owner,pos+Vector3(cos(angle)*spread,.6 if kind=="slam" else .5,sin(angle)*spread),Vector3.UP,blob,{},kind!="slam")
	else:
		var floor_hit: Dictionary = _world_cast(owner,pos+Vector3.UP*.2,pos-Vector3.UP*3.3,false)
		if not floor_hit.is_empty():
			_paint(owner, floor_hit["position"] + floor_hit["normal"] * 0.1, floor_hit["normal"], paint_radius)
	for target in _actors():
		if target == skip or not target.alive or target.team_id == owner.team_id:
			continue
		var center: Vector3 = target.global_position + Vector3.UP * (0.8 if kind == "slam" else 0.7)
		var distance: float = (target.global_position if kind == "slam" else center).distance_to(pos)
		if distance > radius:
			continue
		var los_origin:Vector3=pos+Vector3.UP*(.8 if kind=="slam" else .3 if kind=="bomb" else 0.0)
		if not _world_los(owner,los_origin,center):
			continue
		var amount: float = radial_damage(kind, distance, radius, damage_max, damage_min)
		apply_hit(owner,target,amount,kind)
	var boss = match_node.get("boss")
	if is_instance_valid(boss) and boss != skip and boss.has_method("splash"):
		boss.call("splash", owner, pos, radius, damage_max, kind,damage_min)
	_event("explosion",{"actor":owner,"pos":pos,"radius":radius if fx_radius<0.0 else fx_radius,"damage_radius":radius,"team":owner.team_id,"kind":kind})
	if kind in ["bomb","slam"]:
		_event("shake",{"pos":pos,"amount":1.0 if kind == "slam" else .6})
	_event("bomb_explode" if kind == "bomb" else ("special_slam" if kind == "slam" else "blaster_boom"), {"pos": pos, "actor": owner})

func radial_damage(kind: String, distance: float, radius: float, maximum: float, minimum: float) -> float:
	if kind == "bomb":
		var k: float = 1.0 - clampf((distance - 0.8) / maxf(0.001, radius - 0.8), 0.0, 1.0)
		return lerpf(minimum, maximum, k * k)
	if kind == "slam":
		return maximum if distance < 3.2 else minimum + (maximum - minimum) * 0.3 * (1.0 - (distance - 3.2) / maxf(0.001, radius - 3.2))
	return lerpf(maximum, minimum, clampf(distance / radius, 0.0, 1.0))

func replay_ghost_fire(data: Dictionary) -> void:
	var actor = data.get("actor")
	if not is_instance_valid(actor):return
	var id: String = str(data.get("weapon",actor.get("weapon_id")))
	var w: Dictionary = Rules.weapon(id)
	var kind: String = str(w.get("kind",id))
	var origin: Vector3 = data.get("muzzle",data.get("pos",data.get("from",actor.global_position+Vector3.UP*1.05)))
	var direction: Vector3 = data.get("dir",actor.get("aim_dir"))
	if direction.length_squared()<.000001:direction=Vector3.BACK
	direction=direction.normalized()
	var audio: Node = match_node.get("audio") as Node
	var sound_data: Dictionary = {"actor":actor,"pos":origin,"hand":data.get("hand",0),"charge":data.get("charge",.5)}
	if kind=="charger":
		if not data.has("to"):
			var fx: Node = match_node.get("fx") as Node
			if is_instance_valid(fx):
				fx.call("_beam_fire",origin,origin+direction*float(data.get("len",20.0)),fx.call("_color",actor),float(data.get("charge",.5)))
		if audio:audio.call("on_event","shoot_charger",sound_data)
		return
	if kind in ["roller","slosher"]:
		_replaying=true
		_replay_muzzle=origin
		_replay_direction=direction
		var previous: Vector3 = actor.aim_point
		actor.aim_point=origin+direction*float(w.get("range",9.5))
		if kind=="roller":_flick(actor,w)
		else:_slosh(actor,w)
		actor.aim_point=previous
		_replaying=false
	else:
		_attack_id+=1
		var blast: bool = kind=="blaster"
		_spawn_bullet({"ghost":true,"pos":origin,"velocity":direction*float(w.get("projSpeed",34.0)),"owner":actor,"team":actor.team_id,"kind":kind,"life":float(w.get("range",10.5))/float(w.get("projSpeed",23.0)) if blast else 1.2,"range":INF,"damage":0.0,"radius":float(w.get("impactRadius",.85)),"straight":99.0 if blast else float(w.get("straightTime",.13)),"trail_radius":0.0,"trail_every":0.0,"attack":_attack_id,"gravity":0.0 if blast else 28.0,"drag":0.0 if blast else .8,"weapon":w})
	if audio:
		audio.call("on_event","roller_flick" if kind=="roller" else ("slosh_throw" if kind=="slosher" else "shoot_"+kind),sound_data)

func replay_ghost_bomb(data:Dictionary) -> void:
	var actor=data.get("actor")
	if not is_instance_valid(actor):return
	_attack_id+=1
	var position_world:Vector3=data.get("pos",actor.global_position+Vector3.UP*1.35)
	var velocity_world:Vector3=data.get("velocity",_throw_velocity(actor,13.5))
	_spawn_bullet({"ghost":true,"pos":position_world,"velocity":velocity_world,"owner":actor,"team":actor.team_id,"kind":"bomb","life":8.0,"range":INF,"damage":0.0,"radius":0.0,"straight":0.0,"trail_radius":0.0,"trail_every":0.0,"attack":_attack_id,"gravity":24.0,"fuse":float(data.get("fuse",-1.0)),"beep":0.0,"weapon":{}})
	var audio:Node=match_node.get("audio") as Node
	if audio:audio.call("on_event","bomb_throw",{"actor":actor,"pos":position_world})

func replay_ghost_special(data:Dictionary) -> void:
	if str(data.get("special",data.get("id","")))!="storm":return
	var actor=data.get("actor")
	if not is_instance_valid(actor):return
	_attack_id+=1
	var position_world:Vector3=data.get("muzzle",data.get("pos",actor.global_position)+Vector3.UP*1.45)
	var velocity_world:Vector3=data.get("throw_velocity",_throw_velocity(actor,16.0))
	_spawn_bullet({"ghost":true,"pos":position_world,"velocity":velocity_world,"owner":actor,"team":actor.team_id,"kind":"storm_pod","life":1.1,"range":INF,"damage":0.0,"radius":0.0,"straight":0.0,"trail_radius":0.0,"trail_every":0.0,"attack":_attack_id,"gravity":24.0,"fuse":-1.0,"weapon":{}})

func apply_hit(attacker, victim, amount: float, weapon: String) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(victim) or not victim.alive or victim.team_id == attacker.team_id or amount <= 0.0:
		return false
	var killed: bool = victim.damage(amount,attacker,weapon)
	# Confirmation occurs even when native damage routes to another peer.
	_event("hit",{"attacker":attacker,"victim":victim,"damage":amount,"killed":killed,"weaponId":weapon,"pos":victim.global_position})
	return killed

func spawn_storm(owner, pos: Vector3, direction: Vector3, ghost:bool = false) -> void:
	var cloud := Cloud.new()
	cloud.configure(owner.call("team_color"))
	var ground: Dictionary = _world_cast(owner,pos+Vector3.UP*.5,pos-Vector3.UP*11.5,false)
	cloud.position = Vector3(pos.x, float(ground.get("position", pos).y) + 4.6, pos.z)
	add_child(cloud)
	storms.append({"owner": owner, "team": owner.team_id, "pos": cloud.position, "velocity": Vector3(direction.x, 0.0, direction.z).normalized() * 1.1, "life": 6.5, "age":0.0,"scale":.01,"ghost":ghost,"paint_time":0.0,"node":cloud,"puddle_time":0.0,"flash_time":.5})
	_event("storm_thunder", {"actor": owner, "pos": cloud.position})
	_event("storm:start",{"actor":owner,"team":owner.team_id,"pos":cloud.position,"radius":3.4})

func _tick_storms(dt: float) -> void:
	var network=match_node.get("network")
	var online:bool=is_instance_valid(network) and bool(network.get("active"))
	for i in range(storms.size() - 1, -1, -1):
		var storm: Dictionary = storms[i]
		storm["life"] -= dt
		storm["age"] += dt
		storm["pos"] += storm["velocity"] * dt
		storm["node"].position = storm["pos"]
		var grow:float=clampf(float(storm.age)/.5,0,1)
		var fade:float=clampf(float(storm.life)/.6,0,1)
		storm.scale=(.3+.7*(1.0-pow(1.0-grow,3.0)))*(.2+.8*fade)
		storm["node"].call("update",clock,float(storm.scale))
		var owner = storm["owner"]
		if is_instance_valid(owner):
			_event("storm_rain",{"pos":storm.pos,"actor":owner,"cloud":storm.node.get_instance_id(),"volume":.6*fade})
			if float(storm.life)>.3:
				storm.paint_time-=dt
				while float(storm.paint_time)<=0.0:
					storm.paint_time+=.045
					var theta:float=randf()*TAU
					var p:Vector3=storm.pos+Vector3(cos(theta),0,sin(theta))*sqrt(randf())*3.4-Vector3.UP*.8
					var hit:Dictionary=_world_cast(owner,p,p-Vector3.UP*12.0,false)
					if not hit.is_empty() and not bool(storm.ghost):_paint(owner,hit.position+hit.normal*.1,hit.normal,randf_range(.45,.8))
				var boss=match_node.get("boss")
				if not bool(storm.ghost) and is_instance_valid(boss) and boss.has_method("rain"):
					boss.call("rain",owner,Vector3(storm.pos),3.4*float(storm.scale),34.0*dt)
				for actor in _actors():
					# Original clouds hurt actors on their owning client, including
					# foreign ghost clouds; proxy actors must never route another hit.
					if online and (not network.has_method("owns_actor") or not bool(network.call("owns_actor",actor))):continue
					if actor.alive and actor.team_id!=owner.team_id:
						var delta:Vector3=actor.global_position-Vector3(storm.pos)
						if Vector2(delta.x,delta.z).length()<3.4 and actor.global_position.y<=Vector3(storm.pos).y:
							var visible:bool=_world_los(actor,actor.global_position+Vector3.UP*1.2,Vector3(actor.global_position.x,Vector3(storm.pos).y-.6,actor.global_position.z))
							if visible and actor.damage(34.0*dt,owner,"storm"):
								_event("hit",{"attacker":owner,"victim":actor,"damage":0.0,"killed":true,"weaponId":"storm"})
		if float(storm["life"]) <= 0.0:
			_event("storm:end",{"actor":owner,"pos":storm.pos,"team":storm.team,"cloud":storm.node.get_instance_id()})
			storm["node"].queue_free()
			storms.remove_at(i)

func _segment_actor(start: Vector3, finish: Vector3, actor, threshold: float, axis_radius:float=.38) -> float:
	var height: float = 0.55 if actor.form != "kid" else 1.45
	var base:Vector3=actor.call("visual_position") if actor.has_method("visual_position") else actor.global_position
	var result:Vector2=AimQueries.segment_capsule_distance(start,finish,base,axis_radius,height)
	if result.y < threshold:return result.x*start.distance_to(finish)
	return INF

func _paint(owner, pos: Vector3, normal: Vector3, radius: float, options: Dictionary = {}, fill_special: bool = true) -> void:
	if not is_instance_valid(owner) or radius <= 0.0:
		return
	var area: float = match_node.call("paint_splat", pos, normal, radius, int(owner.team_id), options)
	if owner.has_method("add_turf"):
		owner.call("add_turf", area, fill_special)

func _actors() -> Array:
	var result = match_node.get("actors")
	return result if result is Array else []

func _release_visual(b: Dictionary) -> void:
	if is_instance_valid(b.get("mesh")):
		b["mesh"].visible = false

func _remove_bullet(index: int) -> void:
	_release_visual(bullets[index])
	bullets.remove_at(index)

func _event(kind: String, data: Dictionary = {}) -> void:
	if _replaying:return
	Rules.emit_event(match_node, kind, data)
