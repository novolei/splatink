class_name InkBots
extends RefCounted

const Rules = preload("res://scripts/game/ink_rules.gd")
const ActorNavigation=preload("res://scripts/game/ink_actor_nav.gd")
const LevelQueries=preload("res://scripts/game/ink_level_queries.gd")
var actor_nav:InkActorNav
var level_queries:InkLevelQueries
var match_node: Node
var difficulty: String = "normal"
var states: Dictionary = {}
var clock: float = 0.0
var profile_navigation:bool=false
var navigation_profile:Dictionary={}

func configure(game: Node, level: String = "normal") -> void:
	match_node = game
	difficulty = level
	states.clear()
	profile_navigation=false
	for argument in OS.get_cmdline_user_args():
		if argument.trim_prefix("--").begins_with("profile-render"):profile_navigation=true
	actor_nav=null
	level_queries=null
	var stage=game.get("stage")
	if is_instance_valid(stage):
		var queries=stage.get("level_queries")
		if queries is InkLevelQueries:level_queries=queries
		elif stage.get("blocks") is Array and not stage.get("blocks").is_empty():level_queries=LevelQueries.new();level_queries.configure(stage)
		var source=stage.get("actor_nav")
		if source is InkActorNav:actor_nav=source
		else:
			var id=stage.get("stage_id")
			if id is String:
				var graph:=ActorNavigation.new()
				if graph.configure(id):actor_nav=graph
	if actor_nav:actor_nav.profile_navigation=profile_navigation

func command_for(actor, dt: float) -> Dictionary:
	if not profile_navigation:return _command_for(actor,dt)
	navigation_profile.clear()
	if actor_nav:actor_nav.reset_query_profile()
	var started:int=Time.get_ticks_usec()
	var command:Dictionary=_command_for(actor,dt)
	navigation_profile.total_us=Time.get_ticks_usec()-started
	if actor_nav:navigation_profile.merge(actor_nav.query_profile,true)
	return command

func _command_for(actor, dt: float) -> Dictionary:
	var id: int = actor.get_instance_id()
	if not states.has(id):
		states[id] = {"target": null, "goal": actor.global_position, "path": PackedVector3Array(), "path_index": 0, "think": randf() * 0.2, "goal_time": 0.0, "reaction": 0.0, "yaw": actor.aim_yaw, "pitch": 0.0, "yaw_velocity": 0.0, "pitch_velocity": 0.0, "phase": randf() * TAU, "charge_time": 0.0, "bomb_time": 0.0, "bomb_cooldown": randf_range(3.0, 7.0), "dodge_cooldown": 1.0, "stuck": 0.0, "last_position": actor.global_position, "side": -1.0 if randf() < 0.5 else 1.0, "mode": "paint"}
		states[id].ph1=randf()*20;states[id].ph2=randf()*20;states[id].acq_time=9.0;states[id].acq_sign_y=0.0;states[id].acq_sign_p=0.0;states[id].time=randf()*10
	var s: Dictionary = states[id]
	s["time"] = float(s.get("time", 0.0)) + dt
	s.acq_time=float(s.get("acq_time",9.0))+dt
	var now: float = float(s["time"])
	var cfg: Dictionary = Rules.section("DIFFICULTY").get(difficulty, {})
	var reaction: float = float(cfg.get("reaction", 0.32))
	var awareness: float = float(cfg.get("awareness", 21.0))
	var error: float = float(cfg.get("aimError", 0.06))
	s["think"] -= dt
	s["goal_time"] -= dt
	s["bomb_cooldown"] -= dt
	s["dodge_cooldown"] -= dt
	s.jump_cooldown=float(s.get("jump_cooldown",0.0))-dt
	var move: Vector3 = Vector3.ZERO
	var cmd: Dictionary = {"move": move, "fire": false, "swim": false, "jump": false, "sub": false, "special": false, "aim_dir": actor.aim_dir}
	if not actor.alive:
		return cmd
	var match_boss=match_node.get("boss")
	if is_instance_valid(match_boss):return _boss_command(actor,match_boss,s,dt,cfg)
	if float(s["think"]) <= 0.0:
		s["think"] = 0.16
		var target = _perceive(actor, awareness)
		if target != s["target"]:
			s["target"] = target
			s["reaction"] = reaction*randf_range(.7,1.3)
			_acquire(s)
		if float(s["goal_time"]) <= 0.0 or Vector3(s["goal"]).distance_to(actor.global_position) < 1.8:
			_choose_goal(actor, s)
	s["reaction"] = maxf(0.0, float(s["reaction"]) - dt)
	var target = s["target"]
	if not is_instance_valid(target) or (target.get("alive") != null and not target.get("alive")) or (target.get("dead") != null and target.get("dead")):
		target = null
		s["target"] = null
	s.need_jump=false
	s.aim_target=target!=null
	move=_path_move(actor,s,dt)
	s.want_move=move.length_squared()>.01
	var aim_point: Vector3 = actor.global_position + move * 9.0 + Vector3.UP * 0.1
	var own_ink: bool = actor.ground_team == actor.team_id
	var refill: bool = actor.ink < 22.0 or (actor.hp < 40.0 and own_ink)
	s["mode"] = "refill" if refill else ("fight" if target else "paint")
	if refill:
		cmd["swim"] = true
		if own_ink:
			move = Vector3.ZERO
		else:
			move = _nearest_ink(actor)
	elif target:
		var boss_target: bool = target.has_method("ray_hit")
		var target_pos: Vector3 = target.global_position
		var distance: float = actor.global_position.distance_to(target_pos)
		var reach: float = _weapon_range(actor.weapon_id)
		var toward: Vector3 = (target_pos - actor.global_position)
		toward.y = 0.0
		toward = toward.normalized()
		aim_point = target_pos + Vector3.UP * (3.0 if boss_target else (0.24 if target.form != "kid" else 0.75))
		if boss_target and target.has_method("get_socket"):
			aim_point = target.call("get_socket", "eyeL", aim_point)
		if distance > reach * 0.84:
			move = toward
			cmd["swim"] = own_ink and distance > reach * 1.15
		elif distance < reach * 0.35 and actor.weapon_id != "roller":
			move = -toward
		else:
			var strafe: Vector3 = Vector3.UP.cross(toward)
			move = (strafe * float(s["side"]) * sin(now * 1.8 + float(s["phase"])) + toward * 0.12).normalized()
		if float(s["reaction"]) <= 0.0 and distance < reach * 1.08:
			cmd["fire"] = not bool(cmd["swim"])
		if actor.special_fraction() >= 1.0 and (distance < 5.0 or str(Rules.weapon(actor.weapon_id).get("special", "slam")) == "storm"):
			cmd["special"] = true
		if float(s["bomb_cooldown"]) <= 0.0 and actor.ink >= 80.0 and distance > 4.0 and distance < 16.0:
			s["bomb_time"] = 0.28
			s["bomb_cooldown"] = randf_range(4.0, 7.0)
		if float(s["dodge_cooldown"]) <= 0.0 and actor.hp < 80.0:
			cmd["jump"] = true
			s["dodge_cooldown"] = randf_range(0.8, 1.6)
	else:
		cmd["swim"] = own_ink and randf() > 0.35 and actor.ink < 85.0
		cmd["fire"] = not bool(cmd["swim"]) and actor.ink > 10.0
		if actor.weapon_id == "charger":
			aim_point = actor.global_position + move * 20.0 - Vector3.UP * 0.15
	if float(s["bomb_time"]) > 0.0:
		s["bomb_time"] -= dt
		cmd["sub"] = float(s["bomb_time"]) > 0.0
		cmd["sub_released"] = float(s["bomb_time"]) <= 0.0
		cmd["fire"] = false
	if actor.weapon_id in ["charger", "splatling"] and bool(cmd["fire"]):
		s["charge_time"] += dt
		var w: Dictionary = Rules.weapon(actor.weapon_id)
		if float(s["charge_time"]) > float(w.get("chargeTime", 1.0)) + 0.06:
			cmd["fire"] = false
			s["charge_time"] = -0.12
	else:
		s["charge_time"] = maxf(0.0, float(s["charge_time"]) + dt) if float(s["charge_time"]) < 0.0 else 0.0
	s["last_position"] = actor.global_position
	_smooth_command(actor,s,cmd,move,aim_point,dt,cfg,target!=null and bool(cmd.fire))
	return cmd

