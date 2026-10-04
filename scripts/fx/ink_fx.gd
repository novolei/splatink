class_name InkFx
extends Node3D

## Original fx.js recipes, rendered in six pooled MultiMesh paths with no per-particle nodes.
const DropPool = preload("res://scripts/fx/drop_pool.gd")
const RingPool = preload("res://scripts/fx/ring_pool.gd")
const SheetPool = preload("res://scripts/fx/sheet_pool.gd")
const SpritePool = preload("res://scripts/fx/sprite_pool.gd")
const BeamPool = preload("res://scripts/fx/beam_pool.gd")
const ProjectilePool = preload("res://scripts/fx/projectile_pool.gd")
const ScreenFx = preload("res://scripts/fx/screen_fx.gd")
const BossPool=preload("res://scripts/fx/boss_pool.gd")
const FxColors = preload("res://scripts/fx/ink_fx_colors.gd")
static var WATER: Color = FxColors.from_srgb(Color("bfe9ff"))
static var FOAM: Color = FxColors.from_srgb(Color("eef9ff"))
static var DUST: Color = FxColors.from_srgb(Color("b8a98f"))
var game: Node
var drops: InkDropPool
var rounds: InkProjectilePool
var rings: InkRingPool
var sheets: InkSheetPool
var puffs: InkSpritePool
var glows: InkSpritePool
var beams: InkBeamPool
var screen: InkScreenFx
var boss_pool:InkBossFxPool
var quality: float = 1.0
var time: float = 0.0
var max_drops: int = 2048
var _actor_state: Dictionary = {}
var _schedule: Array[Dictionary] = []
var _camera: Camera3D
var _hit_times: Dictionary = {}
var profile_fx:bool=false
var update_profile:Dictionary={}
var _event_cpu_us:int=0
var _event_count:int=0
var lighting:Dictionary={"sun_direction":Vector3(-.41,.83,-.38).normalized(),"sun_color":Color(1.0,.93,.84),"sky_color":Color(.42,.62,.95),"ground_color":Color(.5,.46,.42)}

func configure(controller: Node) -> void:
	game = controller
	profile_fx=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-render"):profile_fx=true;break
	name = "InkFx"
	drops = DropPool.new()
	add_child(drops)
	drops.initialize(2048)
	drops.game = game
	drops.landed.connect(_drop_landed)
	rounds = ProjectilePool.new()
	add_child(rounds)
	rounds.initialize()
	rings = RingPool.new()
	add_child(rings)
	rings.initialize(160)
	sheets = SheetPool.new()
	add_child(sheets)
	sheets.initialize(64)
	puffs = SpritePool.new()
	add_child(puffs)
	puffs.initialize(384, false)
	glows = SpritePool.new()
	add_child(glows)
	glows.initialize(768, true)
	beams = BeamPool.new()
	add_child(beams)
	beams.initialize(96)
	screen = ScreenFx.new()
	add_child(screen)
	screen.configure(game)
	boss_pool=BossPool.new();add_child(boss_pool);boss_pool.initialize()
	var settings = game.get("settings")
	set_quality(settings if settings is Dictionary else {})
	set_lighting({})
	var stage=game.get("stage")
	if stage is InkStage:configure_lighting(stage.lighting_theme)

func configure_lighting(theme:Dictionary) -> void:
	# Environment.getSkyColors returns linear colors; its ground is the hemisphere
	# bounce (hemiGround * hemiGroundK), not the sky-dome's ground hex.
	if theme.is_empty():return
	var el:float=deg_to_rad(float(theme.get("sunEl",39)))
	var az:float=deg_to_rad(float(theme.get("sunAz",222)))
	set_lighting({"sunDir":Vector3(cos(el)*cos(az),sin(el),cos(el)*sin(az)),"sunColor":FxColors.from_srgb(Color(str(theme.get("sunColor","fff0dc")))),"sunIntensity":float(theme.get("sunIntensity",3)),"sky":FxColors.from_srgb(Color(str(theme.get("skyMid","5aa8f2")))),"horizon":FxColors.from_srgb(Color(str(theme.get("horizon","d4ecfa")))),"ground":_bright(FxColors.from_srgb(Color(str(theme.get("hemiGround","dcc3a0")))),float(theme.get("hemiGroundK",1)))})

func set_lighting(options:Dictionary) -> void:
	# Source FX.setLighting contract: every Color in this options dictionary is linear.
	if options.has("sunDir"):lighting.sun_direction=Vector3(options.sunDir).normalized()
	var sun=options.get("sunColor",options.get("sun"))
	if sun is Color:lighting.sun_color=_bright(sun,minf(1.25,float(options.get("sunIntensity",3))/3.0))
	var sky=options.get("sky",options.get("zenith"))
	if sky is Color:
		lighting.sky_color=sky.lerp(options.horizon,.45) if options.get("horizon") is Color else sky
	if options.get("ground") is Color:lighting.ground_color=options.ground
	if drops:drops.set_lighting(lighting)
	if sheets:sheets.set_lighting(lighting)

func set_quality(settings: Dictionary) -> void:
	var preset: String = str(settings.get("quality", "high"))
	quality = 0.4 if preset == "low" else (0.7 if preset == "medium" else 1.0)
	if OS.has_feature("mobile"):
		quality = minf(quality, 0.7)
	max_drops = 512 if quality <= 0.4 else (1024 if quality <= 0.7 else 2048)
	if drops:
		drops.collision_budget = 8 if quality <= 0.4 else (16 if quality <= 0.7 else 24)
	if rounds:
		rounds.quality = quality
	if screen:
		screen.set_quality(settings, quality)
	if boss_pool:boss_pool.set_quality(quality)

func clear() -> void:
	for pool in [drops, rounds, rings, sheets, puffs, glows, beams]:
		if pool:
			pool.clear()
	_actor_state.clear()
	_schedule.clear()
	_hit_times.clear()
	if screen:
		screen.reset()
	if boss_pool:boss_pool.clear()

func _color(actor, team: int = 0) -> Color:
	if is_instance_valid(actor) and actor.has_method("team_color"):
		return FxColors.from_srgb(actor.call("team_color"))
	var colors = game.get("team_colors")
	return FxColors.from_srgb(colors[clampi(team, 0, 1)]) if colors is Array and colors.size() >= 2 else Color.WHITE

func _near(point: Vector3, distance: float = 36.0) -> bool:
	return not _camera or _camera.global_position.distance_squared_to(point) < distance * distance

func _drop(p: Vector3, v: Vector3, col: Color, size: float, life: float = 1.2, gravity: float = 1.0, stretch: float = 1.3, cosmetic: bool = false) -> void:
	if drops.alive.size() < max_drops:
		drops.drop(p, v, col, size, life, gravity, stretch, 1.0, 0.0, cosmetic, true)

func _bright(color: Color, intensity: float) -> Color:
	return Color(color.r * intensity, color.g * intensity, color.b * intensity, color.a)

func _glow(p: Vector3, col: Color, start: float, finish: float, life: float, alpha: float = 1.0, kind: float = 2.0, velocity: Vector3 = Vector3.ZERO) -> void:
	glows.sprite(p, velocity, col, start, finish, life, alpha, kind, 0.0, 0.0, 0.0, 0.0)

func _mist(p: Vector3, velocity: Vector3, col: Color, size: float = 0.2, alpha: float = 0.25) -> void:
	puffs.sprite(p, velocity, col.lerp(Color.WHITE, 0.4), size * 0.45, size * 1.4, randf_range(0.3, 0.42), alpha, 0.0, 4.5, 0.2)

func _sheet(p: Vector3, normal: Vector3, col: Color, start: float, finish: float, life: float, crown: float = 0.0) -> void:
	if _near(p, 24.0) and (quality > 0.4 or randf() < 0.65):
		sheets.sheet(p, normal, col, start, finish, life, crown)

