class_name InkScreenFx
extends CanvasLayer

## Original screenfx.js composite and sim-clock sequencer, below the native HUD.
const Lens = preload("res://scripts/fx/lens_ink.gd")
const FxColors = preload("res://scripts/fx/ink_fx_colors.gd")
const SEA: Color = Color(.06,.34,.62)
var game: Node
var panel: ColorRect
var material: ShaderMaterial
var lens: InkLens
var s: Dictionary = {}
var quality: float = 1.0
var settings: Dictionary = {}
var time: float = 0.0
var _aspect: float = 16.0 / 9.0
var _local = null
var _camera: Camera3D
var _state: String = "menu"
var _count: int = 99
var _flood_color: Color = Color.WHITE
var _water_flood: bool = false
var _blast_color: Color = Color.WHITE
var _blast_pos: Vector2 = Vector2(.5,.5)
var _punch_pos: Vector2 = Vector2(.5,.5)
var _damage_attacker = null
var _last_land: float = -9.0
var _last_blast: float = -9.0
var _last_blast_point: Vector3 = Vector3.ZERO
var uniforms: Dictionary = {}
var enabled: bool = false
var use_compositor: bool = false

func configure(controller: Node) -> void:
	game=controller
	layer=5
	lens=Lens.new()
	add_child(lens)
	lens.initialize()
	panel=ColorRect.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	material=ShaderMaterial.new()
	material.shader=preload("res://assets/shaders/fx_screen.gdshader")
	panel.material=material
	_set_uniform("tLens",lens.target.get_texture())
	reset()

func reset() -> void:
	s={"speed":0.0,"stretch":0.0,"punch":0.0,"punchV":0.0,"blast":0.0,"blastT":9.0,"chroma":0.0,"edgeInk":0.0,"aura":0.0,"auraPulse":0.0,"heart":0.0,"heartPh":0.0,"hurt":0.0,"urg":0.0,"urgBase":0.0,"swim":0.0,"focus":0.0,"chargePulse":0.0,"shimmer":0.0,"kill":0.0,"flash":0.0,"desat":0.0,"sat":1.0,"satPop":0.0,"flood":0.0,"floodDrip":0.0,"hole":0.0,"floodMode":"","floodT":0.0,"jumpCharge":0.0,"wasJump":false,"stepT":0.0,"rainT":0.0,"emergeT":0.0,"lastForm":"kid","dmgAcc":0.0,"dmgT":0.0,"fullCharge":false}
	_damage_attacker=null
	if lens:lens.clear()
	enabled=false
	if panel:panel.hide()

func set_quality(options: Dictionary, intensity: float) -> void:
	settings=options
	quality=intensity
	if lens:lens.scale_factor=1.0/3.0 if quality>=1.0 else .25
	if material:_set_uniform("TAPS",8 if quality>=1.0 else (6 if quality>=.7 else 5))

func _is_local(actor) -> bool:
	return is_instance_valid(actor) and actor is InkActor and actor.is_local

func _color(team: int) -> Color:
	var colors=game.get("team_colors")
	return FxColors.from_srgb(colors[clampi(team,0,1)]) if colors is Array and colors.size()>=2 else Color.WHITE

func _kick(value: float) -> void:
	s.punchV+=value*22.0

func _screen(point: Vector3) -> Vector2:
	var uv:Vector2=_camera.unproject_position(point)/_camera.get_viewport().get_visible_rect().size
	return Vector2(uv.x,1.0-uv.y)

