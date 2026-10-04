class_name InkCameraRig
extends Node3D

# Direct port of src/game/cameraRig.js. Input stays in the match controller;
# physical actors never inherit the visual spring or diorama camera transform.
class Spring:
	extends RefCounted
	var x: float = 0.0
	var v: float = 0.0
	func _init(initial: float = 0.0) -> void:x=initial
	func reset(value: float) -> void:
		x=value
		v=0.0
	func step(target: float,omega: float,dt: float) -> float:
		var d: float = x-target
		var e: float = exp(-omega*dt)
		var k: float = (v+omega*d)*dt
		x=target+(d+k)*e
		v=(v-omega*k)*e
		return x
	func step_damped(target: float,omega: float,zeta: float,dt: float) -> float:
		var n: int = maxi(1,ceili(omega*dt/.12))
		var h: float = dt/n
		for i in n:
			v+=(-omega*omega*(x-target)-2*zeta*omega*v)*h
			x+=v*h
		return x

# The production map renders the current scene. The user requested a strictly
# vertical view; preserve the original crane/lens timing without cursor tilt.
const DIO_PITCH: float = PI*.5
const DIO_FOV: float = 30.0
var game: Node
var camera: Camera3D
var aim_camera: Camera3D
var mode: String = "orbit"
var yaw: float = 0.0
var pitch: float = -.1
var pivot: Vector3 = Vector3.ZERO
var pivot_y: float = 0.0
var dist: float = 4.5
var cur_dist: float = 4.5
var want_dist: float = 4.5
var fov_kick: float = 0.0
var trauma: float = 0.0
var shake_scale: float = 1.0
var target: Node3D
var base_fov: float = 82.0
var zoom: float = 0.0
var time: float = 0.0
var kick: float = 0.0
var shoulder: float = 0.0
var map_open: bool = false
var map_k: float = 0.0
var dio_look: Vector2 = Vector2.ZERO
var dio_flip: bool = false
var spectate_time: float = 0.0
var _look_target: Vector3 = Vector3.ZERO
var shake_seed: float = randf()*100.0
var sx := Spring.new()
var sy := Spring.new()
var sz := Spring.new()
var boom := Spring.new(4.5)
var hgt := Spring.new(1.85)
var dip := Spring.new()
var side := Spring.new()
var lens_lift := Spring.new()
var recoil_spring := Spring.new()
var _last_y: float = NAN
var _vertical_velocity: float = 0.0
var _takeoff_y: float = 0.0
var _land_seen: float = 99.0
var _jump_was_flight: bool = false
var _jump_land_time: float = 99.0
var _trauma_in: float = 0.0
var _prev_mode: String = "orbit"
var _prev_target: Node3D
var _blend: Dictionary = {}
var _orbit: Dictionary = {"center":Vector3.ZERO,"radius":34.0,"height":17.0,"speed":.05,"phase":0.0}
var _path: Dictionary = {}
var _spectate: Dictionary = {}
var _overview_springs: Array[Spring] = []
var _overview_fresh: bool = false
var _rays: Array[Vector3] = []
var _fit_stage_id: int = -1
var _fit_aspect: float = 0.0
var _dio_distance: float = 150.0
var _dio_z_shift: float = 0.0
var _dio_yaw: float = 0.0
var _dio_pitch: float = 0.0
var _dio_target: Vector3 = Vector3.ZERO
var _dio_transform: Transform3D = Transform3D.IDENTITY

func configure(controller: Node,render_camera: Camera3D) -> void:
	game=controller
	camera=render_camera
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	if aim_camera == null:
		aim_camera=Camera3D.new()
		aim_camera.name="OriginalGameplayAim"
		aim_camera.current=false
		aim_camera.keep_aspect=Camera3D.KEEP_HEIGHT
		add_child(aim_camera)
		camera.make_current()
	_rays=[Vector3(0,0,1)]
	for i in 6:
		var angle: float = float(i)/6.0*TAU
		_rays.append(Vector3(cos(angle)*.5,sin(angle)*.5,.75))
	for i in 8:
		var angle: float = float(i)/8.0*TAU+.39
		_rays.append(Vector3(cos(angle),sin(angle),.4))
	aim_camera.global_transform=camera.global_transform
	aim_camera.fov=camera.fov
	aim_camera.near=camera.near
	aim_camera.far=camera.far