func _ring(p: Vector3, normal: Vector3, col: Color, radius: float, life: float = 0.35, thickness: float = 1.0) -> void:
	rings.ring(p, normal, col, radius, life, thickness)

func _climb_drip(p:Vector3,normal:Vector3,col:Color) -> void:
	_drop(p+normal*.06+Vector3(randf_range(-.1,.1),randf_range(-.1,.1),randf_range(-.1,.1)),normal*.25+Vector3(randf_range(-.1,.1),randf_range(-1,-.4),randf_range(-.1,.1)),col,randf_range(.024,.046),1.4,.5,1.3)

func _ripple(p: Vector3, amplitude: float, wavelength: float, speed: float, life: float) -> void:
	var stage = game.get("stage")
	if is_instance_valid(stage) and stage.has_method("ripple"):
		stage.call("ripple", p, amplitude, wavelength, speed, life)

func _drop_landed(p: Vector3, normal: Vector3, col: Color, radius: float, paint: bool, water: bool) -> void:
	var flags:int=drops.landing_flags
	if water:
		if (flags&(DropPool.F_MATTE|DropPool.F_QUIET))!=0:return
		_ring(p+Vector3.UP*.01, Vector3.UP, col.lerp(Color.WHITE, .55), .18 + radius * 2.5, .45)
		return
	if (flags&DropPool.F_MATTE)!=0:return
	if not paint and ((flags&DropPool.F_RING)!=0 or radius>.03):
		_ripple(p, .0016 + radius * .05, .07 + radius * .5, .75, .42)
	if (flags&DropPool.F_QUIET)!=0:return
	if radius > .075 and drops.alive.size() < max_drops - 8 and randf() < .6:
		for i in range(1+(1 if randf()<.5 else 0)):
			drops.drop(p+normal*.03,_cone(normal,1.15)*randf_range(1.3,3.2),col,radius*.3,.45,1,1,1,0,false,true,DropPool.F_NOCOL)

func _basis(normal: Vector3) -> Basis:
	var axis: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var tangent: Vector3 = reference.cross(axis).normalized()
	return Basis(tangent, axis.cross(tangent), axis)

func _cone(normal: Vector3, angle: float) -> Vector3:
	var z: float = 1.0 - randf() * (1.0 - cos(angle))
	var radius: float = sqrt(maxf(0.0, 1.0 - z * z))
	var phi: float = randf() * TAU
	return _basis(normal) * Vector3(radius * cos(phi), radius * sin(phi), z)

func _sphere() -> Vector3:
	var y: float = randf_range(-1, 1)
	var radius: float = sqrt(1.0 - y * y)
	var phi: float = randf() * TAU
	return Vector3(radius * cos(phi), y, radius * sin(phi))

func burst(p: Vector3, normal: Vector3, col: Color, count: float = 12.0, speed: float = 4.0, size: float = 0.1, spread: float = 0.9, cosmetic: bool = false) -> void:
	var n: int = maxi(1, roundi(count * quality))
	var origin: Vector3 = p + normal * 0.04
	for i in range(n):
		var direction: Vector3 = _cone(normal, maxf(0.05, spread) * PI * 0.5)
		var sp: float = speed * randf_range(0.5, 1.3)
		var radius: float = size * randf_range(0.35, 0.95)
		_drop(origin, direction * sp, col, radius, randf_range(1.6, 2.2), 1, 1.3, cosmetic)
		if randf() < 0.45:
			_drop(origin, direction * sp * randf_range(0.7, 1.2) + _sphere() * 0.4, col, radius * 0.4, 1.2)
	if n >= 4:
		var splash: float = size * (1.6 + 0.5 * sqrt(float(n)))
		_sheet(p + normal * splash * 0.12, normal, col, splash * 0.35, splash * 1.1, 0.17 + splash * 0.12, 1.0)

func _crown(p: Vector3, normal: Vector3, col: Color, count: float, speed: float, size: float, cosmetic: bool = false) -> void:
	var basis: Basis = _basis(normal)
	var n: int = maxi(1, roundi(count * quality))
	var a0: float = randf() * TAU
	for i in range(n):
		var angle: float = a0 + float(i) / float(n) * TAU + randf_range(-0.25, 0.25)
		var direction: Vector3 = (basis.x * cos(angle) + basis.y * sin(angle)) * randf_range(0.6, 1.2) + normal * randf_range(0.7, 1.6)
		_drop(p + normal * 0.04, direction * speed * randf_range(0.6, 1.2), col, size * randf_range(0.55, 1.35), 1.2, 1, 1, cosmetic)

func _burst_drops(p: Vector3, col: Color, radius: float, speed: float, ligaments: int = 26, heavy: int = 6, fine: int = 18) -> void:
	for i in range(roundi(float(ligaments) * quality)):
		var direction: Vector3 = _sphere()
		direction.y = absf(direction.y) * 0.85 + 0.12
		direction = direction.normalized()
		_drop(p + direction * radius * 0.3, direction * randf_range(6, 13) * speed, col, randf_range(0.03, 0.06), 1.6, 1, 1.5, randf() < 0.3)
	for i in range(roundi(float(heavy) * quality)):
		var angle: float = randf() * TAU
		var sp: float = randf_range(2.2, 4.8) * speed
		_drop(p + Vector3.UP * 0.2, Vector3(cos(angle) * sp, randf_range(3.2, 6.2), sin(angle) * sp), col, randf_range(0.07, 0.105), 2.2, 1, 1, true)
	for i in range(roundi(float(fine) * quality)):
		var direction: Vector3 = _sphere()
		direction.y = absf(direction.y) * 0.7 + 0.2
		_drop(p, direction.normalized() * randf_range(4, 10) * speed, col, randf_range(0.011, 0.027), 1.0)

func explosion(p: Vector3, col: Color, radius: float = 3.0) -> void:
	var visual_radius: float = minf(radius, 2.4)
	_glow(p, _bright(col, 4.5), visual_radius * 0.4, visual_radius * 0.85, 0.12, 1, 6)
	_glow(p, _bright(col, 1.15), visual_radius * 0.9, visual_radius * 1.6, 0.17, 0.5)
	_sheet(p, Vector3.UP, col, visual_radius * 0.2, visual_radius * 0.78, 0.34)
	_burst_drops(p, col, visual_radius, sqrt(radius / 3.0))
	_ring(p, Vector3.UP, col, radius * 1.1, 0.55, 1.2)
	_ripple(p, .011 + .0028 * radius, .24 + .03 * radius, 2.1 + .4 * radius, 1.05)
	for i in range(roundi(4.0 * quality)):
		var dir: Vector3 = _sphere()
		dir.y = absf(dir.y) * 0.5
		puffs.sprite(p + dir * radius * randf_range(0.2, 0.6), dir * 1.8 + Vector3.UP * randf_range(0.5, 1.1), col.lerp(Color.WHITE,.42), visual_radius * .225, visual_radius * .7, randf_range(.3,.42), .12, 0, 4.5, .2)