# Boss combat has its own source job: hold a reachable flank at weapon distance.
func boss_goal_radius(weapon:String,stunned:bool=false) -> float:
	var reach:float=15.0 if weapon=="charger" else (3.2 if weapon=="roller" else clampf(_weapon_range(weapon)*.7,4.5,11.0))
	return 3.4+(minf(reach,6.0) if stunned else reach)

func separate(actor,wanted:Vector3) -> Vector3:
	for other in match_node.get("actors"):
		if other==actor or not other.alive:continue
		var delta:Vector3=actor.global_position-other.global_position
		var squared:float=delta.x*delta.x+delta.z*delta.z
		if squared>=1.4*1.4 or squared<=.0001:continue
		var strength:float=(1.4-sqrt(squared))*.7
		var side:float=1.0 if delta.x*(-wanted.z)+delta.z*wanted.x>=0.0 else -1.0
		wanted=Vector3(wanted.x-wanted.z*side*strength,0,wanted.z+wanted.x*side*strength)
	return wanted.limit_length(1.0)

func _path_move(actor,s:Dictionary,dt:float=1.0/60.0) -> Vector3:
	if not profile_navigation:return _path_move_source(actor,s,dt)
	var started:int=Time.get_ticks_usec()
	var result:Vector3=_path_move_source(actor,s,dt)
	_profile_span("path_steer_us",started)
	return result

func _profile_span(label:String,started:int) -> void:
	navigation_profile[label]=int(navigation_profile.get(label,0))+Time.get_ticks_usec()-started