static func ease_in_out(value: float) -> float:
	return 4.0*value*value*value if value<.5 else 1.0-pow(-2.0*value+2.0,3.0)/2.0

static func noise(t: float,phase: float) -> float:
	return sin(t+phase)*.62+sin(t*1.87+phase*1.7)*.38

static func damp(value: float,target_value: float,speed: float,dt: float) -> float:
	return lerpf(value,target_value,1.0-exp(-speed*dt))

func forward() -> Vector3:
	return Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))

func recoil(amount: float) -> void:
	recoil_spring.v=minf(recoil_spring.v+amount*55.0,3.0)

func add_shake(amount: float,position_world = null) -> void:
	var value: float = amount
	if position_world is Vector3 and is_instance_valid(camera):
		value*=clampf(1.0-(camera.global_position.distance_to(position_world)-4.0)/22.0,0.0,1.0)
	if value>0.0:
		_trauma_in=minf(1.0-trauma,_trauma_in+value*.75)

func follow(actor: Node3D,snap: bool = false) -> void:
	mode="follow"
	target=actor
	if not is_instance_valid(actor):return
	dio_flip=int(actor.get("team_id"))==1
	if snap:
		if is_instance_valid(game) and str(game.get("state"))=="menu":
			yaw=actor.rotation.y
			pitch=-.28
		var p: Vector3 = _follow_position(actor)
		var height: float = 1.3 if str(actor.get("form"))=="squid" else 1.85
		sx.reset(p.x);sy.reset(p.y+height);sz.reset(p.z)
		pivot=Vector3(p.x,p.y+height,p.z);pivot_y=pivot.y
		hgt.reset(height);boom.reset(dist);cur_dist=dist;want_dist=dist
		dip.reset(0);side.reset(0);lens_lift.reset(0);recoil_spring.reset(0)
		_last_y=NAN;_takeoff_y=p.y;_vertical_velocity=0
		_land_seen=float(actor.get("land_time")) if actor.get("land_time")!=null else 99.0

func orbit(center: Vector3,radius: float,height: float,speed: float = .05,phase: float = 0.0) -> void:
	mode="orbit"
	_orbit={"center":center,"radius":radius,"height":height,"speed":speed,"phase":phase}

func overview() -> void:
	mode="overview"

func cinematic(from: Vector3,to: Vector3,look_from: Vector3,look_to: Vector3,duration: float,on_done: Callable = Callable()) -> void:
	mode="path"
	_path={"from":from,"to":to,"look_from":look_from,"look_to":look_to,"t":0.0,"duration":maxf(.001,duration),"on_done":on_done}

func intro(actor: Node3D = null,boss: Node3D = null) -> void:
	var player: Node3D = actor if is_instance_valid(actor) else game.get("local_player") as Node3D
	var stage: Node = game.get("stage") as Node
	if not is_instance_valid(stage) or not is_instance_valid(player):return
	target=player
	var team: int = int(player.get("team_id"))
	var layout: Dictionary = stage.get("layout")
	var pad: Vector3 = _vec3(layout.spawnPads[team])
	var sign_team: float = 1.0 if team==0 else -1.0
	yaw=0.0 if team==0 else PI;pitch=-.12;dio_flip=team==1
	if is_instance_valid(boss):
		_boss_intro(pad,boss)
		return
	var source: Dictionary = layout.get("intro",{})
	var from: Vector3 = _vec3(source.get("from",[18,26,30]))*Vector3(sign_team,1,sign_team)
	var to := Vector3(pad.x,pad.y+2.6,pad.z-float(source.get("toBack",5.2))*sign_team)
	var start_look: Vector3 = _vec3(source.get("lookFrom",[0,0,10]))*Vector3(sign_team,1,sign_team)
	var end_look := Vector3(pad.x,pad.y+1.6,pad.z+6.0*sign_team)
	cinematic(from,to,start_look,end_look,3.6)