func muzzle(p: Vector3, dir: Vector3, col: Color, kind: String) -> void:
	var blast: bool = kind == "blaster"
	var charge: bool = kind == "charger"
	var flash_color: Color = _bright(col.lerp(Color.WHITE,.4),3.5) if charge else _bright(col,4.5 if blast else 4.0)
	_glow(p + dir * 0.05, flash_color, 0.35 if blast else (0.7 if charge else 0.2), 0.7 if blast else 0.38, 0.14 if charge else 0.07, 1, 13 if charge else 4)
	if not blast and not charge:
		_glow(p,_bright(col,1.2),.4,.6,.1,.8,0)
	if blast or charge:
		_ring(p + dir * 0.15, dir, col.lerp(Color.WHITE, 0.3), 0.55 if blast else 0.38, 0.16, 1.0)
	var n: int = maxi(2, roundi((9.0 if blast else 5.0) * quality))
	for i in range(n):
		_drop(p, _cone(dir, 0.4 if blast else (0.14 if charge else 0.28)) * randf_range(10 if charge else 6, 18 if charge else 13), col, randf_range(0.018, 0.055), 0.25 if charge else 0.4, 0.4 if charge else 0.6, 1.8 if charge else 1.4)
	if blast:
		for i in 2:puffs.sprite(p+dir*.3,dir*(2.0+i*1.5)+Vector3.UP*.4,col.lerp(Color.WHITE,.45),.2,.7,.4,.32,0,5)
	elif not charge:
		_mist(p + dir * 0.15, dir * 2.5 + Vector3.UP * 0.3, col, 0.27, 0.25)

func _form_pop(p: Vector3, col: Color, to_squid: bool, in_ink: bool) -> void:
	var origin: Vector3 = p + Vector3.UP * (0.35 if to_squid else 0.55)
	puffs.sprite(origin, Vector3.UP * (-0.2 if to_squid else 0.6), col.lerp(Color.WHITE, 0.35), 0.22, 0.62, 0.26, 0.25 if in_ink else 0.38, 0, 5)
	var normal: Vector3 = (_camera.global_position - origin).normalized() if _camera else Vector3.UP
	_ring(origin, normal, col.lerp(Color.WHITE, 0.4), 0.5, 0.16)
	_crown(origin, Vector3.UP, col, 5, 1.8, 0.032)

func _dive(p: Vector3, col: Color, speed: float) -> void:
	_ripple(p, .008 + minf(.006, speed * .0006), .15, 1.5, .85)
	_crown(p, Vector3.UP, col, 10.0 + speed * 0.6, 2.2 + minf(2.5, speed * 0.18), 0.036)
	if speed > 3:
		_sheet(p + Vector3.UP * 0.04, Vector3.UP, col, 0.12, 0.34 + minf(0.25, speed * 0.02), 0.2, 1)
	_ring(p, Vector3.UP, col.lerp(Color.WHITE, 0.2), 0.7, 0.55)
	_bubbles(p, col, 3)

func _bubbles(p: Vector3, col: Color, count: int) -> void:
	for i in range(maxi(1, roundi(float(count) * quality))):
		glows.sprite(p + Vector3(randf_range(-0.25, 0.25), 0.05, randf_range(-0.25, 0.25)), Vector3.UP * randf_range(0.3, 0.6), _bright(col.lerp(Color.WHITE, 0.55),1.1), randf_range(0.04, 0.08), randf_range(0.08, 0.12), randf_range(0.3, 0.55), 0.8, 21, 1, 0, 0.04, 0)

func _enemy_ink_sizzle(p:Vector3,col:Color) -> void:
	var tint:Color=_bright(col.lerp(Color.WHITE,.35),1.3)
	for i in 1+(1 if randf()<.5 else 0):
		var angle:float=randf()*TAU
		var radius:float=randf_range(.12,.37)
		glows.sprite(p+Vector3(cos(angle)*radius,.04,sin(angle)*radius),Vector3.UP*randf_range(.22,.42),tint,randf_range(.035,.065),randf_range(.07,.10),randf_range(.28,.46),.85,21,1,0,.05,0)
	if randf()<.3:
		_drop(p+Vector3(randf_range(-.15,.15),.04,randf_range(-.15,.15)),Vector3(randf_range(-.2,.2),randf_range(.8,1.4),randf_range(-.2,.2)),col,randf_range(.018,.03),.4,1,1)

func _shot_trail(p:Vector3,velocity:Vector3,col:Color,big:bool=false) -> void:
	var size:float=.3 if big else .14
	puffs.sprite(p,velocity*.06+Vector3.UP*.1,col.lerp(Color.WHITE,.42),size*.5,size*1.5,.4 if big else .26,.3 if big else .2,0,5,.1)
	if randf()<(.8 if big else .35):
		_drop(p,velocity*.25+Vector3(randf_range(-.5,.5),0,randf_range(-.5,.5)),col,randf_range(.03,.05) if big else randf_range(.016,.028),.8,1,1.4)

func _trail_random() -> float:
	return randf()

func _slosh_trail(p:Vector3,velocity:Vector3,col:Color,head:bool=false) -> void:
	var count:int=2 if head else (1 if _trail_random()<.6 else 0)
	for i in count:
		var pos:Vector3=p+Vector3((_trail_random()-.5)*.08,-.04,(_trail_random()-.5)*.08)
		var v:Vector3=Vector3(velocity.x*.25+(_trail_random()-.5)*.8,velocity.y*.2-.5,velocity.z*.25+(_trail_random()-.5)*.8)
		_drop(pos,v,col,(.026 if head else .018)+_trail_random()*.016,1.1,1,1.5)

func _footstep(p: Vector3, col: Color, surface: int, direction: Vector3, speed: float) -> void:
	if surface == 0:
		if speed < 3.2:
			return
		puffs.sprite(p + Vector3.UP * 0.08, -direction * 0.6 + Vector3.UP * 0.4, DUST, 0.13, 0.4, 0.6, 0.42, 4, 3.2, 0.15)
	else:
		var k: float = clampf(speed / 7.0, 0.3, 1.2)
		_ripple(p, .0035 + .002 * k if surface == 1 else .003, .1 if surface == 1 else .08, .9 if surface == 1 else .55, .55 if surface == 1 else .5)
		burst(p, (-direction * 0.55 + Vector3.UP).normalized(), col, 2.0 + 2.5 * k if surface == 1 else 3.0, 2.0 if surface == 1 else 1.3, 0.04, 0.45)

func _land(p: Vector3, col: Color, surface: int, speed: float) -> void:
	var k: float = clampf((speed - 3.0) / 12.0, 0, 1)
	if surface == 0:
		_ring(p, Vector3.UP, DUST, 0.8 + 1.1 * k, 0.5)
		for i in range(roundi((4.0 + 6.0 * k) * quality)):
			var dir: Vector3 = _sphere()
			dir.y = 0.15
			puffs.sprite(p + Vector3.UP * 0.05, dir * (1.4 + 1.6 * k), DUST, 0.10, 0.45, 0.5, 0.4, 4)
	else:
		_crown(p, Vector3.UP, col, 8 + 16 * k, 2.4 + 2.2 * k, 0.04 + 0.018 * k)
		_ripple(p, .007 + .006 * k, .16, 1.6 + k, .8)
		if k > 0.25:
			_sheet(p + Vector3.UP * 0.05, Vector3.UP, col, 0.15, 0.4 + 0.35 * k, 0.22, 1)
		_ring(p, Vector3.UP, col.lerp(Color.WHITE, 0.2), 0.65 + k * 0.6, 0.5)

func _flick(p: Vector3, dir: Vector3, col: Color, spread: float = 34.0) -> void:
	var yaw: float = atan2(dir.x, dir.z)
	var n: int = maxi(6, roundi(30.0 * quality))
	for i in range(n):
		var t: float = float(i) / float(n - 1) * 2.0 - 1.0
		var angle: float = yaw + t * deg_to_rad(spread) * 0.55 + randf_range(-0.04, 0.04)
		var up: float = randf_range(0.35, 0.7)
		var speed: float = 6.0 + randf() * 5.0 * (1.0 - 0.4 * absf(t))
		var radius: float = randf_range(0.03, 0.07)
		_drop(p + Vector3(sin(angle), randf_range(-0.12, 0.28), cos(angle)) * 0.4, Vector3(sin(angle) * cos(up), sin(up), cos(angle) * cos(up)) * speed, col, radius, 1.4, 1, 1.2, radius > 0.055)
	_sheet(p + dir * 0.4, dir, col, 0.15, 0.9, 0.25, 0.4)