func _path_move_source(actor,s:Dictionary,dt:float=1.0/60.0) -> Vector3:
	var destination:Vector3=s.goal
	var path:PackedVector3Array=s.path
	if path.is_empty():return Vector3.ZERO
	var index:int=int(s.path_index)
	if not path.is_empty():
		while index<path.size():
			var delta:Vector3=path[index]-actor.global_position
			if delta.x*delta.x+delta.z*delta.z<.36 and delta.y<.9 and delta.y> -1.8:index+=1;s.best_distance=INF;s.no_progress=0.0
			else:break
		s.path_index=index
		if index>=path.size():return Vector3.ZERO
		var current:Vector3=path[index]
		var horizontal:float=Vector2(current.x-actor.global_position.x,current.z-actor.global_position.z).length()
		var ids:PackedInt32Array=s.get("nav_ids",PackedInt32Array())
		if actor_nav and not ids.is_empty():
			var edge:String=actor_nav.edge_type(ids[maxi(0,index-1)],ids[index])
			if actor.is_grounded() and current.y-actor.global_position.y>.9 and horizontal<1.2 and edge!="jump":s.path=PackedVector3Array();s.goal_time=0.0;return Vector3.ZERO
			if index>0 and edge=="jump" and current.y-actor.global_position.y>.4 and horizontal<1.6:s.need_jump=true
		var target_index:int=index
		s.look_time=float(s.get("look_time",0))-dt
		if float(s.look_time)>0 and int(s.get("look_index",-1))==index and int(s.get("look_target",-1))<path.size():target_index=int(s.look_target)
		else:
			if actor_nav and not ids.is_empty():
				for next in range(index+1,mini(path.size(),index+7)):
					var point:Vector3=path[next]
					if absf(point.y-actor.global_position.y)>.4 or actor_nav.edge_type(ids[next-1],ids[next])!="walk":break
					if not _fat_los(actor.global_position,point) or not _dry_line(actor.global_position,point):break
					target_index=next
			s.look_time=.1;s.look_index=index;s.look_target=target_index
		destination=path[target_index]
		if horizontal<float(s.get("best_distance",INF))-.2:s.best_distance=horizontal;s.no_progress=0.0
		else:s.no_progress=float(s.get("no_progress",0))+dt
	var delta:Vector3=destination-actor.global_position
	delta.y=0.0
	return Vector3.ZERO if delta.length()<.001 else separate(actor,delta.normalized())

func _set_path(actor,s:Dictionary,point:Vector3,max_up:float=.8) -> void:
	s.goal=point;s.path_index=0;s.path=PackedVector3Array()
	s.nav_ids=PackedInt32Array();s.goal_id=-1;s.look_time=0.0;s.best_distance=INF;s.no_progress=0.0
	s.repath=randf_range(.8,1.2)
	if actor_nav:
		var end:int=actor_nav.nearest(point,max_up)
		var ids:PackedInt32Array=actor_nav.path_ids(actor_nav.nearest(actor.global_position,1.2),end,actor.team_id)
		var points:PackedVector3Array=[]
		for id in ids:points.append(actor_nav.point(id))
		s.path=points;s.nav_ids=ids;s.path_index=mini(1,ids.size()-1) if not ids.is_empty() else 0
		if not ids.is_empty():s.goal_id=end
		return
	var stage=match_node.get("stage")
	if is_instance_valid(stage) and stage.has_method("find_path"):
		var path=stage.call("find_path",actor.global_position,point,actor.team_id)
		if path is PackedVector3Array:s.path=path
		elif path is Array:s.path=PackedVector3Array(path)

func _fat_los(from:Vector3,to:Vector3) -> bool:
	var direction:Vector3=to-from;direction.y=0;direction=direction.normalized()
	var shoulder:=Vector3(-direction.z,0,direction.x)*.34
	for side in [0,1,-1]:
		var offset:Vector3=shoulder*side+Vector3.UP*.45
		if not match_node.call("cast",from+offset,to+offset,[]).is_empty():return false
	return true

func _wet(point:Vector3) -> bool:
	var stage=match_node.get("stage")
	if not is_instance_valid(stage) or not stage.has_method("ground_height"):return false
	var ground:float=float(stage.call("ground_height",point.x,point.z,point.y+.6))
	return not is_finite(ground) or ground<Rules.player("fallDeathY",-8.0)

func _dry_line(from:Vector3,to:Vector3) -> bool:
	var count:int=ceili(Vector2(to.x-from.x,to.z-from.z).length()/.45)
	for index in range(1,count+1):
		var point:Vector3=from.lerp(to,float(index)/float(count));point.y=from.y
		if _wet(point):return false
	return true

func register_boss_threat(s:Dictionary,threat:Dictionary,cfg:Dictionary,now:float) -> void:
	if float(threat.get("level",0))>0 or float(threat.get("ringIn",-1))>=0:
		if not s.has("threat_seen"):
			s.threat_seen=now+float(cfg.get("reaction",.32))*(.5+randf()*.9)
			s.hop_miss=randf()<.45-float(cfg.get("fireDiscipline",.7))*.4
		if now<float(s.threat_seen):threat.level=0.0;threat.ringIn=-1.0;threat.beam=false;threat.cover=false
	else:s.erase("threat_seen")

func _boss_evade(actor,boss,s:Dictionary,threat:Dictionary) -> bool:
	if not profile_navigation:return _boss_evade_source(actor,boss,s,threat)
	var started:int=Time.get_ticks_usec()
	var result:bool=_boss_evade_source(actor,boss,s,threat)
	_profile_span("evade_us",started)
	return result

func _boss_evade_source(actor,boss,s:Dictionary,threat:Dictionary) -> bool:
	var best:Vector3=actor.global_position;var highest:float=-INF;var found:bool=false
	var stage=match_node.get("stage")
	for index in 12:
		var angle:float=atan2(float(threat.get("ax",0)),float(threat.get("az",0)))+randf_range(-1.2,1.2)
		var radius:float=randf_range(3,8)
		var point:Vector3=actor.global_position+Vector3(sin(angle),0,cos(angle))*radius
		if actor_nav:
			var id:int=actor_nav.nearest(point,1.2)
			if id<0:continue
			point=actor_nav.point(id)
		elif is_instance_valid(stage) and stage.has_method("ground_height"):
			var height:float=float(stage.call("ground_height",point.x,point.z,point.y+1.2))
			if not is_finite(height) or height<=Rules.player("waterY",-3.2):continue
			point.y=height
		else:continue
		var danger:Dictionary=boss.call("threat",point,1.6)
		var score:float=-float(danger.get("level",0))*8-Vector2(point.x-actor.global_position.x,point.z-actor.global_position.z).length()*.25+(sin(angle)*float(threat.get("ax",0))+cos(angle)*float(threat.get("az",0)))*1.5+randf()*.5
		if score>highest:highest=score;best=point;found=true
	if found:_set_path(actor,s,best,1.0);s.goal_time=.8
	return found