func on_event(kind: String,data: Dictionary) -> void:
	if not is_instance_valid(game) or str(game.get("state")) not in ["intro","playing","finish"]:return
	_camera=game.get("camera")
	var actor=data.get("actor")
	match kind:
		"damage":
			if not _is_local(data.get("victim")):return
			var amount:float=float(data.get("amount",0))
			if amount<=0:return
			s.dmgAcc+=amount
			_damage_attacker=data.get("attacker",_damage_attacker)
			if float(s.dmgT)<=0:s.dmgT=.06
			var k:float=clampf(amount/60.0,.1,1.0)
			s.chroma=minf(.9,float(s.chroma)+.12+k*.4)
			if amount>=40:_kick(-.005-.008*k)
		"splatted":
			var victim=data.get("victim")
			if _is_local(data.get("attacker")):
				s.kill=1.0
				s.chroma=minf(1.0,float(s.chroma)+.3)
				_kick(.012)
			if not _is_local(victim):return
			var attacker=data.get("attacker")
			_water_flood=str(data.get("cause",""))=="water"
			_flood_color=SEA if _water_flood else _color(attacker.team_id if is_instance_valid(attacker) and attacker is InkActor else 1-victim.team_id)
			s.floodMode="in"
			s.floodT=0.0
			s.hole=0.0
			s.chroma=minf(1.4,float(s.chroma)+.9)
			_kick(-.03)
			if _water_flood:
				for i in range(34):lens.droplet(2,Vector2(randf(),randf_range(.05,1)),randf_range(.01,.034),randf_range(.3,1.2),randf_range(1.8,3.6))
		"respawn":
			if not _is_local(actor):return
			_flood_color=_color(actor.team_id)
			_water_flood=false
			s.flood=1.0
			s.floodMode="reveal"
			s.floodT=0.0
			s.hole=.0001
			s.floodDrip=.05
			s.shimmer=1.0
			lens.clear()
		"superjump":
			if _is_local(actor) and data.get("phase")=="flight":
				s.flash=.5
				s.chroma=minf(1.2,float(s.chroma)+.6)
				_kick(-.04)
		"superjump:land":
			if _is_local(actor):_land(actor)
		"special_activate":
			if _is_local(actor):
				s.auraPulse=1.0
				s.chroma=minf(1.0,float(s.chroma)+.25)
				if data.get("special")=="storm":s.aura=maxf(float(s.aura),.9)
		"explosion":
			_blast(data.get("pos",Vector3.ZERO),1.0 if data.get("kind")=="slam" else .6,_color(int(data.get("team",0))))
		"special:slam":
			_blast(data.get("pos",Vector3.ZERO),1.0,_color(actor.team_id if is_instance_valid(actor) else 0))
			if _is_local(actor):
				s.blast*=.55
				s.chroma*=.7
		"impact:shot":
			var local=game.get("local_player")
			if not _camera or not is_instance_valid(local) or not local.alive or int(data.get("team",0))==local.team_id:return
			var point:Vector3=data.get("pos",Vector3.ZERO)
			var distance:float=_camera.global_position.distance_squared_to(point)
			if distance>2.4*2.4 or _camera.is_position_behind(point):return
			var uv:Vector2=_screen(point).clamp(Vector2(.03,.05),Vector2(.97,.97))
			for i in range(3 if distance<1.2 else 1+randi()%2):
				lens.droplet(0,(uv+Vector2(randf_range(-.06,.06),randf_range(-.06,.06))).clamp(Vector2(.02,.04),Vector2(.98,.97)),randf_range(.008,.02),randf_range(.1,.35),randf_range(.5,1.0))

func _blast(point: Vector3,amount: float,color: Color) -> void:
	if not _camera:return
	if time-_last_blast<.05 and point.distance_to(_last_blast_point)<.8:return
	_last_blast=time
	_last_blast_point=point
	var k:float=amount*clampf(1.0-(_camera.global_position.distance_to(point)-3.0)/24.0,0,1)
	if k<.04:return
	var uv:Vector2=_screen(point)
	if not _camera.is_position_behind(point) and uv.x>-.125 and uv.x<1.125 and uv.y>-.125 and uv.y<1.125:
		_blast_pos=uv
		_punch_pos=uv
		_blast_color=color.lerp(Color.WHITE,.35)
		s.blast=minf(1.2,maxf(float(s.blast),k*1.1))
		s.blastT=0.0
	s.chroma=minf(1.3,float(s.chroma)+k*.9)
	_kick(.02*k)

func _land(actor) -> void:
	if time-_last_land<.3:return
	_last_land=time
	_punch_pos=Vector2(.5,.3)
	_blast_pos=Vector2(.5,.18)
	_blast_color=_color(actor.team_id).lerp(Color.WHITE,.3)
	s.blast=maxf(float(s.blast),.75)
	s.blastT=0.0
	s.chroma=minf(1.3,float(s.chroma)+.7)
	s.flash=maxf(float(s.flash),.35)
	_kick(.045)

func _edge_point(angle: float,inset: float) -> Vector2:
	var direction:=Vector2(cos(angle),sin(angle))
	var distance:float=minf((_aspect*.5)/maxf(.001,absf(direction.x)),.5/maxf(.001,absf(direction.y)))
	var point:=Vector2(_aspect*.5,.5)+direction*distance
	point.x-=signf(direction.x)*inset*(1.0 if absf(direction.x)>.25 else .3)
	point.y-=signf(direction.y)*inset*(1.0 if absf(direction.y)>.25 else .3)
	point.x/=_aspect
	if point.y<.5 and absf(point.x-.5)<.2:
		point.x=.5+(-1.0 if point.x<.5 else 1.0)*randf_range(.22,.3)
	return point.clamp(Vector2(.02,.03),Vector2(.98,.97))