func _beam_fire(from: Vector3, to: Vector3, col: Color, charge: float) -> void:
	beams.line(from, to, col, 0.035 + charge * 0.05, 0.3 + charge * 0.1, charge)
	muzzle(from, (to - from).normalized(), col, "charger")
	var n: int = mini(40, floori(from.distance_to(to) / 0.75))
	for i in range(1, n + 1):
		var p: Vector3 = from.move_toward(to, float(i) * 0.75 - randf() * 0.3)
		if i % 2 == 0 or quality >= 1:
			_mist(p, Vector3.UP * 0.15, col, 0.13 + charge * 0.05, 0.28)
		if randf() < 0.45 * quality:
			_drop(p, Vector3(randf_range(-0.3, 0.3), randf_range(-1.5, -0.5), randf_range(-0.3, 0.3)), col, randf_range(0.016, 0.034), 0.9)
	burst(to, -(to - from).normalized(), col, 8 + 10 * charge, 4.5, 0.07)
	_glow(to, _bright(col, 4), 0.4 + 0.5 * charge, 0.9 + 0.6 * charge, 0.12, 1, 4)

func _slam_wave(p: Vector3, col: Color, radius: float) -> void:
	_ripple(p, .016, .32, 3.2, 1.3)
	_ring(p, Vector3.UP, col, radius * 1.45, 0.6, 1.4)
	_schedule.append({"at": time + 0.1, "p": p, "normal": Vector3.UP, "color": col, "radius": radius * 1.85, "life": 0.5})
	for i in range(maxi(6, roundi(20.0 * quality))):
		var angle: float = randf() * TAU
		var speed: float = randf_range(5, 9)
		_drop(p + Vector3(cos(angle) * 0.6, 0.3, sin(angle) * 0.6), Vector3(cos(angle) * speed, randf_range(4, 7), sin(angle) * speed), col, randf_range(0.1, 0.16), 2.2, 1, 1.1, true)
	beams.line(p, p + Vector3.UP * 5.5, _bright(col, 1.2), 1.3, 0.6)

func _launch(p: Vector3, col: Color, superjump: bool) -> void:
	_ring(p, Vector3.UP, col, 2.2 if superjump else 1.5, 0.45)
	var n: int = maxi(6, roundi((30.0 if superjump else 18.0) * quality))
	for i in range(n):
		_drop(p + Vector3(randf_range(-0.25, 0.25), 0.1, randf_range(-0.25, 0.25)), _cone(Vector3.UP, 0.35 if superjump else 0.45) * randf_range(9 if superjump else 5, 16 if superjump else 10), col, randf_range(0.035, 0.08), 1.6, 1, 1.5)
	if superjump:
		beams.line(p, p + Vector3.UP * 12.0, _bright(col, 1.3), 0.9, 0.8)
		_glow(p + Vector3.UP * 0.6, _bright(col, 4), 1.2, 2.4, 0.22, 1, 4)

func _super_land(p: Vector3, col: Color) -> void:
	_ripple(p, .013, .24, 2.4, 1.1)
	_ring(p, Vector3.UP, col, 2.4, 0.45, 1.2)
	_ring(p, Vector3.UP, col, 3.0, 0.3)
	_crown(p, Vector3.UP, col, 26, 4.2, 0.045)
	_sheet(p + Vector3.UP * 0.1, Vector3.UP, col, 0.2, 0.9, 0.3, 1)
	_glow(p + Vector3.UP * 0.5, _bright(col, 3), 0.8, 1.8, 0.18, 1, 3)

func _spawn_flash(p:Vector3,col:Color) -> void:
	beams.line(p,p+Vector3.UP*10.0,_bright(col,1.25),1.15,1.0)
	_glow(p+Vector3.UP*.8,_bright(col,4),2.2,3.8,.3,1,5)
	_ring(p,Vector3.UP,col,2.8,.6,1.3)
	_schedule.append({"at":time+.12,"p":p,"normal":Vector3.UP,"color":col,"radius":3.6,"life":.6})
	_ripple(p,.012,.24,2.6,1.1)
	for i in roundi(40*quality):
		var angle:float=randf()*TAU
		var radius:float=randf()*.7
		_drop(p+Vector3(cos(angle)*radius,.1,sin(angle)*radius),Vector3(cos(angle)*randf_range(.6,2.4),randf_range(7,16),sin(angle)*randf_range(.6,2.4)),col,randf_range(.05,.12),1.6,1,1.2)
	for i in roundi(8*quality):
		var angle:float=randf()*TAU
		puffs.sprite(p+Vector3(cos(angle)*.8,.3,sin(angle)*.8),Vector3(cos(angle)*2.5,.8,sin(angle)*2.5),col.lerp(Color.WHITE,.3),.5,1.3,randf_range(.7,1.1),.45,0,3,.4)
	for i in 6:
		var angle:float=float(i)/6.0*TAU+randf()*.5
		var radius:float=randf_range(.9,1.7)
		glows.sprite(p+Vector3(cos(angle)*radius,randf_range(.5,3.0),sin(angle)*radius),Vector3.UP*randf_range(1.2,2.2),_bright(col.lerp(Color.WHITE,.55),2.4),.35,.18,randf_range(.5,.8),1,12,1,0,.05,1.5)

func _slosh_impact(p:Vector3,n:Vector3,d:Vector3,col:Color) -> void:
	var origin:Vector3=p+n*.03
	_sheet(origin,n,col,.3,1.05,.3,1)
	var forward:Vector3=Vector3(d.x,0,d.z).normalized()
	if forward.length_squared()<.001:forward=Vector3.BACK
	var right:=Vector3(forward.z,0,-forward.x)
	for i in maxi(6,roundi(18*quality)):
		var side:float=randf_range(-1,1)
		_drop(origin+right*side*.3+Vector3.UP*.05,forward*randf_range(3.5,7)+right*side*2.2+Vector3.UP*randf_range(1.2,3.4),col,randf_range(.02,.05),1.2,1,1.5,randf()<.3)
	for i in maxi(2,roundi(5*quality)):
		var angle:float=randf()*TAU
		var speed:float=randf_range(1.6,3.4)
		_drop(origin+Vector3.UP*.1,Vector3(cos(angle)*speed,randf_range(3,5.2),sin(angle)*speed)+forward*1.2,col,randf_range(.06,.09),1.8,1,1,true)
	_ripple(origin,.014,.26,2.3,1.05)

func _storm_start(p:Vector3,col:Color,radius:float) -> void:
	for i in roundi(10*quality)+2:
		var angle:float=randf()*TAU
		var distance:float=randf()*radius*.6
		puffs.sprite(p+Vector3(cos(angle)*distance,randf_range(-.3,.3),sin(angle)*distance),Vector3(cos(angle)*3.4,randf_range(-.45,1.05),sin(angle)*3.4),col.lerp(Color.WHITE,.2),radius*.25,radius*.6,randf_range(.7,1.1),.4,0,2.5,0,.05,.4)
	_glow(p,_bright(col,3),radius*.5,radius*1.3,.25,1,3)
	_ring(p,(_camera.global_position-p).normalized() if _camera else Vector3.UP,col,radius*1.4,.3,1.3)

func on_event(kind: String, data: Dictionary) -> void:
	if not profile_fx:
		_on_event_source(kind,data)
		return
	var start:int=Time.get_ticks_usec()
	_on_event_source(kind,data)
	_event_cpu_us+=Time.get_ticks_usec()-start;_event_count+=1