func _boss_goal(actor,boss,s:Dictionary) -> void:
	if not profile_navigation:_boss_goal_source(actor,boss,s);return
	var started:int=Time.get_ticks_usec()
	_boss_goal_source(actor,boss,s)
	_profile_span("goal_us",started)

func _boss_goal_source(actor,boss,s:Dictionary) -> void:
	s.goal_time=randf_range(2.4,4.4);s.rushing=bool(boss.stunned)
	var exposed:bool=bool(boss.stunned) or (int(boss.phase)>=3 and randf()<.3)
	if actor.weapon_id=="roller" and not boss.stunned and level_queries:
		var clean_point:Vector3=Vector3.ZERO;var clean_score:float=.25;var has_clean:bool=false
		for index in 12:
			var angle:float=randf()*TAU;var distance:float=randf_range(3,15)
			var point:Vector3=actor.global_position+Vector3(cos(angle),0,sin(angle))*distance
			var stats:Dictionary=level_queries.region_stats(point,2.2,actor.team_id)
			if int(stats.n)==0 or float(boss.call("threat",point,1.5).get("level",0))>0:continue
			var score:float=float(stats.enemy)-distance*.02
			if score>clean_score:clean_point=point;clean_score=score;has_clean=true
		if has_clean and randf()<.7:_set_path(actor,s,clean_point,.4);return
	var radius:float=boss_goal_radius(actor.weapon_id,bool(boss.stunned))
	var best:Vector3=actor.global_position
	var highest:float=-INF
	var stage=match_node.get("stage")
	for index in 12:
		var offset:float=randf_range(-.65,.65) if exposed else (1.0 if randf()<.5 else -1.0)*randf_range(.95,2.85)
		var angle:float=boss.rotation.y+offset
		var reach:float=radius*randf_range(.85,1.15)
		var point:Vector3=boss.global_position+Vector3(sin(angle),0,cos(angle))*reach
		if actor_nav:
			point.y=boss.global_position.y+.5
			var id:int=actor_nav.nearest(point,2.5)
			if id<0:continue
			var nearest:Vector3=actor_nav.point(id)
			if Vector2(nearest.x-point.x,nearest.z-point.z).length()>2.5:continue
			point=nearest
		elif is_instance_valid(stage) and stage.has_method("ground_height"):
			var height:float=float(stage.call("ground_height",point.x,point.z,boss.global_position.y+2.5))
			if not is_finite(height) or height<=Rules.player("waterY",-3.2):continue
			point.y=height
		else:
			var floor_hit:Dictionary=match_node.call("cast",point+Vector3.UP*.5,point-Vector3.UP*3.0,[])
			if floor_hit.is_empty():continue
			point.y=floor_hit.position.y
		var score:float=-Vector2(point.x-actor.global_position.x,point.z-actor.global_position.z).length()*.08+randf()
		if boss.has_method("threat") and float(boss.call("threat",point,1.5).get("level",0))>0:score-=6.0
		if match_node.call("cast",point+Vector3.UP*1.3,boss.global_position+Vector3.UP*2.5,[]).is_empty():score+=3.0
		for mate in match_node.get("actors"):
			if mate==actor or not mate.alive or not states.has(mate.get_instance_id()):continue
			if actor_nav and int(states[mate.get_instance_id()].get("goal_id",-1))<0:continue
			var goal:Vector3=states[mate.get_instance_id()].goal
			if Vector2(goal.x-point.x,goal.z-point.z).length()<4.0:score-=2.5
		if score>highest:highest=score;best=point
	if is_finite(highest):_set_path(actor,s,best,1.0)
	else:s.path=PackedVector3Array()

func _boss_perceive(actor,boss,s:Dictionary,cfg:Dictionary) -> Dictionary:
	var eye:Vector3=actor.global_position+Vector3.UP*1.2
	var target:Dictionary={}
	var nearest:float=9.0
	for crab in boss._crablets:
		if bool(crab.get("dead",false)):continue
		var point:Vector3=crab.node.global_position+Vector3.UP*.35
		var distance:float=Vector2(point.x-eye.x,point.z-eye.z).length()
		if distance>=nearest or not match_node.call("cast",eye,point,[actor.get_rid()]).is_empty():continue
		nearest=distance
		target={"crab":crab,"point":point,"radius":.5,"distance":distance,"los":true,"key":"crab_%s" % crab.id}
	if target.is_empty() and boss.visible and not boss.dead:
		var shapes:Array=boss.hit_shapes()
		s.shape_time=float(s.get("shape_time",0.0))-.2
		var pick:Dictionary={}
		var belly:Dictionary={}
		for shape in shapes:
			if not shape.active:continue
			if shape.socket=="belly":belly=shape
			if shape.socket==str(s.get("shape_socket","")) and float(s.shape_time)>0.0:pick=shape
		if not belly.is_empty() and pick.get("socket","")!="belly":pick={}
		if pick.is_empty():
			s.shape_time=randf_range(1.2,2.7)
			var prefer_eyes:bool=actor.weapon_id=="charger" or randf()<.25+float(cfg.get("fireDiscipline",.7))*.3
			var candidates:Array[Dictionary]=[]
			for shape in shapes:
				if not shape.active:continue
				shape["score"]=( -100.0 if shape.socket=="belly" else (-50.0 if shape.weak and prefer_eyes else (10.0 if shape.weak else 0.0)))+Vector3(shape.center).distance_to(eye)
				candidates.append(shape)
			candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.score)<float(b.score))
			for shape in candidates:
				if match_node.call("cast",eye,shape.center,[actor.get_rid()]).is_empty():pick=shape;break
			if pick.is_empty():
				for shape in candidates:
					if not shape.weak:pick=shape;break
		if not pick.is_empty():
			s.shape_socket=pick.socket
			target={"shape":pick,"point":pick.center,"radius":float(pick.radius)*.85,"weak":pick.weak,"los":match_node.call("cast",eye,pick.center,[actor.get_rid()]).is_empty(),"key":pick.socket}
	if target.get("key","")!=s.get("boss_target",{}).get("key",""):
		s.reaction=float(cfg.get("reaction",.32))*randf_range(.6,1.1)
		_acquire(s)
	return target