func _damage_splat(amount: float,attacker) -> void:
	var k:float=clampf(amount/70.0,.18,1.2)
	var angle:float=randf()*TAU
	if is_instance_valid(attacker) and attacker is Node3D and _camera:
		var projected:Vector2=(_screen(attacker.global_position+Vector3.UP)-Vector2(.5,.5))*2.0
		var behind:bool=_camera.is_position_behind(attacker.global_position)
		if behind:projected=-projected
		angle=(0.0 if projected.x>=0 else PI)+randf_range(-.35,.35) if not behind and absf(projected.x)<1 and absf(projected.y)<1 else atan2(projected.y,projected.x*_aspect)
	for i in range(2 if k>.7 else 1):
		var a:float=angle+(randf_range(-.7,.7) if i else randf_range(-.18,.18))
		var size:float=(.045+.05*k)*(.6 if i else 1.0)*randf_range(.85,1.15)
		lens.splat(0,_edge_point(a,size*randf_range(.2,.9)),size,6+randi()%4,5+randi()%5,1.5+k*.9)

func _damp(key: String,target: float,speed: float,dt: float) -> void:
	s[key]=lerpf(float(s[key]),target,1.0-exp(-speed*dt))

func _ease_out(value: float) -> float:
	return 1.0-pow(1.0-clampf(value,0,1),3)

func _sim(dt: float,actor,state: String) -> void:
	var alive:bool=is_instance_valid(actor) and actor.alive
	if float(s.dmgT)>0:
		s.dmgT-=dt
		if float(s.dmgT)<=0:
			if float(s.dmgAcc)>0 and alive:_damage_splat(float(s.dmgAcc),_damage_attacker)
			s.dmgAcc=0.0
			_damage_attacker=null
	var hs:float=Vector2(actor.velocity.x,actor.velocity.z).length() if alive else 0.0
	var form:String=actor.form if alive else "kid"
	var swimming:bool=form in ["swim","climb"]
	var speed_target:float=clampf((hs-6.5)/5.3,0,1)*.55 if swimming else 0.0
	var stretch_target:float=clampf((hs-7.0)/4.8,0,1)*.045 if swimming else 0.0
	var sj:Dictionary=actor.super_jump_state if alive else {}
	var flight:bool=sj.get("phase","")=="flight"
	if flight:
		var k:float=clampf(float(sj.get("time",0))/float(sj.get("duration",1.2)),0,1)
		speed_target=.55+.45*absf(cos(k*PI))
		stretch_target=.06*(.4+.6*absf(cos(k*PI)))
	_damp("speed",speed_target,5.0 if speed_target>float(s.speed) else 3.0,dt)
	_damp("stretch",stretch_target,4,dt)
	if bool(s.wasJump) and not flight and alive:_land(actor)
	s.wasJump=flight
	s.jumpCharge=minf(1.0,float(s.jumpCharge)+dt/.75) if sj.get("phase","")=="charge" else maxf(0,float(s.jumpCharge)-dt*3)
	_damp("swim",1.0 if alive and form=="swim" else 0.0,7,dt)
	if alive and s.lastForm=="swim" and form not in ["swim","climb"] and (hs>7 or actor.velocity.y>4) and float(s.emergeT)<=0:
		s.emergeT=.6
		for i in range(2+randi()%3):lens.droplet(1,Vector2(randf_range(.04,.3) if randf()<.5 else randf_range(.7,.96),randf_range(.03,.22)),randf_range(.008,.016),randf_range(.05,.2),randf_range(.45,.8))
	s.emergeT-=dt
	s.lastForm=form
	var enemy:bool=alive and actor.ground_team>=0 and actor.ground_team!=actor.team_id and actor.is_on_floor() and not actor.submerged
	_damp("edgeInk",1.0 if enemy else 0.0,9.0 if enemy else 3.0,dt)
	if enemy and hs>.8:
		s.stepT-=dt*(.6+hs/3.0)
		if float(s.stepT)<=0:
			s.stepT=randf_range(.22,.4)
			lens.droplet(0,Vector2(randf_range(.03,.34) if randf()<.5 else randf_range(.66,.97),randf_range(.02,.14)),randf_range(.012,.024),randf_range(.1,.4),randf_range(.6,1.1))
	var projectiles=game.get("projectiles")
	if alive and is_instance_valid(projectiles):
		for cloud:Dictionary in projectiles.storms:
			var point:Vector3=cloud.pos
			if Vector2(point.x-actor.global_position.x,point.z-actor.global_position.z).length_squared()<3.6*3.6:
				s.rainT-=dt
				if float(s.rainT)<=0:
					s.rainT=randf_range(.05,.12)
					var uv:=Vector2(randf(),randf_range(.15,1))
					if absf(uv.x-.5)<.16 and absf(uv.y-.5)<.2:uv.x+=.3*signf(uv.x-.5)
					var owner=cloud.get("owner")
					lens.droplet(1 if is_instance_valid(owner) and owner.team_id==actor.team_id else 0,uv.clamp(Vector2(.02,0),Vector2(.98,1)),randf_range(.008,.02),randf_range(.02,.2),randf_range(.5,1.1))
				break
	var low:float=clampf((.5-actor.hp/100.0)/.38,0,1) if alive else 0.0
	_damp("hurt",low,4,dt)
	if low>0:
		s.heartPh=fmod(float(s.heartPh)+dt*(80+70*low)/60.0,1.0)
		s.heart=low*(exp(-pow((float(s.heartPh)-.04)/.05,2))+.7*exp(-pow((float(s.heartPh)-.24)/.055,2)))
	else:_damp("heart",0,6,dt)
	s.auraPulse=maxf(0,float(s.auraPulse)-dt*1.4)
	var aura:float=maxf(.75 if alive and not actor.special_active.is_empty() else 0.0,maxf(float(s.jumpCharge)*.9,float(s.auraPulse)*.9))
	_damp("aura",aura,10.0 if aura>float(s.aura) else 2.5,dt)
	var charge:float=actor.charge if alive and actor.weapon_id=="charger" else 0.0
	_damp("focus",.25+.75*charge if charge>0 else 0.0,8,dt)
	if charge>=.999 and not bool(s.fullCharge):
		s.fullCharge=true
		s.chargePulse=1.0
	if charge<.999:s.fullCharge=false
	s.chargePulse=maxf(0,float(s.chargePulse)-dt*2.4)
	_damp("shimmer",.7 if alive and actor.invuln>0 and state=="playing" else 0.0,5,dt)
	s.urg=maxf(float(s.urgBase) if state=="playing" else 0.0,float(s.urg)-dt*1.6)
	if state!="playing":s.urgBase=0.0
	var desat:float=.45 if state=="finish" else (.62 if s.floodMode not in ["","reveal","fadeout"] else 0.0)
	_damp("desat",desat,5,dt)
	_damp("sat",.92 if state=="finish" else 1.0,4,dt)
	s.satPop=maxf(0,float(s.satPop)-dt*2.2)
	s.kill=maxf(0,float(s.kill)-dt*2.4)
	s.flash=maxf(0,float(s.flash)-dt*(4.5 if float(s.flash)>.6 else 2.6))
	s.chroma=maxf(0,float(s.chroma)-dt*3.2)
	s.blast=maxf(0,float(s.blast)-dt*2.4)
	s.blastT+=dt
	var steps:int=maxi(1,ceili(16.0*dt/.12))
	var h:float=dt/steps
	for i in range(steps):
		s.punchV+=(-256.0*float(s.punch)-32.0*float(s.punchV))*h
		s.punch+=float(s.punchV)*h
	if float(s.jumpCharge)>0:s.punch=lerpf(float(s.punch),-.012*float(s.jumpCharge),.2)
	_sim_flood(dt)