func _on_event_source(kind: String, data: Dictionary) -> void:
	if not drops:
		return
	if screen:
		screen.on_event(kind, data)
	var actor = data.get("actor", data.get("victim"))
	var event_position=data.get("pos")
	var pos:Vector3=event_position if event_position is Vector3 else (actor.global_position if is_instance_valid(actor) and actor is Node3D else Vector3.ZERO)
	if not _near(pos, 55.0) and kind not in ["explosion", "special:slam", "superjump", "superjump:land"]:
		return
	var col: Color = _color(actor, int(data.get("team", 0)))
	var normal: Vector3 = data.get("normal", Vector3.UP)
	var direction: Vector3 = data.get("dir", actor.aim_dir if is_instance_valid(actor) and actor is InkActor else Vector3.UP)
	match kind:
		"boss:impact","boss:fx":
			_boss_effect(kind,data,pos)
		"boss:hit":
			if bool(data.get("has_point",false)):
				var boss=data.get("boss")
				var away:Vector3=pos-boss.global_position if is_instance_valid(boss) else Vector3.UP
				away.y=.4
				burst(pos,away.normalized(),_color(data.get("attacker")),10 if bool(data.get("weak",false)) else 5,5 if bool(data.get("weak",false)) else 3,.08)
		"boss:crablet":
			if str(data.get("phase",""))=="pop":explosion(pos,_color(null,0 if bool(data.get("killed",false)) else 1),1.2 if bool(data.get("killed",false)) else 2.1)
		"weapon:shot":
			var weapon_kind: String = str(data.get("kind", "shooter"))
			muzzle(pos, direction, col, "blaster" if weapon_kind == "slosher" else weapon_kind)
		"weapon:flick":
			_flick(pos, direction, col)
		"weapon:beam":
			_beam_fire(data["from"], data["to"], col, float(data.get("charge", 1.0)))
		"impact:shot":
			var blaster_impact: bool = str(data.get("kind",""))=="blaster"
			burst(pos,normal,col,14 if blaster_impact else (6 if data.get("victim")!=null else 5),5.0 if blaster_impact else 3.0,.07)
			if bool(data.get("head", false)):
				burst(pos,Vector3.UP,col,16,4.2,.09)
				_ring(pos,Vector3.UP,col,1.1,.32)
				if data.get("victim")==null:_slosh_impact(pos,normal,direction,col)
		"explosion":
			explosion(pos+Vector3.UP*(.3 if str(data.get("kind"))=="slam" else 0.0),col,float(data.get("radius",3.1)))
		"special:slam":
			_slam_wave(pos, col, float(data.get("radius", 5.2)))
		"special_activate":
			if str(data.get("special", "")) == "slam":
				_launch(pos, col, false)
		"squid_in", "squid_out":
			_form_pop(pos, col, kind == "squid_in", bool(actor.submerged) if is_instance_valid(actor) else false)
		"actor:footstep":
			var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length() if is_instance_valid(actor) else 5
			_footstep(pos, _color(null, int(actor.ground_team)) if is_instance_valid(actor) and actor.ground_team >= 0 else col, int(data.get("surface", 0)), direction, speed)
		"actor:land":
			var surface: int = 1 if is_instance_valid(actor) and actor.ground_team == actor.team_id else (2 if is_instance_valid(actor) and actor.ground_team >= 0 else 0)
			_land(pos, col if surface != 2 else _color(null, 1 - actor.team_id), surface, float(data.get("speed", 8)))
		"actor:jump":
			burst(pos,Vector3.UP,col,8,4.0,.045,.3)
		"actor:ledgepop":
			burst(pos+Vector3.UP*.3,Vector3.UP,col,7,2.6,.07)
		"actor:climb":
			if bool(data.get("on",false)) and is_instance_valid(actor) and actor.alive and _near(pos,26) and actor.wall_normal.length_squared()>=.5:
				for i in 3:_climb_drip(pos+Vector3.UP*.35,actor.wall_normal,col)
				_ring(pos+Vector3.UP*.35+actor.wall_normal*.03,actor.wall_normal,col,.55,.3,.9)
		"weapon:dodge":
			burst(pos, (-direction * 0.8 + Vector3.UP * 0.9).normalized(), col, 14, 3.5, 0.046, 0.66, true)
			_sheet(pos + Vector3.UP * 0.03, Vector3.UP, col, 0.12, 0.5, 0.2, 1)
		"charger_full", "splatling_ready":
			var muzzle_pos: Vector3 = actor.avatar.call("get_muzzle") if is_instance_valid(actor) and actor.avatar else pos
			_glow(muzzle_pos, _bright(col.lerp(Color.WHITE, 0.5), 3.2), 1.0, 0.5, 0.32, 1, 13)
			_crown(muzzle_pos, direction, col, 16 if kind == "splatling_ready" else 8, 3.2, 0.03)
		"hit":
			var victim = data.get("victim")
			var attacker = data.get("attacker")
			if is_instance_valid(victim) and victim.alive and not bool(data.get("killed",false)) and float(data.get("damage",0))>0 and time-float(_hit_times.get(victim.get_instance_id(),-9.0))>=.05:
				_hit_times[victim.get_instance_id()] = time
				var hit_color: Color = _color(attacker, 1 - victim.team_id)
				var hit_dir: Vector3 = victim.global_position-attacker.global_position if is_instance_valid(attacker) and attacker is Node3D else Vector3.BACK
				hit_dir.y=0
				hit_dir=hit_dir.normalized() if hit_dir.length_squared()>.00001 else Vector3.BACK
				var k: float = clampf(float(data.get("damage",30))/60.0,.3,1.5)
				var p: Vector3 = victim.global_position + Vector3.UP * (0.3 if victim.form != "kid" else 0.95)
				_sheet(p - hit_dir * 0.28, hit_dir, hit_color, 0.08, 0.26 + 0.12 * k, 0.2)
				var origin: Vector3 = p-hit_dir*.28
				for i in maxi(3,roundi((6.0+8.0*k)*quality)):
					var back: bool = i%3==0
					var spray: Vector3 = _cone(-hit_dir if back else hit_dir,1.0 if back else .65)
					spray.y+=.3
					_drop(origin,spray*(randf_range(1.8,3.6) if back else randf_range(3.0,6.2)),hit_color,.02+randf()*.03*k,1.1,1,1.4)
				_glow(origin,_bright(hit_color,2.6),.25,.45+.15*k,.07,1,2)
				puffs.sprite(origin,Vector3(hit_dir.x*1.5,.3,hit_dir.z*1.5),hit_color.lerp(Color.WHITE,.35),.18,.45+.15*k,.28,.22,0,4)
		"splatted":
			if str(data.get("cause", "")) == "water":
				_water_splash(pos)
			else:
				_sheet(pos + Vector3.UP * 0.6, Vector3.UP, col, 0.28, 0.9, 0.34)
				_burst_drops(pos + Vector3.UP * 0.6, col, 1.2, 1, 30, 7, 22)
				_glow(pos + Vector3.UP * 0.6, _bright(col, 3.6), 0.8, 1.6, 0.14, 1, 5)
			puffs.sprite(pos + Vector3.UP * 0.35, Vector3.UP * 0.5, col.lerp(Color.WHITE, 0.3), 0.55, 0.85, 1.5, 0.8, 3, 1.2, 0.9, 0.18, 0, .35, .6)
		"respawn":
			_spawn_flash(data.get("ground_pos",pos),col)
		"storm:start":
			_storm_start(pos,col,float(data.get("radius",3.4)))
		"superjump":
			if str(data.get("phase", "")) == "flight":
				_launch(pos, col, true)
		"superjump:land":
			_super_land(pos, col)
		"special_ready":
			_ring(pos, Vector3.UP, col, 1.3, 0.45)
		"empty_click":
			_mist(pos + direction * 0.5 + Vector3.UP * 0.9, direction * 0.8, DUST, 0.14, 0.35)
		"boss_slam", "crablet_pop", "boss_crash":
			explosion(pos, _color(null, 1), 3 if kind == "boss_slam" else 2.1)