func _boss_intro(pad: Vector3,boss: Node3D) -> void:
	var p: Vector3 = boss.global_position
	var fwd := Vector3(sin(boss.rotation.y),0,cos(boss.rotation.y))
	var lateral := Vector3(fwd.z,0,-fwd.x)
	var reveal: Vector3 = p+fwd*15.0+lateral*5.0+Vector3.UP*4.6
	var push: Vector3 = p+fwd*12.0+lateral*3.2+Vector3.UP*3.4
	var behind := Vector3(pad.x,pad.y+2.6,pad.z-5.2)
	var chest: Vector3 = p+Vector3.UP*2.6
	var head: Vector3 = p+Vector3.UP*3.4
	var high := Vector3(pad.x+6.0,pad.y+17.0,pad.z+4.0)
	var mid := Vector3((pad.x+p.x)*.5,0,(pad.z+p.z)*.5)
	cinematic(high,reveal,mid,chest,1.9,func():
		if str(game.get("state"))!="intro":return
		cinematic(reveal,push,chest,head,3.0,func():
			if str(game.get("state"))!="intro":return
			cinematic(push,behind,head,Vector3(pad.x,pad.y+1.6,pad.z+6.0),2.1)))

func spectate(victim: Node3D,killer: Node3D = null) -> void:
	mode="spectate"
	var position_world:Vector3=victim.call("visual_position") if victim.has_method("visual_position") else victim.global_position
	_spectate={"pos":position_world,"from":position_world,"actor":killer}
	spectate_time=0.0
	_look_target=position_world

func set_map(open: bool,cursor: Vector2 = Vector2.ZERO) -> void:
	map_open=open and is_instance_valid(game) and str(game.get("state"))=="playing" and game.get("paused")!=true
	dio_look=cursor.limit_length(1.0)

func on_event(kind: String,data: Dictionary) -> void:
	match kind:
		"recoil":recoil(float(data.get("amount",0.0)))
		"shake":add_shake(float(data.get("amount",0.0)),data.get("pos"))
		"splatted":
			var victim = data.get("victim")
			if victim==target and victim is Node3D:
				spectate(victim,data.get("attacker") as Node3D)
		"respawn":
			var actor = data.get("actor")
			if actor==target and actor is Node3D:
				follow(actor,true)
				yaw=actor.rotation.y;pitch=-.12
				if bool(actor.get("is_local")):
					game.set("_yaw",yaw);game.set("_pitch",pitch)

func boss_finish(boss:Node3D) -> void:
	if not is_instance_valid(boss):return
	var center:Vector3=boss.global_position+Vector3.UP*2.2
	var pos:Vector3=camera.global_position
	orbit(center,15.0,5.5,.09,atan2(pos.x-center.x,pos.z-center.z))

func _start_blend(duration: float) -> void:
	_blend={"t":0.0,"duration":duration,"position":camera.global_position,"quaternion":camera.global_basis.get_rotation_quaternion(),"fov":camera.fov,"active":true}

func _mode_changed(previous: String,next: String) -> void:
	spectate_time=0.0
	if next=="overview":_overview_fresh=true
	if str(game.get("state"))=="menu" or previous.is_empty():return
	var duration: float = 0.0
	if next=="spectate":duration=.55
	elif next=="follow" and previous=="spectate":duration=.7
	elif next=="follow" and previous=="path":duration=.6
	elif next=="overview":duration=1.2
	elif next=="follow" and previous!="follow":duration=.45
	if duration>0.0:_start_blend(duration)