func _boss_command(actor,boss,s:Dictionary,dt:float,cfg:Dictionary) -> Dictionary:
	var cmd:Dictionary={"move":Vector3.ZERO,"fire":false,"swim":false,"jump":false,"sub":false,"sub_released":false,"special":false,"aim_dir":actor.aim_dir}
	if not actor.super_jump_state.is_empty() or str(match_node.get("state"))!="playing":return cmd
	if float(s.think)<=0.0:
		s.think=randf_range(.12,.22)
		s.boss_target=_boss_perceive(actor,boss,s,cfg)
	s.reaction=maxf(0.0,float(s.reaction)-dt)
	var ink_fraction:float=actor.ink/Rules.player("inkMax",100)
	var target:Dictionary=s.get("boss_target",{})
	if s.mode=="refill" and ink_fraction>=float(s.get("refill_until",.85)):s.mode="boss";s.goal_time=0.0
	if s.mode!="refill" and ink_fraction<.1 and not (target.has("crab") and float(target.get("distance",9))<4 and ink_fraction>.03):s.mode="refill";s.refill_until=randf_range(.8,.95)
	if s.mode!="refill":s.mode="boss"
	var own_ink:bool=actor.ground_team==actor.team_id
	var danger:Dictionary=boss.call("threat",actor.global_position,1.4) if boss.has_method("threat") else {"level":0.0,"ringIn":-1.0,"beam":false}
	register_boss_threat(s,danger,cfg,float(s.time))
	s.evade_time=float(s.get("evade_time",0))-dt
	s.refill_repath=float(s.get("refill_repath",0))-dt
	var dive:bool=bool(danger.get("beam",false)) and own_ink
	var evading:bool=float(danger.get("level",0))>.2 and not dive
	if evading:
		if float(s.evade_time)<=0 or s.path.is_empty():_boss_evade(actor,boss,s,danger);s.evade_time=.45
	else:
		if bool(s.get("was_evading",false)):s.path=PackedVector3Array();s.goal_time=0.0
		if s.mode=="refill" and level_queries:
			if float(s.refill_repath)<=0 or s.path.is_empty():_pick_refill(actor,s)
		elif float(s.goal_time)<=0.0 or s.path.is_empty() or int(s.path_index)>=s.path.size() or (bool(boss.stunned) and not bool(s.get("rushing",false))):_boss_goal(actor,boss,s)
	s.was_evading=evading;s.need_jump=false
	var move:Vector3=_path_move(actor,s,dt)
	s.want_move=move.length_squared()>.01
	var aim_point:Vector3=actor.global_position+(move if move.length_squared()>.01 else actor.global_basis.z)*6.0+Vector3.UP*.5
	var fighting:bool=false
	s.aim_target=false
	if s.mode=="refill":
		if not level_queries:move=Vector3.ZERO if own_ink else _nearest_ink(actor)
		var remaining:float=Vector2(Vector3(s.goal).x-actor.global_position.x,Vector3(s.goal).z-actor.global_position.z).length() if not s.path.is_empty() else 0.0
		cmd.swim=own_ink or remaining>2
		if not own_ink and remaining<1.5 and ink_fraction>.03:
			cmd.fire=true;cmd.swim=false
			aim_point=actor.global_position+Vector3.UP*1.1+(actor.global_basis.z*cos(-1.0)+Vector3.UP*sin(-1.0))*6
	elif not target.is_empty() and not dive:
		if target.has("crab"):
			var crab:Dictionary=target.crab
			if bool(crab.get("dead",false)) or not is_instance_valid(crab.node):target={}
			else:target.point=crab.node.global_position+Vector3.UP*.35
		elif target.has("shape"):
			for shape in boss.hit_shapes():
				if shape.socket==target.key:target.point=shape.center;target.shape=shape;break
		if not target.is_empty():
			s.aim_target=true
			aim_point=target.point
			var delta:Vector3=aim_point-actor.global_position-Vector3.UP*1.1
			var distance:float=Vector2(delta.x,delta.z).length()
			target.distance=distance
			var range_limit:float=_weapon_range(actor.weapon_id)+(0.0 if target.has("crab") else float(target.radius)/.85*.6)
			if move.length_squared()<.01 and float(danger.get("level",0))==0 and actor.weapon_id!="charger":
				if float(s.get("strafe_timer",0))<=0:s.strafe_timer=randf_range(.8,2.2);s.side=-1.0 if randf()<.5 else 1.0;s.strafe_amp=randf_range(.35,.75)
				s.strafe_timer=float(s.strafe_timer)-dt
				s.strafe_s=lerpf(float(s.get("strafe_s",0)),float(s.side)*float(s.strafe_amp),1.0-exp(-4.0*dt))
				var toward:Vector3=Vector3(delta.x,0,delta.z)/maxf(distance,.01)
				move=Vector3(-toward.z,0,toward.x)*float(s.strafe_s)
				if distance<4.0:move-=toward*.6
				s.want_move=move.length_squared()>.01
			var yaw:float=atan2(delta.x,delta.z)
			var pitch:float=atan2(delta.y,distance)
			var off:float=Vector2(wrapf(float(s.yaw)-yaw,-PI,PI),float(s.pitch)-pitch).length()
			var tolerance:float=maxf(.05,atan2(float(target.radius),maxf(distance,.5)))*(2.4 if bool(s.get("firing",false)) else 1.5)
			if distance<range_limit*(1.0 if actor.weapon_id=="charger" else 1.05) and bool(target.los) and off<tolerance and float(s.reaction)<=0 and ink_fraction>.02:
				cmd.fire=true
				if actor.weapon_id in ["charger","splatling"]:
					var release:float=float(s.get("charge_release",.97))*(.9 if actor.weapon_id=="splatling" else 1.0)
					cmd.fire=actor.charge<release and float(actor.weapon_state.get("burst",0))<=0
					if actor.charge>0:move*=.3 if actor.weapon_id=="charger" else .45
				elif actor.weapon_id=="roller":cmd.fire=distance<5.5 or (actor.rolling and distance<8)
				fighting=bool(cmd.fire)
				if float(s.bomb_cooldown)<=0 and not target.has("crab") and actor.ink>80 and distance>5 and distance<13 and randf()<.025:s.bomb_time=.01;s.bomb_cooldown=randf_range(6,12)
			elif actor.weapon_id in ["charger","splatling"] and actor.charge>0 and bool(target.los):cmd.fire=true
			if actor.special_fraction()>=1 and float(danger.get("level",0))==0 and not target.has("crab"):
				var special:String=str(Rules.weapon(actor.weapon_id).get("special","slam"))
				cmd.special=(special=="slam" and distance<5.5) or (special=="storm" and distance<13 and bool(target.los))
	if not cmd.fire and s.mode!="refill" and not dive and ink_fraction>.15 and level_queries:
		var heading:float=atan2(move.x,move.z) if move.length_squared()>.01 else actor.rotation.y
		var stats:Dictionary=level_queries.region_stats(actor.global_position+Vector3(sin(heading),0,cos(heading))*3,2.5,actor.team_id)
		if actor.ground_team==1-actor.team_id or (int(stats.n)>0 and float(stats.enemy)>.2):
			s.sweep=float(s.get("sweep",0))+dt*2.1
			if not fighting:
				s.aim_target=false
				var yaw:float=heading+(0.0 if actor.weapon_id=="roller" else sin(float(s.sweep))*.5)
				var pitch:float=-.12 if actor.weapon_id=="charger" else (-.28 if actor.weapon_id=="blaster" else -.42)
				aim_point=actor.global_position+Vector3.UP*1.1+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*6
			cmd.fire=move.length_squared()>.01 if actor.weapon_id=="roller" else (actor.charge<.6 if actor.weapon_id in ["charger","splatling"] else true)
	if float(s.bomb_time)>0:s.bomb_time=0.0;cmd.sub=true;s.release_bomb=true;cmd.fire=false
	elif bool(s.get("release_bomb",false)):cmd.sub_released=true;s.release_bomb=false
	if float(danger.get("ringIn",-1))>=0 and float(danger.ringIn)<.2 and not bool(s.get("hop_miss",false)) and actor.is_grounded() and float(s.jump_cooldown)<=0:cmd.jump=true;s.jump_cooldown=.5
	if dive:cmd.swim=true;cmd.fire=false
	elif not cmd.fire and actor.charge<=0 and own_ink and (Vector3(s.goal).distance_to(actor.global_position)>4 or float(danger.get("level",0))>.2):cmd.swim=true
	s.firing=bool(cmd.fire)
	_smooth_command(actor,s,cmd,move,aim_point,dt,cfg,fighting)
	return cmd

