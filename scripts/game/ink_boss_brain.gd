class_name InkBossBrain
extends RefCounted

## Source BossBrain idle/attention/footprint steering. Attack records stay on InkBoss for replication.
const SPEED:Array=[0.0,2.9,3.3,3.8]
const TURN:Array=[0.0,1.25,1.45,1.75]
const PREF:Array=[0.0,10.0,9.0,8.0]
var boss
var nav:InkBossNav
var target=null
var retarget:float=0.0
var attention:Dictionary={}
var damage_by:Dictionary={}
var plan:Dictionary={}
var goal:Vector2
var goal_time:float=0.0
var path:PackedVector2Array
var path_index:int=0
var speed:float=0
var stuck:float=0
var home:Vector2
var force:String=""

func configure(entity,navigation:InkBossNav)->void:
	boss=entity;nav=navigation;home=Vector2(boss.global_position.x,boss.global_position.z)

func tick(dt:float)->void:
	for key in damage_by:damage_by[key]=float(damage_by[key])*exp(-dt/8.0)

func note_damage(actor,amount:float)->void:
	if is_instance_valid(actor):
		var key:int=actor.get_instance_id()
		damage_by[key]=float(damage_by.get(key,0))+amount

func pick_target()->void:
	retarget=randf_range(3,5.5)
	var highest:float=-INF
	target=null
	for actor in boss.match_node.get("actors"):
		if not actor.alive or actor.team_id!=0 or not actor.super_jump_state.is_empty() or nav.in_pad(actor.global_position.x,actor.global_position.z,3):continue
		var key:int=actor.get_instance_id()
		var distance:float=Vector2(actor.global_position.x-boss.global_position.x,actor.global_position.z-boss.global_position.z).length()
		var score:float=-distance*.1+float(damage_by.get(key,0))*.004-float(attention.get(key,0))*1.4+randf()*1.3
		if score>highest:highest=score;target=actor
	for key in attention:attention[key]=float(attention[key])*.8
	if is_instance_valid(target):
		var key:int=target.get_instance_id()
		attention[key]=float(attention.get(key,0))+1

func choose(actor)->Dictionary:
	var point:Vector3=boss.global_position+boss.global_basis.z*2
	var distance:float=Vector2(actor.global_position.x-point.x,actor.global_position.z-point.z).length()
	var close:int=0;var distant:int=0
	for unit in boss.match_node.get("actors"):
		if not unit.alive or unit.team_id!=0 or nav.in_pad(unit.global_position.x,unit.global_position.z,1):continue
		var d:float=Vector2(unit.global_position.x-boss.global_position.x,unit.global_position.z-boss.global_position.z).length()
		if d<10.5:close+=1
		if d>13:distant+=1
	var yaw:float=atan2(actor.global_position.x-boss.global_position.x,actor.global_position.z-boss.global_position.z)
	var lane:Dictionary=boss._lane(yaw)
	var weights:Array=[["slam",3.0+float(close)*.6 if distance<11 else .25],["barrage",1.3+float(distant)*.45+(1.0 if distance>12 else 0.0)],["sweep",2.1 if distance>5 and distance<17 else .4],["charge",(2.2 if distance>5.5 else 1.2) if not lane.is_empty() else 0.0]]
	if boss.phase>=2 and float(boss._move_cooldowns.crablets)<=0 and boss._crablets.size()<3:weights.append(["crablets",2.4])
	if boss.phase>=3 and float(boss._move_cooldowns.frenzy)<=0:weights.append(["frenzy",1.1+float(close)*.9])
	var total:float=0
	for weight in weights:
		if weight[0]==boss._last_move:weight[1]=float(weight[1])*.3
		total+=float(weight[1])
	var choice:float=randf()*total
	var id:String="barrage"
	for weight in weights:
		choice-=float(weight[1])
		if choice<=0:id=str(weight[0]);break
	if not force.is_empty():id=force;force=""
	if id=="charge" and lane.is_empty():id="barrage"
	return {"id":id,"face":yaw if id in ["slam","sweep"] else (float(lane.yaw) if id=="charge" else null),"lane":lane,"time":0.0}

