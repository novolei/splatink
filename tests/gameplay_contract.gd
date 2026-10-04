extends SceneTree

## Source-value contract, independent of character imports and rendering. Run with --headless --script.
const Actor = preload("res://scripts/game/ink_actor.gd")
const Weapons = preload("res://scripts/game/ink_weapons.gd")
const Rules = preload("res://scripts/game/ink_rules.gd")
const Bots = preload("res://scripts/game/ink_bots.gd")
const Boss = preload("res://scripts/game/ink_boss.gd")

class StageStub:
	extends Node
	var layout:Dictionary={"spawnPads":[[2,3,4],[-2,5,-4]]}

class AimAvatarStub:
	extends Node3D
	var physical:Vector3=Vector3(-.2,.85,.2)
	var aimed:Vector3=Vector3(.25,1.1,.6)
	var left:Vector3=Vector3(-.3,1.05,.5)
	var aim_ready_value:float=0.0
	func get_muzzle()->Vector3:return physical
	func get_aim_muzzle(_pitch:float=0.0)->Vector3:return aimed
	func aim_ready()->float:return aim_ready_value
	func get_muzzle_hand(_hand:int=0)->Vector3:return left

class ShapeBossStub:
	extends Boss
	var fixture_shapes:Array[Dictionary]=[]
	func hit_shapes()->Array[Dictionary]:return fixture_shapes if visible and not dead else []

class Arena:
	extends Node3D
	var actors: Array = []
	var projectiles: Node3D
	var team_colors: Array = [Color("ff8a14"), Color("2f5bff")]
	var boss = null
	var network = null
	var stage = null
	var state:String="playing"
	var audio = null
	var fx = null
	var events: Array = []
	var paint: Array = []
	var cover: bool = false
	func cast(from: Vector3, to: Vector3, _exclude: Array = [], _mask: int = 1) -> Dictionary:
		if cover:
			return {"position": from.lerp(to, 0.5), "normal": Vector3.UP}
		if from.y >= 0.0 and to.y < 0.0:
			return {"position": from.lerp(to, from.y / (from.y - to.y)), "normal": Vector3.UP}
		return {}
	func sample_ink(_pos: Vector3, _normal: Vector3 = Vector3.UP) -> int:
		return -1
	func paint_splat(pos: Vector3, normal: Vector3, radius: float, team: int, options: Dictionary = {}) -> float:
		paint.append({"pos": pos, "normal": normal, "radius": radius, "team": team, "options": options})
		return radius * radius
	func spawn_for(_team: int, _index: int) -> Vector3:
		return Vector3.ZERO
	func notify_event(kind: String, data: Dictionary) -> void:
		events.append({"kind": kind, "data": data})

var arena: Arena
var weapons
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_contract")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func near(actual: float, expected: float, description: String, tolerance: float = 0.001) -> void:
	expect(absf(actual - expected) <= tolerance, "%s: got %.6f, expected %.6f" % [description, actual, expected])

func actor(id: String, team: int = 0, pos: Vector3 = Vector3.ZERO):
	var result = Actor.new()
	arena.add_child(result)
	result.match_node = arena
	result.weapon_id = id
	result.team_id = team
	result.global_position = pos
	result.aim_dir = Vector3(0, 0, 1)
	result.aim_point = pos + Vector3(0, 0.92, 10.0)
	result.reset_weapon()
	arena.actors.append(result)
	return result

func reset_rounds() -> void:
	weapons.clear()
	arena.events.clear()
	arena.paint.clear()
	for unit in arena.actors:
		unit.queue_free()
	arena.actors.clear()
	arena.cover = false