func _smooth_command(actor,s:Dictionary,cmd:Dictionary,move:Vector3,aim_point:Vector3,dt:float,cfg:Dictionary,fighting:bool) -> void:
	var delta:Vector3=aim_point-actor.global_position-Vector3.UP*1.1
	var desired_aim:=Vector2(atan2(delta.x,delta.z),atan2(delta.y,Vector2(delta.x,delta.z).length()))
	if bool(s.get("aim_target",false)):desired_aim=target_aim(desired_aim,s,cfg,match_node.get("boss")!=null)
	var yaw:float=desired_aim.x
	var pitch:float=clampf(desired_aim.y,-1.1,1.0)
	var omega:float=float(cfg.get("aimOmega",13)) if fighting else 8.0
	var turn:float=float(cfg.get("aimTurn",10)) if fighting else 6.0
	s.yaw_velocity=clampf(float(s.yaw_velocity)+(omega*omega*wrapf(yaw-float(s.yaw),-PI,PI)-2*omega*float(s.yaw_velocity))*dt,-turn,turn)
	s.yaw=wrapf(float(s.yaw)+float(s.yaw_velocity)*dt,-PI,PI)
	s.pitch_velocity=clampf(float(s.pitch_velocity)+(omega*omega*(pitch-float(s.pitch))-2*omega*float(s.pitch_velocity))*dt,-turn*.7,turn*.7)
	s.pitch=clampf(float(s.pitch)+float(s.pitch_velocity)*dt,-1.1,1.0)
	var magnitude:float=minf(1,move.length())
	var move_yaw:float=float(s.get("move_yaw",actor.aim_yaw))
	var move_magnitude:float=float(s.get("move_magnitude",0))
	if magnitude>.01:
		var desired:float=atan2(move.x,move.z)
		var difference:float=wrapf(desired-move_yaw,-PI,PI)
		if move_magnitude<.05:move_yaw=desired
		elif absf(difference)>2.1:move_yaw=desired;move_magnitude*=.35
		else:move_yaw+=clampf(difference,-11*dt,11*dt)
	move_magnitude=lerpf(move_magnitude,magnitude,1.0-exp(-14*dt))
	s.move_yaw=move_yaw;s.move_magnitude=move_magnitude
	cmd.move=Vector3(sin(move_yaw),0,cos(move_yaw))*move_magnitude
	_navigation_tail(actor,s,cmd,bool(s.get("want_move",move.length_squared()>.01)))
	cmd.aim_dir=Vector3(sin(float(s.yaw))*cos(float(s.pitch)),sin(float(s.pitch)),cos(float(s.yaw))*cos(float(s.pitch)))
	var aim_distance:float=delta.length() if fighting else (1.6 if str(s.mode)=="refill" else 6.0)
	cmd.aim_point=actor.global_position+Vector3.UP*1.1+Vector3(cmd.aim_dir)*aim_distance
	if not fighting and Vector3(cmd.aim_point).y<actor.global_position.y:cmd.aim_point.y=actor.global_position.y