func _boss_effect(kind:String,data:Dictionary,pos:Vector3) -> void:
	var boss=data.get("boss")
	var gy:float=boss.global_position.y if is_instance_valid(boss) else pos.y
	var local_basis:Basis=boss.global_basis if is_instance_valid(boss) else Basis.IDENTITY
	boss_pool.set_ink(_color(null,1))
	var socket:String=str(data.get("socket",""))
	if kind=="boss:impact":
		match socket:
			"clawL":boss_pool.ink(pos,26,Vector3.UP,7,.9,.2,gy)
			"mouth":boss_pool.ink(pos,14,(local_basis*Vector3(0,.6,1)).normalized(),5,.9,.16,gy)
			"body":boss_pool.ink(pos,30,Vector3.UP,6,1,.2,gy)
	else:
		match str(data.get("name","")):
			"burst":
				var point:Vector3=boss.global_position+Vector3.UP*.3 if is_instance_valid(boss) else pos
				boss_pool.ink(point,90,Vector3.UP,13,.75,.3,gy,2.6);boss_pool.steam(point,14,Vector3.UP,4,2.5,2)
			"geyser":boss_pool.geyser(pos,3.6)
			"hatch":boss_pool.ink(pos,5,Vector3.UP,5,.5,.14,gy);boss_pool.steam(pos,2,Vector3.UP,2,.9,.9)
			"roar":
				if is_instance_valid(boss) and int(boss.get("phase"))>=3:boss_pool.steam(pos,10,(local_basis*Vector3(0,.5,1)).normalized(),3,1.2,1.3)
			"retire":burst(pos,Vector3.UP,_color(null,1),6,3,.08)

func _water_splash(p: Vector3) -> void:
	var pos := Vector3(p.x, -1.58, p.z)
	_crown(pos, Vector3.UP, WATER, 24, 6.0, 0.06)
	_ring(pos, Vector3.UP, FOAM, 1.32, 0.6)
	_schedule.append({"at": time + 0.12, "p": pos, "normal": Vector3.UP, "color": FOAM, "radius": 2.42, "life": 0.9})
	for i in range(roundi(5.0 * quality) + 1):
		puffs.sprite(Vector3(p.x+randf_range(-.5,.5),-1.6+.4,p.z+randf_range(-.5,.5)), Vector3(randf_range(-.75,.75),randf_range(1.5,2.5),randf_range(-.75,.75)), FOAM, .3, 1.0, randf_range(.9,1.3), .4, 0, 2, .1)

func update(dt: float, actors: Array) -> void:
	if not drops or dt <= 0.0:
		return
	time += dt
	var start:int=Time.get_ticks_usec() if profile_fx else 0
	if profile_fx:
		update_profile={"event_us":_event_cpu_us,"event_count":_event_count}
		_event_cpu_us=0;_event_count=0
	if screen:
		screen.update(dt)
	_camera = get_viewport().get_camera_3d()
	for i in range(_schedule.size() - 1, -1, -1):
		var item: Dictionary = _schedule[i]
		if float(item["at"]) <= time:
			_ring(item["p"], item["normal"], item["color"], float(item["radius"]), float(item["life"]))
			_schedule.remove_at(i)
	if profile_fx:update_profile.screen_schedule_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	for actor in actors:
		if is_instance_valid(actor) and actor.alive:
			_actor_effects(actor, dt)
	if profile_fx:update_profile.actor_recipes_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	var projectiles = game.get("projectiles")
	if is_instance_valid(projectiles):
		_projectile_effects(projectiles, dt)
		rounds.render_projectiles(projectiles.bullets, game.get("team_colors"))
	else:
		rounds.clear()
	if profile_fx:update_profile.projectile_recipes_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	_boss_hazard_effects()
	if profile_fx:update_profile.hazard_recipes_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	drops.update(dt, _camera)
	if profile_fx:
		update_profile.drops_us=Time.get_ticks_usec()-start
		for measure in drops.profile_update:update_profile["drops_"+str(measure)]=drops.profile_update[measure]
		start=Time.get_ticks_usec()
	puffs.update(dt, _camera)
	if profile_fx:update_profile.puffs_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	glows.update(dt, _camera)
	if profile_fx:update_profile.glows_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	rings.update(dt)
	sheets.update(dt)
	beams.update(dt)
	if profile_fx:update_profile.surface_beams_us=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
	boss_pool.update(dt,_camera)
	if profile_fx:
		update_profile.boss_pool_us=Time.get_ticks_usec()-start
		update_profile.drops_count=drops.alive.size();update_profile.puffs_count=puffs._active.size();update_profile.glows_count=glows._active.size()
		update_profile.rounds_count=rounds.multimesh.visible_instance_count;update_profile.rings_count=rings._rings.size();update_profile.sheets_count=sheets._sheets.size()

func _boss_hazard_effects() -> void:
	var boss=game.get("boss")
	if not is_instance_valid(boss) or bool(boss.get("dead")) or str(game.get("state"))!="playing":return
	var color:Color=_color(null,1)
	_boss_ring_effects(boss.get("_hazards"),color,float(boss.get("clock")))
	var displayed=boss.get("_visual_hazards")
	if displayed is Array:_boss_ring_effects(displayed,color,float(boss.get("clock")))
	var id:String=str(boss.get("move_id"));var phase_name:String=str(boss.get("move_phase"))
	if phase_name!="act":return
	var params:Dictionary=boss.get("_move_params")
	var timing:Array=boss.get("_timing")
	var t:float=float(boss.get("move_time"))-float(timing[0]) if not timing.is_empty() else 0.0
	if id=="frenzy":
		var origin:Vector3=boss.global_position
		for j in 6:
			var angle:float=float(params.rot0)+t*2.6+float(j)/6.0*TAU
			var direction:=Vector3(sin(angle),0,cos(angle));var speed:float=randf_range(10,15)
			_drop(origin+direction*2.2+Vector3.UP*2.2,direction*speed+Vector3.UP*randf_range(3,5),color,.16,1)
	elif id=="sweep" and randf()<.6:
		var beam:MeshInstance3D=boss.get("_beam")
		if is_instance_valid(beam) and beam.visible:
			var tip:Vector3=beam.global_transform*Vector3(0,0,1)
			tip.y+=.15-.3
			burst(tip,Vector3.UP,color,5,5,.12)

func _boss_ring_effects(records:Array,color:Color,clock:float) -> void:
	for hazard:Dictionary in records:
		if str(hazard.get("kind",""))!="ring":continue
		var t:float=clock-float(hazard.get("start",0))-float(hazard.get("delay",0))
		var radius:float=float(hazard.get("display_radius",2.4+9.5*t))
		if t<0 or radius>19:continue
		var reach:PackedFloat32Array=PackedFloat32Array(hazard.reach)
		for j in 5:
			var heading:int=randi()%96;var angle:float=(float(heading)+.5)/96.0*TAU
			if radius+.55>reach[heading]:continue
			var direction:=Vector3(sin(angle),0,cos(angle))
			_drop(Vector3(hazard.pos)+direction*(radius+.55*.6)+Vector3.UP*.1,direction*2.5+Vector3.UP*randf_range(2.4,4),color,.12,.6)