func update(dt: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(game):return
	time+=dt
	if not pivot.is_finite() or not is_finite(sx.x+sy.x+sz.x+boom.x+dip.x+recoil_spring.x+trauma):
		pivot=Vector3(0,2,0);pivot_y=2;cur_dist=dist
		sx.reset(0);sy.reset(2);sz.reset(0);boom.reset(dist);dip.reset(0);recoil_spring.reset(0);trauma=0;_trauma_in=0
	if mode!=_prev_mode or (mode=="follow" and target!=_prev_target):
		if mode!=_prev_mode:_mode_changed(_prev_mode,mode)
		_prev_mode=mode;_prev_target=target
	var settings: Dictionary = game.get("settings")
	base_fov=float(settings.get("fov",82.0))
	if mode=="follow" and is_instance_valid(target):
		if bool(target.get("is_local")):
			yaw=float(game.get("_yaw"));pitch=float(game.get("_pitch"))
		elif str(game.get("state"))=="menu":
			yaw=lerp_angle(yaw,target.rotation.y,1.0-exp(-2.0*dt))
		_follow(dt)
	elif mode=="spectate" and not _spectate.is_empty():_update_spectate(dt)
	elif mode=="path" and not _path.is_empty():_update_path(dt)
	elif mode=="orbit":_update_orbit(dt)
	elif mode=="overview":_update_overview(dt)
	var fov: float = rad_to_deg(2.0*atan(tan(deg_to_rad(base_fov)*.5)/(16.0/9.0)))+(fov_kick-zoom)*.8
	if bool(_blend.get("active",false)):
		_blend.t+=dt
		var amount: float = ease_in_out(clampf(float(_blend.t)/float(_blend.duration),0,1))
		camera.global_position=Vector3(_blend.position).lerp(camera.global_position,amount)
		var quat: Quaternion = (_blend.quaternion as Quaternion).slerp(camera.global_basis.get_rotation_quaternion(),amount)
		camera.global_basis=Basis(quat)
		fov=lerpf(float(_blend.fov),fov,amount)
		if amount>=1.0:_blend.active=false
	if _trauma_in>0.0:
		var amount: float = minf(_trauma_in,dt*14.0)
		trauma=minf(1.0,trauma+amount);_trauma_in-=amount
	else:trauma=maxf(0.0,trauma-dt*2.1)
	var intensity: float = trauma*trauma*float(settings.get("cameraShake",1.0))*shake_scale
	if intensity>.0005:
		var t: float = time*13.0
		camera.rotate_object_local(Vector3.RIGHT,noise(t,shake_seed)*.014*intensity)
		camera.rotate_object_local(Vector3.UP,noise(t*1.13,shake_seed+3.1)*.01*intensity)
		camera.rotate_object_local(Vector3.BACK,noise(t*.87,shake_seed+7.7)*.008*intensity)
		camera.global_position+=camera.global_basis.x*noise(t*1.07,shake_seed+11.0)*.025*intensity
		camera.global_position.y+=noise(t*.93,shake_seed+19.0)*.025*intensity
	aim_camera.global_transform=camera.global_transform
	aim_camera.fov=fov;aim_camera.near=camera.near;aim_camera.far=camera.far
	if str(game.get("state"))!="playing" or game.get("paused")==true:map_open=false
	var desired_map: float = 1.0 if map_open and mode in ["follow","spectate"] else 0.0
	if desired_map>map_k:map_k=minf(1.0,map_k+dt/.42)
	elif desired_map<map_k:map_k=maxf(0.0,map_k-dt/.34)
	if map_k>.0001:
		_diorama(dt)
		var amount: float = ease_in_out(map_k)
		var rise: float = amount+.35*amount*(1.0-amount)
		var game_look: Vector3 = aim_camera.global_position-aim_camera.global_basis.z*12.0
		var blended_look: Vector3 = game_look.lerp(_dio_target,amount)
		var start: Vector3 = aim_camera.global_position
		camera.global_position=Vector3(lerpf(start.x,_dio_transform.origin.x,amount),lerpf(start.y,_dio_transform.origin.y,rise),lerpf(start.z,_dio_transform.origin.z,amount))
		var map_up:Vector3=_dio_transform.basis.y
		var up_blend:float=clampf((amount-.75)/.25,0.0,1.0)
		_set_look(blended_look,Vector3.UP.lerp(map_up,up_blend).normalized())
		var q: Quaternion = camera.global_basis.get_rotation_quaternion()
		if amount<.15:q=aim_camera.global_basis.get_rotation_quaternion().slerp(q,amount/.15)
		if amount>.999:q=_dio_transform.basis.get_rotation_quaternion()
		elif amount>.85:q=q.slerp(_dio_transform.basis.get_rotation_quaternion(),(amount-.85)/.15)
		camera.global_basis=Basis(q)
		fov=lerpf(fov,DIO_FOV,amount)
	camera.fov=fov

func _cast(from: Vector3,to: Vector3) -> Dictionary:
	var excluded: Array = [target.get_rid()] if is_instance_valid(target) and target is CollisionObject3D else []
	return game.call("cast",from,to,excluded,1)

func camera_probe(origin: Vector3,back: Vector3,want: float,radius: float = .62,pad: float = .3) -> Dictionary:
	var reference: Vector3 = Vector3.UP if absf(back.y)<=.95 else Vector3.RIGHT
	var lateral: Vector3 = back.cross(reference).normalized()
	var up: Vector3 = lateral.cross(back).normalized()
	var hard: float = want
	var soft: float = want
	var floor_hit: bool = false
	for ray: Vector3 in _rays:
		var start: Vector3 = origin+lateral*ray.x*radius+up*ray.y*radius
		var hit: Dictionary = _cast(start,start+back*(want+pad))
		if hit.is_empty():continue
		var limit: float = maxf(0.0,start.distance_to(hit.position)-pad)
		if ray.z>=1.0 and limit<hard:
			hard=limit;floor_hit=Vector3(hit.normal).y>.6
		soft=minf(soft,limit+(want-limit)*(1.0-ray.z))
	return {"hard":hard,"soft":minf(soft,hard),"floor":floor_hit}

func _follow_position(actor: Node3D) -> Vector3:
	if actor.has_method("presentation_position"):return actor.call("presentation_position")
	return actor.call("visual_position") if actor.has_method("visual_position") else actor.global_position

func _follow(dt: float) -> void:
	var p: Vector3 = _follow_position(target)
	var velocity: Vector3 = target.get("velocity")
	var squid: bool = str(target.get("form"))=="squid"
	var swim: bool = bool(target.get("submerged")) or bool(target.get("climbing"))
	var grounded: bool = bool(target.call("is_grounded")) if target.has_method("is_grounded") else (target is CharacterBody3D and (target as CharacterBody3D).is_on_floor())
	var climbing: bool = bool(target.get("climbing"))
	var jump: Dictionary = target.get("super_jump_state")
	var flying: bool = not jump.is_empty() and str(jump.get("phase"))=="flight"
	var special: bool = not str(target.get("special_active")).is_empty()
	var height: float = hgt.step(1.15 if swim else (1.3 if squid else 1.85),11.0,dt)
	var omega_h: float = 20.0 if flying else 30.0
	var lead: float = .72*2.0/omega_h
	var fwd: Vector3 = forward()
	var right := Vector3(-cos(yaw),0,sin(yaw))
	var lateral: float = velocity.dot(right)
	var offset: float = side.step(clampf(lateral*.045,-.32,.32)*(0.0 if flying else 1.0),3.2,dt)
	var y: float = p.y+height
	if absf(sx.x-p.x)+absf(sz.x-p.z)>6.0 or absf(sy.x-y)>6.0:
		sx.reset(p.x);sz.reset(p.z);sy.reset(y);_last_y=NAN;_vertical_velocity=0
	sx.step(p.x+velocity.x*lead+right.x*offset,omega_h,dt)
	sz.step(p.z+velocity.z*lead+right.z*offset,omega_h,dt)
	var fresh: bool = is_nan(_last_y) or dt<=0.0
	var raw: float = 0.0 if fresh else clampf((y-_last_y)/dt,-30,30)
	_last_y=y;_vertical_velocity=0.0 if fresh else damp(_vertical_velocity,raw,30,dt)
	var omega_v: float = 13.0
	var lead_v: float = .5
	if grounded or climbing:_takeoff_y=p.y
	if not grounded and not climbing:
		if flying or special:omega_v=16.0;lead_v=.85
		elif p.y<_takeoff_y-.25:omega_v=15.0;lead_v=.8
		else:omega_v=7.5;lead_v=.25
	sy.step(y+_vertical_velocity*lead_v*2.0/omega_v,omega_v,dt)
	var land_t: float = float(target.get("land_time")) if target.get("land_time")!=null else 99.0
	var land_speed: float = float(target.get("land_speed")) if target.get("land_speed")!=null else 0.0
	if land_t<_land_seen-.000001 and land_speed>4.0:dip.v-=clampf((land_speed-4.0)*.045,0,.45)
	_land_seen=land_t
	pivot=Vector3(sx.x,sy.x+clampf(dip.step_damped(0,13,.82,dt),-.3,.12),sz.x);pivot_y=pivot.y
	var speed: float = Vector2(velocity.x,velocity.z).length()
	if flying:
		var travel: Vector3 = Vector3(jump.to)-Vector3(jump.from)
		if Vector2(travel.x,travel.z).length_squared()>1.0:yaw=lerp_angle(yaw,atan2(travel.x,travel.z),1.0-exp(-3.5*dt))
		var progress: float = clampf(float(jump.get("time",0.0))/float(jump.get("duration",1.15)),0,1)
		pitch=damp(pitch,lerpf(-.3,-.75,clampf((progress-.35)/.5,0,1)),4,dt)
		_jump_was_flight=true
	elif _jump_was_flight:_jump_was_flight=false;_jump_land_time=0
	if _jump_land_time<.45:
		_jump_land_time+=dt
		if pitch<-.2:pitch=damp(pitch,-.16,7,dt)
	if flying or _jump_land_time<.45:
		game.set("_yaw",yaw);game.set("_pitch",pitch)
	var fk: float = clampf((speed-6.0)*1.1,0,7) if swim else (6.0 if flying else (1.2 if not grounded and velocity.y>2.0 else 0.0))
	fov_kick=damp(fov_kick,fk,5,dt)
	var charging: float = float(target.get("charge")) if str(target.get("weapon_id"))=="charger" and bool(target.get("firing")) else 0.0
	zoom=damp(zoom,14.0 if charging>.99 else charging*6.0,8,dt)
	var want: float = (4.1 if squid else dist)-charging*.6
	if swim:want+=clampf((speed-6.0)/6.0,0,1)*.35
	if flying:want+=1.2
	want_dist=damp(want_dist,want,6,dt)
	var probe: Dictionary = camera_probe(pivot,-fwd,want_dist)
	var deep: float = clampf(boom.x-float(probe.hard),0,1)
	boom.step(float(probe.soft),22.0+26.0*deep if float(probe.soft)<boom.x else 3.6,dt)
	if boom.x>float(probe.hard)+1.6:boom.x=float(probe.hard)+1.6;boom.v=minf(boom.v,0)
	if bool(probe.floor) and boom.x>float(probe.hard):boom.x=float(probe.hard);boom.v=minf(boom.v,0)
	if boom.x<.45:boom.x=.45;boom.v=maxf(boom.v,0)
	cur_dist=boom.x
	camera.global_position=pivot-fwd*cur_dist+Vector3.UP*.15
	var stage = game.get("stage")
	var ground_y: float = stage.call("ground_height",camera.global_position.x,camera.global_position.z,camera.global_position.y+.2) if is_instance_valid(stage) and stage.has_method("ground_height") else -INF
	var lift: float = maxf(0,ground_y+.24-camera.global_position.y) if is_finite(ground_y) and ground_y<pivot.y-.6 else 0.0
	camera.global_position.y+=lens_lift.step(lift,34.0 if lift>lens_lift.x else 7.0,dt)
	var close: float = clampf((2.8-cur_dist)/1.8,0,1)
	var shift: float = .55*close*close*(3.0-2.0*close)
	if shift>.01:
		var obstruction: Dictionary = _cast(camera.global_position,camera.global_position+right*(shift+.25))
		if not obstruction.is_empty():shift=maxf(0,camera.global_position.distance_to(obstruction.position)-.25)
	shoulder=damp(shoulder,shift,8,dt)
	if shoulder>.001:camera.global_position+=right*shoulder
	kick=clampf(recoil_spring.step(0,22,dt),-.01,.035)
	_set_look(pivot+fwd*10.0+Vector3.UP*.15+right*shoulder)
	if absf(kick)>.000001:camera.rotate_object_local(Vector3.RIGHT,kick)

func _set_look(point: Vector3,up:Vector3=Vector3.UP) -> void:
	if camera.global_position.distance_squared_to(point)>.000001:
		var direction:Vector3=(point-camera.global_position).normalized()
		if absf(direction.dot(up))>.9999:up=Vector3.BACK if absf(direction.z)<.999 else Vector3.RIGHT
		camera.look_at(point,up)

func _update_spectate(dt: float) -> void:
	spectate_time+=dt
	var actor = _spectate.get("actor")
	var killer: Node3D = actor if is_instance_valid(actor) and bool(actor.get("alive")) else null
	var focus: Vector3 = _spectate.pos if spectate_time<.8 or killer==null else (killer.call("visual_position") if killer.has_method("visual_position") else killer.global_position)
	_look_target=_look_target.lerp(focus+Vector3.UP*1.1,1.0-exp(-(7.0 if spectate_time<.8 else 4.5)*dt))
	var direction: Vector3 = Vector3(_spectate.from)-_look_target
	direction.y=0
	if direction.length_squared()<.01:direction=Vector3.BACK
	direction=direction.normalized()
	var angle: float = atan2(direction.x,direction.z)+minf(spectate_time,6.0)*.07
	var radius: float = 4.2 if spectate_time<.8 else 5.5
	var position: Vector3 = _look_target+Vector3(sin(angle)*radius,2.4,cos(angle)*radius)
	var obstruction: Dictionary = _cast(_look_target,position)
	if not obstruction.is_empty():position=Vector3(obstruction.position).lerp(_look_target,.12)
	camera.global_position=camera.global_position.lerp(position,1.0-exp(-3.0*dt))
	_set_look(_look_target)
	fov_kick=damp(fov_kick,-6,3,dt);zoom=damp(zoom,0,6,dt)

func _update_path(dt: float) -> void:
	_path.t+=dt
	var progress: float = clampf(float(_path.t)/float(_path.duration),0,1)
	var amount: float = ease_in_out(progress)
	camera.global_position=Vector3(_path.from).lerp(Vector3(_path.to),amount)+Vector3.UP*sin(amount*PI)*1.5
	_set_look(Vector3(_path.look_from).lerp(Vector3(_path.look_to),amount))
	fov_kick=0;zoom=0
	var callback: Callable = _path.on_done
	if progress>=1.0 and callback.is_valid():
		_path.on_done=Callable()
		callback.call()

func _update_orbit(dt: float) -> void:
	var angle: float = float(_orbit.phase)+time*float(_orbit.speed)
	var center: Vector3 = _orbit.center
	var position: Vector3 = center+Vector3(sin(angle)*float(_orbit.radius),float(_orbit.height)+sin(time*.13)*1.2,cos(angle)*float(_orbit.radius))
	camera.global_position=camera.global_position.lerp(position,1.0-exp(-2.0*dt))
	_set_look(center)
	fov_kick=0;zoom=0

func _update_overview(dt: float) -> void:
	if _overview_springs.is_empty() or _overview_fresh:
		_overview_springs=[Spring.new(camera.global_position.x),Spring.new(camera.global_position.y),Spring.new(camera.global_position.z)]
		_overview_fresh=false
	camera.global_position=Vector3(_overview_springs[0].step(0,1.9,dt),_overview_springs[1].step(62,1.9,dt),_overview_springs[2].step(-18,1.9,dt))
	_set_look(Vector3(0,0,3))
	fov_kick=damp(fov_kick,-12,2,dt);zoom=0

func _aspect() -> float:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	return size.x/maxf(1.0,size.y)

static func _vec3(data: Array) -> Vector3:
	return Vector3(float(data[0]),float(data[1]),float(data[2]))

func _dio_pose(distance: float,z_shift: float,bounds: Dictionary,angle: float,angle_pitch: float) -> Transform3D:
	_dio_target=Vector3((float(bounds.minX)+float(bounds.maxX))*.5,0,(float(bounds.minZ)+float(bounds.maxZ))*.5+z_shift)
	if absf(angle_pitch-PI*.5)<.00001:
		var position_vertical:Vector3=_dio_target+Vector3.UP*distance
		var map_up:Vector3=Vector3(sin(angle),0,cos(angle))
		return Transform3D(Basis.IDENTITY,position_vertical).looking_at(_dio_target,map_up)
	var position: Vector3 = _dio_target+Vector3(-sin(angle)*cos(angle_pitch)*distance,sin(angle_pitch)*distance,-cos(angle)*cos(angle_pitch)*distance)
	return Transform3D(Basis.IDENTITY,position).looking_at(_dio_target,Vector3.UP)

func _diorama(dt: float) -> void:
	var stage = game.get("stage")
	if not is_instance_valid(stage):return
	var aspect: float = _aspect()
	var bounds: Dictionary = stage.get("bounds")
	if _fit_stage_id!=stage.get_instance_id() or absf(_fit_aspect-aspect)>.001:
		_fit_stage_id=stage.get_instance_id();_fit_aspect=aspect;_fit_diorama(bounds,aspect)
	_dio_yaw=0.0;_dio_pitch=0.0
	_dio_transform=_dio_pose(_dio_distance,-_dio_z_shift if dio_flip else _dio_z_shift,bounds,PI if dio_flip else 0.0,DIO_PITCH)

func _project_ndc(point: Vector3,pose: Transform3D,aspect: float) -> Vector2:
	var local: Vector3 = pose.affine_inverse()*point
	var extent: float = maxf(.00001,-local.z)*tan(deg_to_rad(DIO_FOV)*.5)
	return Vector2(local.x/(extent*aspect),local.y/extent)

func _fit_diorama(bounds: Dictionary,aspect: float) -> void:
	var points := PackedVector3Array()
	for x: float in [float(bounds.minX),float(bounds.maxX)]:
		for z: float in [float(bounds.minZ),float(bounds.maxZ)]:
			for y: float in [-1.2,6.0]:points.append(Vector3(x,y,z))
	var z_shift: float = 0.0
	var distance: float = 150.0
	for pass_index in 4:
		var low: float = 20.0
		var high: float = 1500.0
		for iteration in 28:
			var middle: float = (low+high)*.5
			var pose: Transform3D = _dio_pose(middle,z_shift,bounds,0,DIO_PITCH)
			var fits: bool = true
			for point: Vector3 in points:
				var p: Vector2 = _project_ndc(point,pose,aspect)
				if p.x<-.92 or p.x>.92 or p.y<-.72 or p.y>.74:
					fits=false;break
			if fits:high=middle
			else:low=middle
		distance=high
		var pose: Transform3D = _dio_pose(distance,z_shift,bounds,0,DIO_PITCH)
		var min_y: float = 9.0
		var max_y: float = -9.0
		for point: Vector3 in points:
			var p: Vector2 = _project_ndc(point,pose,aspect)
			min_y=minf(min_y,p.y);max_y=maxf(max_y,p.y)
		var offset: float = .01-(min_y+max_y)*.5
		z_shift-=offset*distance*tan(deg_to_rad(DIO_FOV)*.5)/sin(DIO_PITCH)
	_dio_distance=distance;_dio_z_shift=z_shift