func _acquire(s:Dictionary) -> void:
	s.acq_time=0.0;s.acq_sign_y=(-1.0 if randf()<.5 else 1.0)*randf_range(.5,1.0);s.acq_sign_p=(randf()-.5)*1.2

func _wander(value:float) -> float:return sin(value)*.6+sin(value*2.27+1.3)*.4

func target_aim(ideal:Vector2,s:Dictionary,cfg:Dictionary,boss:bool=false) -> Vector2:
	var error:float=float(cfg.get("aimError",.06))*(.8 if boss else 1.0)
	var acquisition:float=exp(-float(s.get("acq_time",9))/maxf(.12,float(cfg.get("reaction",.32))*.9))
	var time:float=float(s.time)
	return ideal+Vector2(error*(.75*_wander(time*1.7+float(s.get("ph1",0)))+2.4*acquisition*float(s.get("acq_sign_y",0))),error*.6*(.75*_wander(time*2.1+float(s.get("ph2",0)))+1.6*acquisition*float(s.get("acq_sign_p",0))))

# Source _tail ordering: smoothing, water stopping distance, then hop/skip/replan.
func _navigation_tail(actor,s:Dictionary,cmd:Dictionary,want_move:bool) -> void:
	if float(s.get("move_magnitude",0))>.05 and actor.is_grounded():cmd.move=edge_guard(actor,cmd.move)
	var trying:bool=not s.path.is_empty() and want_move and not (actor.weapon_id=="charger" and actor.charge>0)
	if not trying:s.no_progress=0.0
	var stalled:float=float(s.get("no_progress",0))
	if stalled>.7 and float(s.get("jump_cooldown",0))<=0 and actor.is_grounded() and not near_water(actor,1.2):cmd.jump=true;s.jump_cooldown=1.0
	if stalled>1.5 and not s.path.is_empty() and int(s.path_index)<s.path.size()-1 and not bool(s.get("skipped",false)):
		s.path_index=int(s.path_index)+1;s.skipped=true;s.best_distance=INF
	if stalled>2.4:
		s.no_progress=0.0;s.skipped=false;s.path=PackedVector3Array();s.nav_ids=PackedInt32Array();s.goal_time=0.0;s.repath=0.0
	if float(s.get("no_progress",0))==0:s.skipped=false
	s.stuck=float(s.get("no_progress",0))
	if bool(s.get("need_jump",false)) and float(s.get("jump_cooldown",0))<=0 and actor.is_grounded():cmd.jump=true;s.jump_cooldown=.6;s.need_jump=false

func near_water(actor,radius:float) -> bool:
	for index in 8:
		var angle:float=float(index)*TAU/8.0
		if _wet(actor.global_position+Vector3(cos(angle),0,sin(angle))*radius):return true
	return false

func edge_guard(actor,move:Vector3) -> Vector3:
	var magnitude:float=Vector2(move.x,move.z).length()
	if magnitude<.0001:return move
	var direction:Vector3=move/magnitude
	var look:float=.6+Vector2(actor.velocity.x,actor.velocity.z).length()*.17
	if not _water_ahead(actor.global_position,direction,look):return move
	for angle in [.8,-.8,1.45,-1.45]:
		var rotated:=Vector3(direction.x*cos(angle)+direction.z*sin(angle),0,-direction.x*sin(angle)+direction.z*cos(angle))
		if not _water_ahead(actor.global_position,rotated,look):return rotated*magnitude
	return Vector3.ZERO

func _water_ahead(position:Vector3,direction:Vector3,look:float) -> bool:
	return _wet(position+direction*.45) or _wet(position+direction*look)