func _sim_flood(dt: float) -> void:
	if s.floodMode=="":
		s.flood=maxf(0,float(s.flood)-dt*2)
		s.hole=0.0
		return
	s.floodT+=dt
	var t:float=s.floodT
	if s.floodMode=="in":
		var k:float=clampf(t/.24,0,1)
		s.flood=(4*k*k*k if k<.5 else 1-pow(-2*k+2,3)*.5) if t<.24 else (1.0 if t<.5 else lerpf(1.0,.17,_ease_out((t-.5)/.8)))
		s.floodDrip=minf(.4,.05 if t<.5 else .05+(t-.5)*.08)
	elif s.floodMode=="reveal":
		s.flood=1.0
		s.floodDrip=.05
		var k:float=clampf((t-.1)/.72,0,1)
		s.hole=.0001 if t<.1 else (pow(k,1.7)*.75+_ease_out(k)*.25)*1.32
		if t>.86:
			s.floodMode=""
			s.flood=0.0
			s.hole=0.0
	elif s.floodMode=="fadeout":
		s.flood=maxf(0,float(s.flood)-dt*2.5)
		if float(s.flood)<=0:s.floodMode=""

func _set_uniform(parameter: String, value: Variant) -> void:
	uniforms[parameter]=value
	if material:material.set_shader_parameter(parameter,value)

func _uniform_color(name: String,color: Color,intensity: float) -> void:
	_set_uniform(name,Vector4(color.r,color.g,color.b,intensity))