func idle(dt:float)->void:
	retarget-=dt;goal_time-=dt;boss._wait-=dt
	if retarget<=0 or not is_instance_valid(target) or not target.alive:pick_target()
	if boss._wait<=0 and is_instance_valid(target):
		if plan.is_empty():plan=choose(target)
		plan.time=float(plan.time)+dt
		if plan.face==null:
			boss._start_move(str(plan.id));plan.clear();speed=0;path.clear();return
		var want:float=float(plan.face)
		if plan.id in ["slam","sweep"]:want=atan2(target.global_position.x-boss.global_position.x,target.global_position.z-boss.global_position.z)
		var difference:float=wrapf(want-boss.rotation.y,-PI,PI)
		if absf(difference)<.16 or (plan.id!="charge" and float(plan.time)>1.2 and absf(difference)<.6):
			boss._start_move(str(plan.id));plan.clear();speed=0;path.clear();return
		if not turn(want,dt) or float(plan.time)>2.4:boss._last_move=str(plan.id);plan.clear();boss._wait=.3
		speed=0;return
	walk(dt)

func turn(want:float,dt:float)->bool:
	var difference:float=wrapf(want-boss.rotation.y,-PI,PI)
	if absf(difference)<.001:return true
	var yaw:float=boss.rotation.y+clampf(difference,-float(TURN[boss.phase])*dt,float(TURN[boss.phase])*dt)
	var point:Vector3=boss.global_position
	if nav.turn_ok(point.x,point.z,yaw):boss.rotation.y=yaw;return true
	var radius:float=float(SPEED[boss.phase])*.55*dt
	var highest:float=nav.wall_clear(point.x,point.z)+minf(nav.floor_clear(point.x,point.z),3)*.5+.001
	var best:Vector2=Vector2.INF
	for index in 8:
		var angle:float=float(index)/8.0*TAU
		var candidate:Vector2=Vector2(point.x+sin(angle)*radius,point.z+cos(angle)*radius)
		if not nav.turn_ok(candidate.x,candidate.y,boss.rotation.y):continue
		var score:float=nav.wall_clear(candidate.x,candidate.y)+minf(nav.floor_clear(candidate.x,candidate.y),3)*.5
		if score>highest:highest=score;best=candidate
	if not best.is_finite():return false
	boss.global_position.x=best.x;boss.global_position.z=best.y
	if nav.turn_ok(best.x,best.y,yaw):boss.rotation.y=yaw
	return true

func pick_goal()->void:
	goal_time=randf_range(3,5.5)
	var best:Vector2=Vector2.INF
	var highest:float=-INF
	for index in 16:
		var point:Vector2=nav.random_point()
		var score:float=minf(nav.wall_clear(point.x,point.y),6)*.7+minf(nav.floor_clear(point.x,point.y),4)*.4-point.distance_to(Vector2(boss.global_position.x,boss.global_position.z))*.07+randf()*1.5
		if is_instance_valid(target):score-=absf(point.distance_to(Vector2(target.global_position.x,target.global_position.z))-float(PREF[boss.phase]))
		else:score-=point.distance_to(home)*.2
		if point.distance_to(Vector2(float(nav.pads[0].x),float(nav.pads[0].z)))<18:score-=12
		if score>highest:highest=score;best=point
	if not best.is_finite():return
	goal=best;path=nav.find_path(Vector2(boss.global_position.x,boss.global_position.z),best);path_index=1

func walk(dt:float)->void:
	if goal_time<=0 or path.is_empty() or (path_index>=path.size() and goal_time<1.5):pick_goal()
	var want:float=boss.rotation.y
	var go:bool=false
	if path_index<path.size():
		var point:Vector2=path[path_index]
		var position:Vector2=Vector2(boss.global_position.x,boss.global_position.z)
		while position.distance_to(point)<1.1 and path_index<path.size()-1:path_index+=1;point=path[path_index]
		if path_index>=path.size()-1 and position.distance_to(point)<1.1:path_index=path.size()
		else:want=atan2(point.x-position.x,point.y-position.y);go=true
	if not go and is_instance_valid(target):want=atan2(target.global_position.x-boss.global_position.x,target.global_position.z-boss.global_position.z)
	var difference:float=wrapf(want-boss.rotation.y,-PI,PI)
	turn(want,dt)
	var maximum:float=float(SPEED[boss.phase])*(clampf(1-absf(difference)/.9,0,1) if go else 0.0)
	speed+=clampf(maximum-speed,-4*dt,3*dt)
	if speed>.01:
		var point:Vector3=boss.global_position+boss.global_basis.z*speed*dt
		if nav.pose_ok(point.x,point.z,boss.rotation.y):boss.global_position=point;stuck=0
		else:
			speed=0;stuck+=dt
			if stuck>.8:stuck=0;goal_time=0;path.clear()