func _perceive(actor, awareness: float):
	var boss = match_node.get("boss")
	if is_instance_valid(boss) and not boss.get("dead"):
		return boss
	var best = null
	var score: float = INF
	var actors = match_node.get("actors")
	if not actors is Array:
		return null
	for other in actors:
		if other == actor or not other.alive or other.team_id == actor.team_id:
			continue
		var distance: float = actor.global_position.distance_to(other.global_position)
		if distance > awareness or (other.submerged and distance > 5.2):
			continue
		var from: Vector3 = actor.global_position + Vector3.UP * 1.0
		var to: Vector3 = other.global_position + Vector3.UP * 0.75
		var hit: Dictionary = match_node.call("cast", from, to, [actor.get_rid(), other.get_rid()])
		if not hit.is_empty() and Vector3(hit["position"]).distance_to(to) > 0.4:
			continue
		if distance < score:
			best = other
			score = distance
	return best

func _choose_goal(actor, s: Dictionary) -> void:
	if actor_nav and level_queries:
		_pick_paint_goal(actor,s);return
	var stage = match_node.get("stage")
	if not is_instance_valid(stage):
		return
	var best: Vector3 = actor.global_position
	var best_score: float = -INF
	var bounds = stage.get("bounds")
	for i in range(18):
		var radius: float = randf_range(7.0, 22.0)
		var angle: float = randf() * TAU
		var candidate: Vector3 = actor.global_position + Vector3(cos(angle), 0, sin(angle)) * radius
		if bounds is Dictionary:
			candidate.x = clampf(candidate.x, float(bounds.get("minX", -24.0)) + 1.5, float(bounds.get("maxX", 24.0)) - 1.5)
			candidate.z = clampf(candidate.z, float(bounds.get("minZ", -44.0)) + 1.5, float(bounds.get("maxZ", 44.0)) - 1.5)
		var height: float = float(stage.call("ground_height", candidate.x, candidate.z, actor.global_position.y + 1.8))
		if not is_finite(height) or height < -3.1:
			continue
		candidate.y = height
		var state: int = int(match_node.call("sample_ink", candidate, Vector3.UP))
		var value: float = (3.0 if state == -1 else (4.0 if state != actor.team_id else 0.0)) + randf() - actor.global_position.distance_to(candidate) * 0.03
		if actor.ink < 25.0:
			value = (5.0 if state == actor.team_id else 0.0) + randf()
		if value > best_score:
			best_score = value
			best = candidate
	s["goal_time"] = randf_range(2.0, 4.0)
	_set_path(actor,s,best)

func _pick_paint_goal(actor,s:Dictionary) -> void:
	var stage=match_node.get("stage")
	var pads:Array=stage.layout.spawnPads
	var raw:Array=pads[1-actor.team_id];var enemy:=Vector3(raw[0],raw[1],raw[2])
	raw=pads[actor.team_id];var own:=Vector3(raw[0],raw[1],raw[2])
	var total:float=own.distance_to(enemy)
	var best:int=-1;var highest:float=-INF
	for index in 16:
		var id:int=actor_nav.valid_ids[randi()%actor_nav.valid_ids.size()]
		if actor_nav.zones[id]>=0:continue
		var point:Vector3=actor_nav.point(id)
		var distance:float=Vector2(point.x-actor.global_position.x,point.z-actor.global_position.z).length()
		if distance>34:continue
		var stats:Dictionary=level_queries.region_stats(point,3.5,actor.team_id)
		if int(stats.n)==0:continue
		var progress:float=1-Vector2(point.x-enemy.x,point.z-enemy.z).length()/maxf(total,.01)
		var score:float=(float(stats.empty)+float(stats.enemy)*1.25)*12-distance*.18+clampf(progress,0,.8)*4+randf()*2.5
		for mate in match_node.get("actors"):
			if mate==actor or mate.team_id!=actor.team_id or not states.has(mate.get_instance_id()):continue
			var goal:Vector3=states[mate.get_instance_id()].goal
			if Vector2(point.x-goal.x,point.z-goal.z).length()<7:score-=4
		if score>highest:highest=score;best=id
	s.goal_time=randf_range(4,7)
	if best>=0:_set_path(actor,s,actor_nav.point(best),.3)

func _pick_refill(actor,s:Dictionary) -> void:
	if not profile_navigation:_pick_refill_source(actor,s);return
	var started:int=Time.get_ticks_usec()
	_pick_refill_source(actor,s)
	_profile_span("refill_us",started)

func _pick_refill_source(actor,s:Dictionary) -> void:
	if not level_queries:return
	var best:Vector3=Vector3.ZERO;var closest:float=INF
	for index in 14:
		var angle:float=randf()*TAU;var radius:float=randf_range(1,8)
		var point:Vector3=actor.global_position+Vector3(cos(angle),0,sin(angle))*radius
		var stats:Dictionary=level_queries.region_stats(point,1.2,actor.team_id)
		if int(stats.n)>0 and float(stats.own)>.6 and radius<closest:closest=radius;best=point
	if is_finite(closest):_set_path(actor,s,best,.4)
	else:s.path=PackedVector3Array()
	s.refill_repath=1.2

func _nearest_ink(actor) -> Vector3:
	for radius in [2.0, 4.0, 6.0]:
		for i in range(8):
			var angle: float = float(i) * TAU / 8.0
			var direction := Vector3(cos(angle), 0, sin(angle))
			if int(match_node.call("sample_ink", actor.global_position + direction * radius, Vector3.UP)) == actor.team_id:
				return direction
	return Vector3.ZERO

func _weapon_range(id: String) -> float:
	var w: Dictionary = Rules.weapon(id)
	match id:
		"roller": return 6.0
		"charger": return float(w.get("rangeMax", 27.0)) * 0.9
		"slosher": return 9.5
		_: return float(w.get("range", 12.5))