func _actor_effects(actor, dt: float) -> void:
	var p: Vector3 = actor.global_position
	if not _near(p, 40.0):
		return
	var id: int = actor.get_instance_id()
	if not _actor_state.has(id):
		_actor_state[id] = {"sub": false, "form": "kid", "emerge": -100.0, "wake": 0.0, "bubble": 0.0, "climb": 0.0, "drip": 0.0, "spark": 0.0, "swim_yaw": 0.0, "dodging": false, "laser": 0.0}
	var state: Dictionary = _actor_state[id]
	var col: Color = _color(actor)
	var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	var direction: Vector3 = Vector3(actor.velocity.x, 0, actor.velocity.z).normalized() if speed > 0.01 else Vector3(sin(actor.rotation.y), 0, cos(actor.rotation.y))
	var sub: bool = actor.submerged or actor.climbing
	if sub and not bool(state["sub"]):
		_dive(p, col, speed)
	elif not sub and bool(state["sub"]):
		burst(p, Vector3.UP, col, 8, 2.7, 0.032, 0.65)
		_ripple(p, .007, .14, 1.3, .75)
		state["emerge"] = time
	state["sub"] = sub
	if actor.form == "kid" and actor.is_grounded() and actor.ground_team >= 0 and actor.ground_team != actor.team_id and _near(p,22):
		state["sizzle"] = float(state.get("sizzle", 0.0)) + dt
		if float(state["sizzle"]) > .11:
			state["sizzle"] = 0.0
			var enemy_color: Color = _color(null, 1 - actor.team_id)
			_enemy_ink_sizzle(p,enemy_color)
	if actor.submerged:
		state["wake"] += dt
		if float(state["wake"]) >= 0.05:
			state["wake"] = 0.0
			var k: float = minf(1.0, speed / 11.8)
			for i in range(floori((0.5 + 3.0 * k * k) * quality + randf())):
				var right := Vector3(direction.z, 0, -direction.x)
				_drop(p - direction * 0.34 + Vector3.UP * 0.05, -direction * speed * randf_range(0.06, 0.16) + Vector3.UP * (randf_range(1.5, 2.8) + 1.5 * k) + right * randf_range(-0.8, 0.8), col, randf_range(0.016, 0.034) + 0.012 * k, 0.6, 1, 1.7)
			if randf() < 0.28 * quality + 0.08:
				_bubbles(p - direction * 0.5, col, 1)
		if speed < 2.0:
			state["bubble"] += dt
			if float(state["bubble"]) > 0.35:
				state["bubble"] = 0.0
				_bubbles(p, col, 1)
		var yaw: float = atan2(direction.x, direction.z)
		var rate: float = wrapf(yaw - float(state["swim_yaw"]), -PI, PI) / maxf(dt, 0.001)
		if speed > 4.5 and absf(rate) > 3.2 and randf() < dt * 22.0:
			var outward := Vector3(direction.z, 0, -direction.x) * (-1 if rate > 0 else 1)
			burst(p + outward * 0.18, (outward + Vector3.UP).normalized(), col, 3, 3, 0.035, 0.3)
		state["swim_yaw"] = yaw
	if actor.climbing:
		state["climb"] += dt
		if float(state["climb"]) > 0.07:
			state["climb"] = 0.0
			_climb_drip(p+Vector3.UP*.3,actor.wall_normal,col)
	var hurt: float = 1.0 - actor.hp / 100.0
	state["drip"] += dt * (hurt * 7.0 + (26.0 * (1.0 - (time - float(state["emerge"])) / 0.5) if time - float(state["emerge"]) < 0.5 else 0.0))
	while float(state["drip"]) >= 1.0:
		state["drip"] -= 1.0
		var angle: float = randf() * TAU
		var enemy_col: Color = _color(null, 1 - actor.team_id) if hurt > 0.08 else col
		_drop(p + Vector3(cos(angle) * 0.18, randf_range(0.35, 1.1), sin(angle) * 0.18), Vector3(randf_range(-0.25, 0.25), -0.4, randf_range(-0.25, 0.25)), enemy_col, 0.03 + hurt * 0.02, 1.6)
	if actor.special_fraction() >= 1.0:
		state["spark"] += dt * (12.0 if actor.is_local else 9.0)
		while float(state["spark"]) >= 1:
			state["spark"] -= 1
			var angle: float = randf() * TAU
			glows.sprite(p + Vector3(cos(angle) * 0.5, randf_range(0.2, 1.55 if actor.form == "kid" else 0.55), sin(angle) * 0.5), Vector3(-sin(angle) * 0.6, 0.6, cos(angle) * 0.6), _bright(col.lerp(Color.WHITE, 0.35), 2.4), 0.3, 0.07, 0.6, 1, 11.5, 0.5, 0, 0.08, 3)
	var muzzle_pos: Vector3 = actor.avatar.call("get_muzzle") if actor.avatar and actor.avatar.has_method("get_muzzle") else p + Vector3.UP * 0.92 + actor.aim_dir * 0.45
	if actor.charge > 0.0 and actor.form == "kid":
		_charge_effects(actor, muzzle_pos, col, dt, state)
	if actor.rolling and speed > 0.8:
		var k: float = minf(speed / 4.4, 1.0)
		for i in range(floori(30.0 * k * quality * dt + randf())):
			var off: float = randf_range(-0.95, 0.95)
			var right := Vector3(direction.z, 0, -direction.x)
			_drop(p + direction * 0.85 + right * off + Vector3.UP * 0.1, direction * randf_range(1.6, 3.8) * k + right * signf(off) * 0.7 + Vector3.UP * randf_range(1.4, 3.2), col, randf_range(0.025, 0.055), 1, 1, 1, randf() < 0.3)
	var dodge: float = float(actor.weapon_state.get("dodge", 0.0))
	if dodge > 0.0:
		state["dodging"] = true
		var dir: Vector3 = actor.weapon_state.get("roll_dir", direction)
		for i in range(floori((10.0 + 46.0 * dodge / 0.3) * dt * maxf(0.5, quality) + randf())):
			_drop(p + dir * 0.3 + Vector3.UP * 0.05, dir * randf_range(3, 6) + Vector3.UP * randf_range(0.5, 1.6), col, randf_range(0.011, 0.025), 0.55, 1, 1.7)
	elif bool(state["dodging"]):
		state["dodging"] = false
		burst(p, (direction * 0.7 + Vector3.UP).normalized(), col, 9, 2.5, 0.036)
	if actor.special_active == "slam":
		if actor._special_phase == "hang":
			_glow(p + Vector3.UP * 0.8, _bright(col.lerp(Color.WHITE, 0.25), 2.6), 1.1, 1.1, maxf(0.03, dt * 1.6), 0.8, 2)
		elif actor._special_phase == "fall":
			for i in range(maxi(1, roundi(3.0 * quality))):
				_drop(p + _sphere() * 0.5 + Vector3.UP, Vector3.DOWN * randf_range(14, 18), col.lerp(Color.WHITE, 0.45), 0.03, 0.14, 0, 3.4)
	if not actor.super_jump_state.is_empty():
		_superjump_effects(actor, p, col, dt)