func run_contract() -> void:
	arena = Arena.new()
	root.add_child(arena)
	weapons = Weapons.new()
	arena.add_child(weapons)
	arena.projectiles = weapons
	weapons.configure(arena)
	expect(Rules.section("WEAPONS").size() == 7, "Exact source catalogue has seven weapons")
	near(Rules.player("hp", 0), 100, "Player HP")
	near(Rules.player("swimSpeed", 0), 11.8, "Own ink swim speed")
	near(Rules.player("respawnTime", 0), 5.5, "Respawn delay")
	var unit = actor("shooter")
	weapons.tick_actor(unit, 1.0 / 60.0, {"fire": true})
	expect(weapons.bullets.size() == 1, "Shooter fires on trigger press")
	near(unit.ink, 99.05, "Shooter per-shot ink")
	near(weapons.bullets[0].life, 1.2, "Shooter source lifetime")
	near(weapons.bullets[0].gravity, 28, "Shooter source gravity")
	near(weapons.bullets[0].drag, 0.8, "Shooter source drag")
	var direction: Vector3 = weapons.ballistic_direction(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 10), 34, 0.13, 28, 0.8, 12.5)
	var landing: float = weapons.trajectory_height(asin(direction.y), 10, 34, 0.13, 28, 0.8)
	near(landing, 0, "Muzzle ballistic compensation meets target", 0.025)
	reset_rounds()
	unit = actor("dualies")
	expect(weapons.try_dodge(unit, Vector3.RIGHT), "First dualies roll")
	near(unit.ink, 93, "Dualies roll consumes seven ink")
	weapons.tick_actor(unit, 0.31, {"fire": true})
	expect(weapons.try_dodge(unit, Vector3.RIGHT), "Second dualies roll chains")
	weapons.tick_actor(unit, 0.81, {"fire": true})
	near(float(unit.weapon_state.lock),.5,"Source dualies lock begins after the roll has finished")
	expect(not weapons.try_dodge(unit, Vector3.RIGHT), "Only two dualies rolls before trigger release")
	weapons.tick_actor(unit, 0.01, {"fire": false})
	expect(not weapons.try_dodge(unit, Vector3.RIGHT),"Source trigger release during post-roll lock does not restore rolls")
	weapons.tick_actor(unit, 0.5, {"fire": false})
	expect(weapons.try_dodge(unit, Vector3.RIGHT), "Trigger release after lock restores rolls")
	reset_rounds()
	unit = actor("splatling")
	weapons.tick_actor(unit, 0.85, {"fire": true})
	near(unit.charge, 1, "Splatling fully spins up at 0.85 seconds")
	weapons.tick_actor(unit, 0, {"fire": false})
	near(float(unit.weapon_state.burst), 1.7, "Full splatling burst duration")
	expect(weapons.bullets.is_empty(), "Source splatling release transitions to streaming before the next weapon tick")
	weapons.tick_actor(unit,.01,{"fire":false})
	expect(weapons.bullets.size() == 1, "Source splatling first streaming tick fires first round")
	near(unit.ink, 99.4, "Splatling ink per shot")
	reset_rounds()
	unit = actor("roller")
	weapons.tick_actor(unit, 0.01, {"fire": true, "fire_pressed": true})
	near(unit.ink, 91, "Roller flick consumes nine ink before windup")
	expect(weapons.bullets.is_empty(), "Roller respects 0.22 second flick windup")
	weapons.tick_actor(unit, 0.23, {"fire": true})
	expect(weapons.bullets.size() == 9, "Roller flick sends nine globs")
	reset_rounds()
	unit = actor("slosher")
	weapons.tick_actor(unit, 0.01, {"fire": true})
	near(unit.ink, 92.5, "Slosher ink cost")
	weapons.tick_actor(unit, 0.14, {"fire": true})
	expect(weapons.bullets.size() == 8, "Slosher sends eight staggered globs")
	near(weapons.bullets[0].damage, 70, "Slosher head damage")
	near(weapons.bullets[7].damage, 34, "Slosher tail damage")
	near(weapons.bullets[7].delay, 0.084, "Slosher final glob delay")
	reset_rounds()
	unit = actor("charger")
	weapons.tick_actor(unit, 0.2, {"fire": true})
	near(unit.charge, 0.25, "Charger quick first 20 percent curve")
	weapons.tick_actor(unit, 0.8, {"fire": true})
	near(unit.charge, 1, "Charger full one second charge")
	var first = actor("shooter", 1, Vector3(0, 0, 5))
	var second = actor("shooter", 1, Vector3(0, 0, 7))
	weapons.tick_actor(unit, 0, {"fire": false})
	near(unit.ink, 82, "Full charger ink cost")
	near(float(unit.weapon_state.cooldown), 0.28, "Charger release recovery")
	expect(not first.alive and second.alive, "Charger stops at first enemy as source implementation does")
	reset_rounds()
	unit = actor("blaster")
	weapons.tick_actor(unit, 0.01, {"fire": true})
	near(unit.ink, 91, "Blaster ink cost")
	near(weapons.bullets[0].life, 10.5 / 23.0, "Blaster burst travel time")
	near(weapons.bullets[0].gravity, 0, "Blaster flies straight")
	near(weapons.radial_damage("bomb", 0.8, 3.1, 180, 35), 180, "Bomb inner lethal radius")
	near(weapons.radial_damage("bomb", 1.95, 3.1, 180, 35), 71.25, "Bomb quadratic damage falloff")
	near(weapons.radial_damage("bomb", 3.1, 3.1, 180, 35), 35, "Bomb edge damage")
	near(weapons.radial_damage("slam", 3.19, 5.2, 180, 55), 180, "Slam inner kill radius")
	near(weapons.radial_damage("slam", 5.2, 5.2, 180, 55), 55, "Slam edge damage")
	reset_rounds()
	unit = actor("shooter")
	var protected = actor("shooter", 1, Vector3(0, 0, 1))
	arena.cover = true
	weapons.explode(Vector3.ZERO, unit, 3.1, 180, 35, 2.7, "bomb")
	near(protected.hp, 100, "Solid cover blocks bomb damage")
	arena.cover = false
	protected.invuln = 1.0
	protected.damage(200, unit)
	expect(protected.alive, "Spawn immunity prevents weapon death")
	protected.invuln = 0.0
	protected.special_charge = 100
	protected.damage(200, unit)
	expect(not protected.alive and unit.splats == 1, "Lethal hit credits attacker exactly once")
	near(protected.special_charge, 50, "Splat halves banked special")
	near(protected.respawn_timer, 5.5, "Splat arms source respawn timer")
	reset_rounds()
	unit = actor("shooter")
	unit.ink = 12
	unit.special_charge = 190
	unit.start_special()
	near(unit.ink, 12, "Special activation preserves ink instead of refilling")
	near(unit.velocity.y, 11.5, "Slam source rise launch speed")
	var enemy = actor("shooter", 1)
	unit.damage(40, enemy)
	near(unit.hp, 90, "Slam armor reduces damage to one quarter")
	var boss = Boss.new()
	arena.add_child(boss)
	boss.match_node = arena
	boss.hp = 10000
	boss.max_hp = 10000
	boss.damage(100, unit, "roller", true)
	near(boss.hp, 9925, "Boss roller resistance and weakpoint multiplier")
	near(float(unit.get_meta("boss_damage",0)),75,"Boss damage result counts final resistance-adjusted HP loss")
	expect(int(unit.get_meta("weak_hits",0))==1,"Accepted Boss weakpoint hit increments source statistic")
	boss.stunned = true
	boss.damage(100, unit, "charger", true)
	near(boss.hp, 9612.5, "Boss stunned weakpoint multiplier")
	near(float(unit.get_meta("boss_damage",0)),387.5,"Boss result sums stunned weakpoint damage")
	reset_rounds()
	unit = actor("shooter")
	weapons.tick_actor(unit, .01, {"fire":true})
	var victim = actor("shooter",1,Vector3(0,0,3))
	weapons._impact(weapons.bullets[0],Vector3(0,1,3),Vector3(0,0,-1),victim)
	expect(arena.paint.is_empty(),"Direct player impact has splash VFX without wall/floor turf splat")
	weapons._impact(weapons.bullets[0],Vector3(0,0,3),Vector3.UP)
	expect(arena.paint.size()==1,"World impact leaves actual source splat")
	unit.velocity=Vector3(0,0,11.8)
	unit.submerged=true
	var turn:Vector3=unit.horizontal_velocity(Vector3.RIGHT,11.8,true,false,true,.016)
	near(turn.length(),11.8,"Swimming carves turn while retaining source speed")
	var air:Vector3=unit.horizontal_velocity(Vector3(0,0,1),2.9,true,false,false,.016)
	near(air.length(),11.8,"Squid leap preserves swim momentum in air")
	unit.velocity=Vector3.ZERO
	unit.submerged=false
	var start:Vector3=unit.horizontal_velocity(Vector3(0,0,1),6.0,false,false,true,.016)
	near(start.length(),.56,"Source run initial acceleration easing")
	reset_rounds()
	unit=actor("shooter",1)
	weapons.replay_ghost_fire({"actor":unit,"weapon":"shooter","muzzle":Vector3(0,1,0),"dir":Vector3.BACK})
	expect(weapons.bullets.size()==1 and bool(weapons.bullets[0].get("ghost",false)),"Remote fire creates a marked visual projectile")
	near(unit.ink,100,"Remote replay never spends local proxy ink")
	var ghost_target=actor("shooter",0,Vector3(0,0,3))
	weapons.update(.1)
	near(ghost_target.hp,100,"Remote visual body collision cannot apply replicated damage twice")
	expect(arena.paint.is_empty(),"Remote visual flight and impact never alter turf")
	expect(weapons.bullets.is_empty(),"Remote visual shot retires on body collision")
	reset_rounds()
	unit=actor("slosher",1)
	weapons.replay_ghost_fire({"actor":unit,"weapon":"slosher","muzzle":Vector3(3,1,0),"dir":Vector3.BACK})
	expect(weapons.bullets.size()==8,"Remote bucket replay preserves the eight-glob volley")
	var all_ghost:bool=true
	for bullet in weapons.bullets:all_ghost=all_ghost and bool(bullet.get("ghost",false))
	expect(all_ghost and arena.events.is_empty(),"Replayed bucket volley is visual and does not rebroadcast fire")
	near(unit.ink,100,"Replayed bucket retains proxy ink")
	reset_rounds()
	unit=actor("roller",1)
	var replay_origin:=Vector3(4,2,3)
	weapons.replay_ghost_fire({"actor":unit,"weapon":"roller","muzzle":replay_origin,"dir":Vector3.RIGHT})
	expect(weapons.bullets.size()==9,"Remote roller replay preserves the nine-glob volley")
	expect(Vector3(weapons.bullets[4].pos).is_equal_approx(replay_origin),"Remote flick begins at transmitted muzzle")
	expect(Vector3(weapons.bullets[4].velocity).x>0 and absf(Vector3(weapons.bullets[4].velocity).z)<1,"Remote flick follows transmitted heading")
	reset_rounds()
	unit=actor("blaster",1)
	ghost_target=actor("shooter",0,Vector3(0,0,3))
	weapons.replay_ghost_fire({"actor":unit,"weapon":"blaster","muzzle":Vector3(0,1,0),"dir":Vector3.BACK})
	weapons._impact(weapons.bullets[0],Vector3(0,1,3),Vector3.UP)
	near(ghost_target.hp,100,"Remote burst does not apply splash damage")
	expect(arena.paint.is_empty(),"Remote burst does not add floor paint")
	reset_rounds()
	unit=actor("blaster")
	weapons.tick_actor(unit,.01,{"fire":true})
	weapons._impact(weapons.bullets[0],Vector3(0,1,3),Vector3(0,0,-1))
	expect(arena.paint.size()==2,"Source blaster wall impact paints struck wall and floor under burst")
	near(float(arena.paint[1].radius),1.5,"Source blaster burst floor splat radius")
	var burst_event:Dictionary={}
	for event in arena.events:
		if event.kind=="explosion":burst_event=event.data
	near(float(burst_event.get("radius",0)),1.9,"Blaster visual burst radius differs from damage range")
	near(float(burst_event.get("damage_radius",0)),2.6,"Blaster source splash damage radius")
	arena.paint.clear()
	weapons._impact(weapons.bullets[0],Vector3(0,1,3),Vector3.UP,null,false)
	expect(arena.paint.size()==1,"Air burst paints only nearby floor without a fictitious impact face")
	reset_rounds()
	unit=actor("slosher")
	weapons.tick_actor(unit,.01,{"fire":true})
	expect(arena.events.size()==1 and arena.events[0].kind=="slosh_throw","Bucket throw audio starts during source windup")
	weapons.tick_actor(unit,.14,{"fire":true})
	var slosh_fire:int=0
	for event in arena.events:
		if event.kind=="weapon:shot" and event.data.kind=="slosher":slosh_fire+=1
	expect(slosh_fire==1,"Bucket release emits one replicable source fire event")
	reset_rounds()
	unit=actor("shooter")
	unit.alive=false;unit.respawn_timer=.01
	arena.state="finish"
	unit.tick(.1,{})
	expect(not unit.alive,"Finish never respawns a dead actor after the countdown expires")
	var spawn_stage:=StageStub.new()
	arena.add_child(spawn_stage);arena.stage=spawn_stage
	unit.spawn_index=2;unit.special_charge=75
	arena.state="playing"
	unit.tick(.01,{})
	var respawn_angle:float=PI+.6
	expect(unit.alive and unit.global_position.is_equal_approx(Vector3(2+cos(respawn_angle)*1.1,7.5,4+sin(respawn_angle)*1.1)),"Source respawn uses slot circle1.1 at pad+4.5 rather than initial spawn ring")
	near(unit.velocity.y,-4,"Source respawn drops at four metres per second")
	near(unit.special_charge,0,"Source spawnAt resets special charge")
	near(unit.aim_pitch,0,"Source spawnAt resets aim pitch")
	expect(arena.events.size()==1 and arena.events[0].data.ground_pos.y==3,"Source respawn emits one pad-level flash event")
	arena.stage=null
	boss.hp=1000;boss.stunned=false;boss.invuln=false
	boss.rain(unit,Vector3.ZERO,3.4,10)
	boss.rain(unit,Vector3.ZERO,3.4,20)
	near(boss.hp,1000,"Storm Boss damage is accumulated before flush")
	boss._flush_rain(.01)
	near(boss.hp,970,"Storm Boss damage flushes batched raw damage")
	boss.rain(unit,Vector3.ZERO,3.4,10)
	boss._flush_rain(.1)
	near(boss.hp,970,"Storm Boss damage packets are limited to source.3second cadence")
	boss._flush_rain(.21)
	near(boss.hp,960,"Storm Boss delayed batch eventually lands")
	boss.invuln=true
	boss.damage(100,unit,"shooter",true)
	near(boss.hp,960,"Source phase roar prevents Boss damage")
	reset_rounds()
	unit=actor("shooter",1)
	var bomb_origin:=Vector3(3,1.35,4)
	weapons.replay_ghost_bomb({"actor":unit,"pos":bomb_origin,"velocity":Vector3(0,0,2)})
	expect(weapons.bullets.size()==1 and bool(weapons.bullets[0].ghost) and weapons.bullets[0].kind=="bomb","Remote bomb helper creates a ghost without emitting launch again")
	expect(arena.events.is_empty() and arena.paint.is_empty(),"Remote bomb creation is read-only for gameplay and replication")
	weapons.bullets[0].fuse=0.01
	weapons.update(.02)
	expect(arena.paint.is_empty(),"Remote bomb expiry does not paint")
	weapons.replay_ghost_special({"actor":unit,"special":"storm","muzzle":Vector3(0,8,0),"throw_velocity":Vector3.ZERO})
	weapons.update(1.11)
	expect(weapons.storms.size()==1 and bool(weapons.storms[0].ghost),"Remote tempest creates a ghost cumulus cloud")
	expect(weapons.storms[0].node.puffs.size()==15 and weapons.storms[0].node.groups.size()==2,"Source cumulus has15puffs grouped into2draw submissions")
	near(unit.ink,100,"Remote bombs and tempest preserve proxy ink")
	reset_rounds()
	unit=actor("shooter")
	var aim_avatar:=AimAvatarStub.new()
	unit.add_child(aim_avatar)
	unit.avatar=aim_avatar
	expect(weapons._muzzle(unit).is_equal_approx(aim_avatar.aimed),"Source first round uses full aim grip before the carried gun has raised")
	aim_avatar.aim_ready_value=.5
	expect(weapons._muzzle(unit).is_equal_approx(aim_avatar.physical.lerp(aim_avatar.aimed,.5)),"Source aimReady blends physical and aimed muzzle")
	aim_avatar.aim_ready_value=.98
	expect(weapons._muzzle(unit).is_equal_approx(aim_avatar.physical),"Source aimReady threshold .98 retains physical muzzle")
	aim_avatar.physical=Vector3(9,1,0)
	expect(weapons._muzzle(unit).is_equal_approx(Vector3(0,1.05,.3)),"Source muzzle distance guard prevents firing from an invalid rig pose")
	aim_avatar.physical=Vector3(-.2,.85,.2)
	arena.cover=true
	expect(weapons._muzzle(unit).is_equal_approx(Vector3(0,1.05,.3)),"Source obstructed muzzle falls back to torso launch point")
	arena.cover=false
	aim_avatar.aim_ready_value=0
	expect(weapons._muzzle_hand(unit,0).is_equal_approx(aim_avatar.aimed),"Source dualies right hand retains first-round aiming correction")
	expect(weapons._muzzle_hand(unit,1).is_equal_approx(aim_avatar.left),"Source dualies left hand uses its physical pistol muzzle")
	aim_avatar.left=Vector3(INF,0,0)
	expect(weapons._muzzle_hand(unit,1).is_equal_approx(Vector3(-.25,1.1,.6)),"Source dualies missing left muzzle mirrors right grip across actor centerline")
	unit.aim_point=Vector3(1,1.05,10)
	var corrected:Vector3=weapons._aim_from(unit,Vector3(0,1.05,0))
	expect(corrected.x>0.09 and corrected.z>.99,"Source muzzle parallax aims at reticle world point")
	unit.aim_point=Vector3(0,1.05,1)
	expect(weapons._aim_from(unit,Vector3(0,1.05,0))==unit.aim_dir,"Source very near reticle falls back to aimDir")
	unit.aim_point=Vector3(0,1.05,-10)
	expect(weapons._aim_from(unit,Vector3(0,1.05,0))==unit.aim_dir,"Source reticle behind gun cannot reverse a shot")
	near(weapons.spread_degrees(Rules.weapon("shooter"),"shooter",true,0),2.475,"Source shooter first round applies default .45 accuracy multiplier")
	near(weapons.spread_degrees(Rules.weapon("shooter"),"shooter",true,1),5.5,"Source shooter bloom reaches ground spread")
	near(weapons.spread_degrees(Rules.weapon("dualies"),"dualies",true,0,true),2.2,"Source dualies turret spread is independent of first-round bloom")
	near(weapons.spread_degrees(Rules.weapon("blaster"),"blaster",true,0),1.2,"Source blaster ground cone default is1.2degrees")
	near(weapons.spread_degrees(Rules.weapon("blaster"),"blaster",false,1),4,"Source blaster air cone default is4degrees")
	seed(1428)
	var inside_cone:bool=true
	var horizontal_energy:float=0
	var vertical_energy:float=0
	var cone_tangent:float=tan(deg_to_rad(11))
	for index in 128:
		var sample:Vector3=weapons._spread(Vector3.BACK,11)
		var x:float=sample.x/sample.z
		var y:float=sample.y/sample.z/.55
		inside_cone=inside_cone and x*x+y*y<=cone_tangent*cone_tangent+.000001
		horizontal_energy+=x*x
		vertical_energy+=y*y
	expect(inside_cone,"Source shot spread stays within elliptical circular cone instead of square angle bounds")
	expect(vertical_energy/horizontal_energy>.6 and vertical_energy/horizontal_energy<1.5,"Source shot disk distributes both scaled axes uniformly")
	reset_rounds()
	unit=actor("shooter",0,Vector3(10,0,.5))
	var crab_model:=Node3D.new()
	arena.add_child(crab_model)
	crab_model.position=Vector3(10,0,0)
	boss._crablets.append({"id":12,"node":crab_model,"hp":30.0,"life":12.0,"dead":false})
	boss.damage_crablet(0,31,unit,"shooter")
	near(unit.hp,100,"Destroyed source crablet cannot damage nearby squadmate")
	expect(unit.splats==1,"Source crablet weapon kill credits one splat")
	expect(arena.paint.size()==1 and arena.paint[0].team==0,"Destroyed source crablet paints squad ink")
	near(arena.paint[0].radius,1.3,"Destroyed source crablet paint radius")
	expect(bool(boss._crablets[0].dead),"Crablet death state prevents repeated hits before pooled visual disposal")
	boss.damage_crablet(0,31,unit,"shooter")
	expect(unit.splats==1,"Repeated hit on popped crablet cannot double credit")
	boss._tick_crablets(.01)
	expect(boss._crablets.is_empty(),"Dead crablet is removed from native collision list")
	arena.paint.clear()
	crab_model=Node3D.new()
	arena.add_child(crab_model)
	crab_model.position=Vector3(10,0,0)
	boss._crablets.append({"id":13,"node":crab_model,"hp":30.0,"life":.01,"dead":false})
	boss._tick_crablets(.02)
	near(unit.hp,60,"Expired source crablet bursts for40damage within2.1metres")
	expect(arena.paint.size()==1 and arena.paint[0].team==1,"Expired source crablet paints enemy ink")
	near(arena.paint[0].radius,1.7,"Expired source crablet paint radius")
	var pads:=StageStub.new()
	arena.add_child(pads)
	arena.stage=pads
	unit.global_position=Vector3(2+4.7,100,4)
	expect(boss._safe_spawn(unit),"Source Boss pad immunity uses pad center and ignores airborne height")
	unit.global_position.x=2+4.9
	expect(not boss._safe_spawn(unit),"Source Boss safe pad uses barrier radius plus.6margin")
	reset_rounds()
	unit=actor("shooter",0,Vector3(3,2,7))
	unit.smooth_y=-.4
	unit.smooth_y_velocity=0
	unit.smooth_visual(1.0/60.0)
	near(unit.smooth_y,-.336,"Source visual spring absorbs a step with omega24 semiimplicit integration")
	near(unit.smooth_y_velocity,3.84,"Source visual spring retains vertical correction velocity")
	expect(unit.visual_position().is_equal_approx(Vector3(3,1.664,7)),"Camera and hit queries share source smoothed actor position")
	for index in 120:unit.smooth_visual(1.0/60.0)
	near(unit.smooth_y,0,"Visual curb offset settles completely",.0001)
	unit.smooth_y=-5;unit.smooth_y_velocity=0;unit.smooth_visual(.001)
	near(unit.smooth_y,-.7,"Source visual correction is bounded at .7metres")
	unit.spawn_at(Vector3(0,0,0),0)
	near(unit.smooth_y,0,"Source respawn resets curb spring offset")
	near(unit.smooth_y_velocity,0,"Source respawn resets curb spring momentum")
	var shape_boss:=ShapeBossStub.new()
	arena.add_child(shape_boss)
	shape_boss.match_node=arena;shape_boss.hp=10000;shape_boss.max_hp=10000
	shape_boss.fixture_shapes=[{"center":Vector3(0,1,6),"radius":1.8,"weak":false,"active":true,"socket":"shellF"},{"center":Vector3(0,1,7),"radius":.4,"weak":true,"active":true,"socket":"eyeL"}]
	var geometry_hit:Dictionary=shape_boss.segment_hit(Vector3(0,1,0),Vector3(0,1,10))
	expect(geometry_hit.socket=="shellF" and not geometry_hit.weak,"Rear weakpoint cannot win through the closer armoured shell")
	near(geometry_hit.distance,4.2,"Source sphere query returns surface entry distance")
	shape_boss.fixture_shapes[1].center=Vector3(0,1,4.65)
	geometry_hit=shape_boss.segment_hit(Vector3(0,1,0),Vector3(0,1,10))
	expect(geometry_hit.weak,"Weakpoint within source .02 segment bias wins over neighbouring shell")
	shape_boss.fixture_shapes[1].center=Vector3(0,1,5.1)
	expect(not shape_boss.segment_hit(Vector3(0,1,0),Vector3(0,1,10)).weak,"Weakpoint bias does not select a substantially occluded eye")
	near(shape_boss.ray_distance(Vector3(0,1,0),Vector3.BACK,10),4.2,"Reticle ray uses exact sphere entry")
	near(shape_boss.ray_distance(Vector3(0,8,0),Vector3.BACK,10),-1,"Reticle ray reports miss outside original hit volumes")
	crab_model=Node3D.new();arena.add_child(crab_model);crab_model.position=Vector3(0,.65,2)
	shape_boss._crablets.append({"id":20,"node":crab_model,"hp":100,"dead":false})
	geometry_hit=shape_boss.segment_hit(Vector3(0,1,0),Vector3(0,1,10))
	expect(int(geometry_hit.crab)==0,"Closest crablet replaces the farther Boss surface")
	near(geometry_hit.distance,2,"Source crab segment uses nearest-center parameter")
	crab_model.position.z=8
	expect(int(shape_boss.segment_hit(Vector3(0,1,0),Vector3(0,1,10)).crab)==-1,"Far crablet cannot intercept a nearer Boss hit")
	shape_boss._crablets.clear();crab_model.queue_free()
	shape_boss.fixture_shapes=[{"center":Vector3(0,1.05,6),"radius":1.8,"weak":false,"active":true,"socket":"shellF"}]
	arena.boss=shape_boss
	unit.weapon_id="charger";unit.reset_weapon();unit.charge=1;unit.aim_point=Vector3(0,1.05,27)
	weapons._charger(unit,Rules.weapon("charger"))
	var beam_end:Vector3=Vector3.INF
	for event in arena.events:
		if event.kind=="weapon:beam":beam_end=event.data.to
	near(beam_end.z,4.1,"Native charger beam stops at exact Boss sphere with .1padding",.005)
	near(shape_boss.hp,9840,"Charger applies one source direct hit to the nearest Boss sphere")
	shape_boss.hp=10000
	arena.cover=true
	shape_boss.splash(unit,Vector3(0,1.05,3),3.1,180,"bomb",35)
	near(shape_boss.hp,10000,"Solid cover blocks source Boss splash")
	arena.cover=false
	shape_boss.splash(unit,Vector3(0,1.05,3),3.1,180,"bomb",35)
	near(shape_boss.hp,9907.09677,"Source Boss splash falls off from nearest normal sphere before weapon resistance",.01)
	shape_boss.invuln=true;unit.is_local=true
	arena.events.clear();shape_boss.damage(40,unit,"shooter",true,Vector3(0,1,4))
	expect(arena.events.size()==1 and bool(arena.events[0].data.blocked) and arena.events[0].data.damage==0,"Source phase armour emits local blocked hit feedback without HP loss")
	arena.boss=null
	reset_rounds()
	var brains:=Bots.new();brains.configure(arena)
	near(brains.boss_goal_radius("charger"),18.4,"Source charger Boss flank radius")
	near(brains.boss_goal_radius("roller"),6.6,"Source roller Boss flank radius")
	near(brains.boss_goal_radius("shooter"),12.15,"Source shooter Boss flank radius")
	near(brains.boss_goal_radius("charger",true),9.4,"Source stunned Boss draws ranged squad toward exposed belly")
	unit=actor("shooter",0,Vector3(0,0,15))
	var mate=actor("shooter",0,Vector3(.3,0,15))
	var separation:Vector3=brains.separate(unit,Vector3.FORWARD)
	expect(separation.x<0 and separation.z<0,"Source sideways separation steers away from nearby squadmate without reversing travel")
	shape_boss.global_position=Vector3.ZERO;shape_boss.invuln=false;shape_boss.stunned=false
	arena.boss=shape_boss
	var bot_state:Dictionary={"goal":unit.global_position,"path":PackedVector3Array(),"path_index":0,"goal_time":0}
	seed(18);brains._boss_goal(unit,shape_boss,bot_state)
	var goal:Vector3=bot_state.goal
	var bearing:float=absf(wrapf(atan2(goal.x,goal.z)-shape_boss.rotation.y,-PI,PI))
	expect(bearing>=.95 and bearing<=2.85,"Source Boss goal lies on flank or rear instead of straight approach to its eyes")
	expect(Vector2(goal.x,goal.z).length()>10 and Vector2(goal.x,goal.z).length()<14,"Source shooter approach holds weapon distance from Boss center")
	expect(is_finite(float(bot_state.goal_time)),"Boss goal duration is finite")
	expect(float(bot_state.goal_time)>=2.4 and float(bot_state.goal_time)<=4.4,"Boss source goal reconsideration interval")
	arena.boss=null
	near(shape_boss.phase_times("sweep",2)[0],1.012,"Source phase2 telegraph pace")
	near(shape_boss.phase_times("sweep",2)[1],1.848,"Source phase2 active pace")
	near(shape_boss.phase_times("sweep",3)[2],.702,"Source phase3 recovery pace")
	near(shape_boss.charge_distance(.175,20,16),.7,"Source charge acceleration is distance-integrated")
	near(shape_boss.charge_distance(.35,20,16),2.8,"Source charge ramp covers2.8metres at phase3")
	near(shape_boss.charge_time(20,16),1.425,"Source charge duration follows actual lane length")
	near(shape_boss.charge_distance(5,20,16),20,"Source charge cannot exceed its body-safe lane")
	unit.global_position=Vector3(10,0,8.5);unit.invuln=0;unit.hp=100
	shape_boss.clock=0;shape_boss._weak_material=StandardMaterial3D.new()
	shape_boss._add_hazard("ring",Vector3(10,0,0),19,32,0,(19.0-2.4)/9.5)
	shape_boss.clock=1;shape_boss._tick_hazards(1)
	near(unit.hp,68,"Source swept shockwave band hits an actor skipped between low-rate frames")
	shape_boss.clock=1.01;shape_boss._tick_hazards(.01)
	near(unit.hp,68,"Source shockwave damages each actor once")
	unit.hp=100;unit.global_position.y=.55
	shape_boss._hazards[0].hits.clear();shape_boss.clock=1;shape_boss._tick_hazards(1)
	near(unit.hp,100,"Source jump higher than .5 clears floor shockwave")
	unit.global_position.y=-.9
	shape_boss._hazards[0].hits.clear();shape_boss._tick_hazards(1)
	near(unit.hp,100,"Source ring cannot hit actors under its floor")
	unit.global_position=Vector3(10,1.9,0);unit.hp=100;arena.cover=true
	shape_boss._damage_radius(Vector3(10,0,0),2.75,52,"boss_barrel",2.2)
	near(unit.hp,48,"Source barrel uses horizontal range and2.2height, independent of normal weapon splash LOS")
	arena.cover=false
	var approaching:Dictionary=shape_boss.threat(Vector3(10,0,14),1.4)
	expect(float(approaching.ringIn)>=0 and float(approaching.ringIn)<1.4,"Source Bots see shockwave arrival before the band reaches them")
	arena.events.clear();shape_boss.invuln=false;shape_boss.damage(5,unit,"storm",false,null)
	var boss_feedback:Dictionary={}
	for event in arena.events:
		if event.kind=="boss:hit":boss_feedback=event.data
	expect(boss_feedback.get("pos") is Vector3 and not bool(boss_feedback.get("has_point",true)),"Area Boss damage carries a finite display position without inventing a direct bullet impact")
	var hooks=preload("res://scripts/game/ink_boss_events.gd").new()
	hooks.play("boss_slam_act",1.2,3)
	var impacts:int=0
	for hook in hooks.advance(.59):
		if hook.kind=="impact":impacts+=1
	expect(impacts==1,"Source phase3 slam has its first claw impact at act start")
	for hook in hooks.advance(.02):
		if hook.kind=="impact":impacts+=1
	expect(impacts==2,"Source phase3 slam repeats its claw impact at .6 seconds")
	hooks.play("boss_sweep_act",1.05,1)
	near(hooks.scale,2.0,"Source clip hooks and poses share normalized active-phase duration")
	hooks.play("boss_run")
	var stride_count:int=0
	for hook in hooks.advance(3.0):
		if hook.kind=="foot":stride_count+=1
	expect(stride_count==hooks.events.size()*2,"Source locomotion footsteps survive loop crossings without lost or repeated hooks")
	var threat_state:Dictionary={"threat_seen":2.0,"hop_miss":false}
	var warning:Dictionary={"level":1.0,"ringIn":.15,"beam":true,"cover":true}
	brains.register_boss_threat(threat_state,warning,{"reaction":.32,"fireDiscipline":.7},1.9)
	expect(float(warning.level)==0 and float(warning.ringIn)==-1 and not warning.beam and not warning.cover,"Source Boss telegraph waits for bot perception reaction before influencing dodges")
	warning={"level":1.0,"ringIn":.15,"beam":true,"cover":true}
	brains.register_boss_threat(threat_state,warning,{"reaction":.32,"fireDiscipline":.7},2.0)
	expect(float(warning.level)==1 and float(warning.ringIn)==.15,"Source Boss warning becomes visible to AI exactly at registered reaction time")
	brains.register_boss_threat(threat_state,{"level":0.0,"ringIn":-1},{"reaction":.32},2.1)
	expect(not threat_state.has("threat_seen"),"Source bot forgets a cleared hazard so the next hazard gets a fresh reaction")
	shape_boss.move_id="slam";shape_boss.move_time=0;shape_boss._timing=[1.15,1.2,1.0]
	var wave_reach:PackedFloat32Array=[];wave_reach.resize(96);wave_reach.fill(19)
	shape_boss._move_params={"center":Vector3(10,0,0),"rings":[0.0,.9],"reach":wave_reach};shape_boss._hazards.clear()
	var future_wave:Dictionary=shape_boss.threat(Vector3(10,0,4),1.4)
	near(float(future_wave.ringIn),1.15+(4.0-.55-2.4)/9.5,"Source bots forecast ring arrival from the telegraph before the wave spawns")
	shape_boss.move_id=""
	print("Gameplay source contract: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
