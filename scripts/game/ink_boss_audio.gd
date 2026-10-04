class_name InkBossAudio
extends RefCounted

## src/audio/bossAudio.js director. Timers run on the native simulation clock.
var audio:Node
var boss:Node3D
var phase:int=1
var dead:bool=false
var state:String=""
var time:float=0.0
var hit_time:float=-9
var crit_time:float=-9
var foot_time:float=-9
var loops:Dictionary={}
var delayed:Array[Dictionary]=[]

func configure(owner:Node) -> void:audio=owner

func clear() -> void:
	_stop_all()
	boss=null;phase=1;dead=false;state="";time=0;hit_time=-9;crit_time=-9;foot_time=-9

func _pos(socket:String="") -> Vector3:
	if not is_instance_valid(boss):return Vector3.ZERO
	return boss.call("get_socket",socket,boss.global_position+Vector3.UP*3.0) if not socket.is_empty() and boss.has_method("get_socket") else boss.global_position+Vector3.UP*3.0

func _play(name:String,options:Dictionary={},delay:float=0.0) -> void:
	if delay>0:
		var copy:Dictionary=options.duplicate();copy.delay=delay;audio.call("play",name,copy)
	else:audio.call("play",name,options)

func _loop(key:String,name:String,duration:float,socket:String="",delay:float=0.0) -> void:
	if delay>0:
		delayed.append({"key":key,"name":name,"left":delay,"duration":duration,"socket":socket})
		return
	_stop(key)
	loops[key]={"name":name,"left":duration,"socket":socket}

func _stop(key:String) -> void:
	loops.erase(key)
	audio.call("stop_loop","boss_"+key)

func _stop_all() -> void:
	for key in loops.keys():_stop(str(key))
	delayed.clear()

func update(dt:float) -> void:
	if not is_instance_valid(boss):
		if not loops.is_empty():_stop_all()
		return
	time+=dt
	var game:Node=boss.get("match_node") as Node
	var next_state:String=str(game.get("state")) if game else ""
	if next_state!=state:
		state=next_state
		if state=="playing" and not dead:audio.call("play_music",["boss","boss_2","boss_3"][clampi(phase-1,0,2)],1.0)
		elif state=="finish":
			_stop_all()
			if not dead:audio.call("stop_music",.6)
		elif state in ["judge","results","menu"]:_stop_all()
	for i in range(delayed.size()-1,-1,-1):
		delayed[i].left-=dt
		if float(delayed[i].left)<=0:
			var row:Dictionary=delayed[i];delayed.remove_at(i)
			_loop(row.key,row.name,float(row.duration),row.socket)
	for key in loops.keys():
		var row:Dictionary=loops[key]
		row.left-=dt
		if float(row.left)<=0:_stop(key)
		else:audio.call("loop","boss_"+key,row.name,{"pos":_pos(row.socket)})

func on_event(kind:String,data:Dictionary) -> bool:
	if not kind.begins_with("boss:"):return false
	if is_instance_valid(data.get("boss")):boss=data.boss
	if kind=="boss:spawn":
		_stop_all();phase=1;dead=false;state="";time=0
		return true
	if not is_instance_valid(boss):return true
	match kind:
		"boss:intro":
			_play("boss_title")
			_play("boss_roar",{"pos":_pos("mouth"),"volume":1.0},.35)
			_play("boss_slam",{"pos":_pos(),"volume":.55,"pitch":.8},.1)
		"boss:move":
			if dead:return true
			var id:String=str(data.get("id",""));var move_phase:String=str(data.get("phase",""));var duration:float=float(data.get("dur",0))
			match id+":"+move_phase:
				"slam:tele":_play("boss_tele",{"pos":_pos("clawL")})
				"barrage:tele":_play("boss_tele",{"pos":_pos("shellTop"),"pitch":1.12})
				"barrage:act":
					for i in randi_range(3,5):
						_play("boss_whistle",{"pos":_pos("shellTop"),"pitch":randf_range(.9,1.15)},float(i)*.2)
						_play("boss_barrel",{"pos":_pos("shellTop"),"volume":.55},.95+float(i)*.2)
				"sweep:tele":_play("boss_cannon_charge",{"pos":_pos("cannon")})
				"sweep:act":_loop("sweep","boss_cannon_sweep",maxf(1,duration)+.2,"cannon")
				"sweep:rec":_stop("sweep")
				"charge:tele":
					_play("boss_tele",{"pos":_pos("mouth"),"pitch":.82})
					_play("boss_roar",{"pos":_pos("mouth"),"volume":.45,"pitch":1.25},.2)
				"charge:act":_loop("gallop","boss_gallop",maxf(1,duration)+.3)
				"charge:rec":_stop("gallop")
				"crablets:tele":_play("boss_tele",{"pos":_pos("hatch"),"pitch":1.25})
				"crablets:act":
					_play("crablet_chitter",{"pos":_pos("hatch")})
					_play("crablet_chitter",{"pos":_pos("hatch"),"pitch":1.15},.3)
				"frenzy:tele":_play("boss_roar",{"pos":_pos("mouth"),"volume":.7,"pitch":1.15})
				"frenzy:act":_loop("frenzy","boss_frenzy",maxf(1,duration)+.3)
				"frenzy:rec":_stop("frenzy")
		"boss:stun":
			if dead:return true
			_stop("gallop");_play("boss_crash",{"pos":_pos("shellTop")})
			_loop("dizzy","boss_dizzy",maxf(.6,float(data.get("dur",3))-.3),"eyeL",.35)
		"boss:phase":
			var next_phase:int=clampi(int(data.get("phase",1)),1,3)
			if next_phase>phase:
				phase=next_phase;_stop_all();_play("boss_phase")
				_play("boss_roar",{"pos":_pos("mouth"),"pitch":.88 if phase>=3 else .95},.3)
				if state=="playing":audio.call("play_music",["boss","boss_2","boss_3"][phase-1],1.0)
		"boss:hit":
			if dead or bool(data.get("crab",false)) or bool(data.get("blocked",false)):return true
			var attacker=data.get("attacker")
			var local:bool=is_instance_valid(attacker) and bool(attacker.get("is_local"))
			if bool(data.get("weak",false)):
				if time-crit_time>(.07 if local else .3):
					crit_time=time;_play("boss_crit",{} if local else {"pos":data.get("pos",_pos("eyeL")),"volume":.5})
			elif local and time-hit_time>.06:hit_time=time;_play("boss_hit")
		"boss:defeat":
			if dead:return true
			dead=true;_stop_all();audio.call("stop_music",.5)
			_play("boss_defeat",{"pos":_pos()});_play("boss_sunk",{},1.35)
		"boss:foot":
			if not dead and time-foot_time>=.06:
				foot_time=time
				var strength:float=clampf(float(data.get("strength",.6)),0,1)
				_play("boss_step",{"pos":data.get("pos",_pos()),"volume":.35+.65*strength,"pitch":randf_range(.9,1.1)})
		"boss:impact":
			var strength:float=clampf(float(data.get("strength",1)),.2,1)
			if "claw" in str(data.get("socket","")):_play("boss_slam",{"pos":data.get("pos",_pos()),"volume":strength})
			elif not dead:_play("boss_step",{"pos":data.get("pos",_pos()),"pitch":.75})
		"boss:crablet":_play("crablet_chitter" if str(data.get("phase"))=="spawn" else "crablet_pop",{"pos":data.get("pos",_pos()),"pitch":1.1 if bool(data.get("killed",false)) else .85})
	return true