func _charge_effects(actor, p: Vector3, col: Color, dt: float, state: Dictionary) -> void:
	var k: float = actor.charge
	var size: float = (0.07 + 0.2 * k) * (0.85 + 0.15 * sin(time * 40.0))
	_glow(p, _bright(col.lerp(Color.WHITE, 0.2 + 0.4 * k), (1.5 + 2.5 * k)), size, size, maxf(0.03, dt * 1.6), 1, 1 + 3 * k)
	if actor.weapon_id == "charger":
		var reach: float = lerpf(11, 27, k)
		var hit: Dictionary = game.call("cast", p, p + actor.aim_dir * reach, [actor.get_rid()])
		var end: Vector3 = hit.get("position", p + actor.aim_dir * reach)
		beams.line(p, end, col, 0.012 + k * 0.012, maxf(0.03, dt * 1.6), k, true)
		if not hit.is_empty():
			_glow(end + hit["normal"] * 0.03, _bright(col.lerp(Color.WHITE, 0.35), (2 + 2 * k)), 0.08 + 0.1 * k, 0.08 + 0.1 * k, maxf(0.03, dt * 1.6), 1, 11 + 2 * k)
		for i in range(floori((10 + 36 * k) * dt * maxf(0.5, quality) + randf())):
			var offset: Vector3 = _sphere() * randf_range(0.3, 0.55)
			_glow(p + offset, _bright(col.lerp(Color.WHITE, 0.5), 2.2), 0.05, 0.02, 0.17, 1, 1, -offset / 0.17)
	elif actor.weapon_id == "splatling":
		var streaming: bool = float(actor.weapon_state.get("burst", 0.0)) > 0
		var basis: Basis = _basis(actor.aim_dir)
		var amount: float = 30.0 if streaming else 3.0 + 38.0 * k * k
		for i in range(floori(amount * dt * maxf(0.5, quality) + randf())):
			var angle: float = randf() * TAU
			var radial: Vector3 = basis.x * cos(angle) + basis.y * sin(angle)
			var tangent: Vector3 = -basis.x * sin(angle) + basis.y * cos(angle)
			var speed: float = (1.2 + 3.6 * k) * randf_range(0.7, 1.3)
			_drop(p - actor.aim_dir * randf_range(0.06, 0.22) + radial * 0.065, tangent * speed + radial * speed * 0.35 + actor.aim_dir * (randf_range(2, 4) if streaming else 0.5) + Vector3.UP * 0.5, col, randf_range(0.011, 0.024) + 0.008 * k, 0.75, 1, 1.5)

func _superjump_effects(actor, p: Vector3, col: Color, dt: float) -> void:
	var state: Dictionary = actor.super_jump_state
	var target: Vector3 = state.get("to", p)
	if state["phase"] == "charge":
		var k: float = clampf(float(state["time"]) / 0.75, 0, 1)
		for i in range(floori((14 + 24 * k) * dt * maxf(0.5, quality) + randf())):
			var angle: float = randf() * TAU
			_drop(p + Vector3(cos(angle) * 0.6, 0.05, sin(angle) * 0.6), Vector3(-sin(angle) * 1.8, randf_range(2.5, 5.5), cos(angle) * 1.8), col, randf_range(0.025, 0.05), 0.7, 0.8, 1.3)
		_glow(p + Vector3.UP * 0.45, _bright(col.lerp(Color.WHITE, 0.2), (1.4 + 2 * k)), 0.7 + 0.5 * k, 0.7 + 0.5 * k, maxf(0.03, dt * 1.6), 0.7, 2 * k)
		var destination = state.get("target")
		target = destination.global_position if destination is Node3D and is_instance_valid(destination) else (destination if destination is Vector3 else p)
	else:
		for i in range(maxi(1, roundi(2.0 * quality))):
			_drop(p + _sphere() * 0.15, actor.velocity * 0.15 + _sphere() * 0.5, col, randf_range(0.03, 0.065), 1.1, 1, 1.4)
		_glow(p, _bright(col.lerp(Color.WHITE, 0.2), 2.2), 0.55, 0.3, 0.16, 0.9, 1.5)
	_ring(target, Vector3.UP, col, 1.5, maxf(0.05, dt * 2), 0.6)
	beams.line(target, target + Vector3.UP * 9, _bright(col, 1.5), 0.18, maxf(0.05, dt * 2), 0.2, true)

func _projectile_effects(projectiles, dt: float) -> void:
	var budget: int = 48
	for bullet in projectiles.bullets:
		var p: Vector3 = bullet["pos"]
		var velocity: Vector3 = bullet["velocity"]
		var col: Color = _color(bullet.get("owner"), int(bullet.get("team", 0)))
		if bullet["kind"] not in ["bomb","storm_pod"]:
			var age:float=float(bullet.get("age",0))
			# Source hooks reset a recycled round, then advance/reset distance even
			# while too young, delayed, distant or beyond the shared frame budget.
			if not bullet.has("fx_age") or age<float(bullet.fx_age):bullet.fx_distance=0.0
			bullet.fx_age=age
			bullet.fx_distance=float(bullet.get("fx_distance",0))+velocity.length()*dt
			var slosh:bool=bullet["kind"]=="slosher"
			var step:float=.8
			if bullet["kind"]=="blaster":step=.55
			elif bullet["kind"]=="flick":step=1.1
			elif slosh:step=.45 if bool(bullet.get("head",false)) else 1.0
			if float(bullet.fx_distance)>=step:
				bullet.fx_distance=0.0
				if budget>0 and age>.03 and age>float(bullet.get("delay",-1)) and _near(p,30):
					budget-=1
					if slosh:_slosh_trail(p,velocity,col,bool(bullet.get("head",false)))
					else:_shot_trail(p,velocity,col,bullet["kind"]=="blaster")
		if bullet["kind"] == "bomb" and float(bullet.get("fuse", -1)) >= 0:
			var ground: Dictionary = game.call("cast", p, p - Vector3.UP * 4, [])
			if not ground.is_empty() and randf() < dt * 5:
				_ring(ground["position"], ground["normal"], col, 3.1, 0.35, 0.7)
	for storm in projectiles.storms:
		if not _near(storm["pos"], 60):
			continue
		var col: Color = _color(storm.get("owner"))
		var cloud_radius:float=3.4*float(storm.get("scale",1.0))
		var fade:float=clampf(float(storm.life)/.6,0,1)
		if float(storm.life)>.3:
			for i in floori(cloud_radius*cloud_radius*8.5*quality*dt+randf()):
				var angle:float=randf()*TAU
				var radius:float=sqrt(randf())*cloud_radius*.92
				_drop(storm.pos+Vector3(cos(angle)*radius,-.25-randf()*.4,sin(angle)*radius),Vector3(.4,-randf_range(15,20),.15),col,randf_range(.03,.048),1.4,1,3.2)
		if float(storm.get("age",0))>.35 and fade>.3:
			for i in floori(pow(3.4*clampf(float(storm.get("scale",1)),.3,1),2)*3.2*quality*dt+randf()):
				var angle:float=randf()*TAU
				var radius:float=sqrt(randf())*cloud_radius*.95
				_drop(storm.pos+Vector3(cos(angle)*radius,randf_range(-.9,-.4),sin(angle)*radius),Vector3(.35,-randf_range(19,23),.12),col.lerp(Color.WHITE,.35),randf_range(.022,.034),1,1,5.5)
		storm.puddle_time=float(storm.get("puddle_time",0))+dt*16*fade
		while float(storm.puddle_time)>=1.0:
			storm.puddle_time-=1.0
			var angle:float=randf()*TAU
			var radius:float=sqrt(randf())*3.4*.95
			var origin:Vector3=storm.pos+Vector3(cos(angle)*radius,-.6,sin(angle)*radius)
			var hit:Dictionary=game.call("cast",origin,origin-Vector3.UP*14,[])
			if not hit.is_empty():
				_ripple(hit.position+hit.normal*.01,randf_range(.004,.007),.09,.8,.5)
				if randf()<.35:_crown(hit.position+hit.normal*.01,hit.normal,col,2,1.4,.02)
		storm.flash_time=float(storm.get("flash_time",.5))-dt
		if float(storm.flash_time)<=0:
			storm.flash_time=randf_range(.5,1.7)
			_glow(storm.pos+Vector3(randf_range(-1.7,1.7),randf_range(-.24,.56),randf_range(-1.7,1.7)),_bright(col.lerp(Color.WHITE,.5),2.5),1.36,2.38,.12,1,1)