func update(dt: float) -> void:
	if not is_instance_valid(game):return
	var state:String=str(game.get("state"))
	var active:bool=state in ["intro","playing","finish"]
	if state!=_state:
		if state=="intro" or not active:reset()
		if state=="playing":
			s.satPop=1.0
			s.chroma=minf(1.0,float(s.chroma)+.35)
			_kick(.015)
		_state=state
	if not active:
		panel.hide()
		return
	_local=game.get("local_player")
	_camera=game.get("camera")
	var size:Vector2=get_viewport().get_visible_rect().size
	panel.size=size
	_aspect=size.x/maxf(1,size.y)
	lens.resize(size)
	time+=dt
	var remaining:int=ceili(float(game.get("time_left")))
	if remaining<=10 and remaining!=_count:
		s.urg=1.0
		s.urgBase=clampf((11.0-remaining)/10.0,0,1)*.35
	_count=remaining
	_sim(dt,_local,state)
	lens.update(dt)
	var intensity:float=clampf(float(settings.get("cameraShake",1.0)),0,1)*(.35 if bool(settings.get("reducedMotion",false)) else 1.0)
	_set_uniform("uRes",size)
	_set_uniform("uAspect",_aspect)
	_set_uniform("uTime",time)
	for key in ["Speed","Stretch","Blast","Chroma"]:
		_set_uniform("u"+key,float(s[key.left(1).to_lower()+key.substr(1)])*intensity)
	_set_uniform("uPunch",clampf(float(s.punch),-.08,.08)*intensity)
	_set_uniform("uPunchPos",_punch_pos)
	_set_uniform("uBlastPos",_blast_pos)
	_set_uniform("uBlastColor",Vector3(_blast_color.r,_blast_color.g,_blast_color.b))
	_set_uniform("uBlastRing",_ease_out(float(s.blastT)/.55)*.9)
	_set_uniform("uLensOn",0.0 if lens.parts.is_empty() else 1.0)
	_set_uniform("uLensTexel",Vector2.ONE/Vector2(lens.target.size))
	_set_uniform("uHurt",s.hurt)
	_set_uniform("uFocus",s.focus)
	_set_uniform("uDesat",s.desat)
	_set_uniform("uSat",float(s.sat)+float(s.satPop)*.28)
	_set_uniform("uFloodDrip",s.floodDrip)
	_set_uniform("uFloodClear",1.0 if _water_flood else 0.0)
	_set_uniform("uHole",s.hole)
	_uniform_color("uFlood",_flood_color,float(s.flood))
	var rim:Color=_flood_color.lerp(Color.WHITE,.55)
	_set_uniform("uHoleRim",Vector3(rim.r,rim.g,rim.b)*1.6)
	_uniform_color("uFlash",Color.WHITE,float(s.flash)*(.3+.7*intensity))
	_uniform_color("uUrgency",Color(1,.16,.05),float(s.urg))
	if is_instance_valid(_local):
		var own:Color=_color(_local.team_id)
		var enemy:Color=_color(1-_local.team_id)
		_set_uniform("uLensColA",Vector3(enemy.r,enemy.g,enemy.b))
		_set_uniform("uLensColB",Vector3(own.r,own.g,own.b))
		var tint:Color=own.lerp(Color.WHITE,.6)
		_set_uniform("uSpeedTint",Vector3(tint.r,tint.g,tint.b))
		_uniform_color("uEdgeInk",enemy,float(s.edgeInk))
		_uniform_color("uHeart",enemy.lerp(Color(.55,0,.04),.55),float(s.heart))
		_uniform_color("uAura",Color(own.r*1.6,own.g*1.6,own.b*1.6),float(s.aura)*(.55+.45*intensity))
		_uniform_color("uSwim",own,float(s.swim))
		_uniform_color("uKill",Color(own.r*1.3,own.g*1.3,own.b*1.3),float(s.kill)*(.5+.5*intensity))
		_uniform_color("uShimmer",Color(own.r+.3,own.g+.3,own.b+.3),float(s.shimmer))
		_uniform_color("uCharge",Color(own.r+.5,own.g+.5,own.b+.5),float(s.chargePulse)*intensity)
	var visible_effect:bool=not lens.parts.is_empty() or absf(float(s.punch))>.0004 or absf(float(s.sat)-1)>.002
	for key in ["speed","stretch","blast","chroma","edgeInk","aura","heart","hurt","urg","swim","focus","chargePulse","shimmer","kill","flash","desat","satPop","flood"]:
		if float(s[key])>.002:visible_effect=true
	enabled=visible_effect
	panel.visible=visible_effect and not use_compositor
