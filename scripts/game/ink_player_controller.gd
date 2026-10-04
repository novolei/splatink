class_name InkPlayerController
extends RefCounted

# Production Player.js: camera-centre targeting, body-axis convergence and
# radial gamepad response. The overhead map never becomes the gameplay ray.
var game:Node
var on_target:Node=null
var in_range:bool=false
var pad_look:Vector2=Vector2.ZERO
var edge_time:float=0.0
var last_device:String="kbm"
var assist:Dictionary={"has":false,"target":null,"yaw":0.0,"pitch":0.0}
var mouse_delta:Vector2=Vector2.ZERO
var mouse_active:bool=false

func configure(owner:Node)->void:game=owner

func reset()->void:
	on_target=null;in_range=false;pad_look=Vector2.ZERO;edge_time=0.0
	assist={"has":false,"target":null,"yaw":0.0,"pitch":0.0};mouse_delta=Vector2.ZERO;mouse_active=false

func queue_mouse(delta:Vector2)->void:
	mouse_delta+=delta;last_device="kbm"

func apply_mouse(delta:Vector2)->void:
	# Native physics stays fixed at 60 Hz. Raw mouse look must reach the render
	# camera immediately instead of waiting for the next physical actor tick.
	var settings:Dictionary=game.get("settings")
	var friction:float=lerpf(1.0,.58,float(assist.get("closeness",0.0))*float(assist.get("strength",0.0))) if bool(assist.get("has",false)) else 1.0
	var sensitivity:float=.0021*float(settings.get("sensitivity",1.0))*(friction if bool(settings.get("aimAssistMouse",false)) else 1.0)
	game.set("_yaw",float(game.get("_yaw"))-delta.x*sensitivity)
	game.set("_pitch",clampf(float(game.get("_pitch"))-delta.y*sensitivity*(-1.0 if bool(settings.get("invertY",false)) else 1.0),-1.05,1.15))
	last_device="kbm";mouse_active=mouse_active or not delta.is_zero_approx();mouse_delta=Vector2.ZERO

static func radial_stick(raw:Vector2,dead_zone:float,outer:float)->Vector2:
	var magnitude:float=raw.length()
	if magnitude<=dead_zone:return Vector2.ZERO
	return raw/magnitude*minf(1.0,(magnitude-dead_zone)/(outer-dead_zone))

static func look_curve(magnitude:float)->float:
	return .62*pow(magnitude/.75,1.6) if magnitude<.75 else .62+(magnitude-.75)/.25*.38

func update(dt:float,input:Dictionary)->Dictionary:
	var actor=game.get("local_player")
	var settings:Dictionary=game.get("settings")
	var has_pad:bool=bool(input.get("has_pad",false))
	var raw_left:Vector2=input.get("left",Vector2.ZERO)
	var raw_right:Vector2=input.get("right",Vector2.ZERO)
	if maxf(maxf(absf(raw_left.x),absf(raw_left.y)),maxf(absf(raw_right.x),absf(raw_right.y)))>.3:last_device="pad"
	var strength:float=float(settings.get("aimAssist",1.0)) if has_pad and last_device=="pad" else (.5 if bool(settings.get("aimAssistMouse",false)) else 0.0)
	var candidate:Dictionary=assist_target(strength)
	var friction:float=lerpf(1.0,.58,float(candidate.closeness)*float(candidate.strength)) if not candidate.is_empty() else 1.0
	var inverse:float=-1.0 if bool(settings.get("invertY",false)) else 1.0
	var map_up:bool=bool(input.get("map_up",false))
	var mouse:Vector2=Vector2.ZERO if map_up else mouse_delta
	mouse_delta=Vector2.ZERO
	var yaw:float=float(game.get("_yaw"));var pitch:float=float(game.get("_pitch"))
	var look_active:bool=mouse_active and not map_up
	mouse_active=false
	if not mouse.is_zero_approx():
		var sensitivity:float=.0021*float(settings.get("sensitivity",1.0))*(friction if bool(settings.get("aimAssistMouse",false)) else 1.0)
		yaw-=mouse.x*sensitivity;pitch-=mouse.y*sensitivity*inverse;look_active=true
	if has_pad and not map_up:
		var stick:Vector2=radial_stick(raw_right,.11,.96)
		var magnitude:float=stick.length()
		edge_time=minf(.5,edge_time+dt) if magnitude>.93 else maxf(0.0,edge_time-dt*3.0)
		var boost:float=1.0+.55*clampf((edge_time-.16)/.3,0.0,1.0)
		var response:float=look_curve(magnitude)/magnitude if magnitude>0.0 else 0.0
		pad_look=pad_look.lerp(stick*response,1.0-exp(-60.0*dt))
		look_active=look_active or magnitude>0.0
		yaw-=pad_look.x*3.6*float(settings.get("padSensitivity",1.0))*boost*friction*dt
		pitch-=pad_look.y*2.4*float(settings.get("padSensitivity",1.0))*friction*dt*inverse
	var movement:Vector2=input.get("move",Vector2.ZERO)
	if has_pad:movement+=radial_stick(raw_left,.14,.95)
	var magnitude:float=movement.length()
	movement=movement.limit_length(1.0)
	if not candidate.is_empty() and bool(candidate.prev_valid) and (look_active or magnitude>.2 or bool(actor._prev.get("fire",false))):
		var share:float=.42*float(candidate.strength)*float(candidate.closeness)
		yaw+=wrapf(float(candidate.yaw)-float(candidate.prev_yaw),-PI,PI)*share
		pitch+=(float(candidate.pitch)-float(candidate.prev_pitch))*share*.7
	pitch=clampf(pitch,-1.05,1.15)
	game.set("_yaw",yaw);game.set("_pitch",pitch)
	var forward:=Vector3(sin(yaw),0,cos(yaw));var right:=Vector3(-cos(yaw),0,sin(yaw))
	var point:Vector3=compute_aim()
	return {"move":right*movement.x-forward*movement.y,"aim_yaw":yaw,"aim_pitch":pitch,"aim_point":point,"aim_dir":(point-actor.global_position-Vector3.UP*1.05).normalized()}

func assist_target(strength:float)->Dictionary:
	var actor=game.get("local_player")
	var rig=game.get("camera_rig")
	var camera:Camera3D=rig.get("aim_camera") if is_instance_valid(rig) else game.get("camera")
	if strength<=0.0 or not is_instance_valid(camera) or not is_instance_valid(actor):
		assist.has=false;assist.target=null;return {}
	var direction:Vector3=-camera.global_basis.z
	var weapon:Dictionary=InkRules.weapon(str(actor.get("weapon_id")))
	var kind:String=str(weapon.get("kind",actor.get("weapon_id")))
	var effective:float=float(weapon.get("rangeMax",12.0)) if kind=="charger" else (7.0 if kind=="roller" else float(weapon.get("range",12.0)))
	var maximum:float=minf(32.0,effective*1.15+2.0)
	var best:Node=null;var best_score:float=INF;var best_yaw:float=0.0;var best_pitch:float=0.0;var closeness:float=0.0
	for enemy in game.get("actors"):
		if enemy.team_id==actor.team_id or not enemy.alive or enemy.submerged or enemy.invuln>0.0:continue
		var center:Vector3=enemy.visual_position()+Vector3.UP*(.3 if enemy.form=="squid" else .95)
		var vector:Vector3=center-camera.global_position;var distance:float=vector.length()
		if distance>maximum+4.0 or distance<.5 or actor.global_position.distance_to(enemy.global_position)>maximum:continue
		vector/=distance
		var angle:float=acos(clampf(vector.dot(direction),-1.0,1.0))
		var cone:float=clampf(atan2(1.0,distance),deg_to_rad(2.5),deg_to_rad(10.0))
		if angle>cone:continue
		if not actor.controller_cast(camera.global_position,center-vector*.05,true).is_empty():continue
		var score:float=angle/cone+distance*.01
		if score<best_score:
			best_score=score;best=enemy;best_yaw=atan2(vector.x,vector.z);best_pitch=asin(clampf(vector.y,-1.0,1.0));closeness=1.0-angle/cone
	if not is_instance_valid(best):assist.has=false;assist.target=null;return {}
	assist.prev_valid=bool(assist.has) and assist.target==best
	assist.prev_yaw=assist.yaw;assist.prev_pitch=assist.pitch
	assist.target=best;assist.yaw=best_yaw;assist.pitch=best_pitch
	assist.closeness=clampf(closeness*1.3,0.0,1.0);assist.strength=strength;assist.has=true
	return assist

func compute_aim()->Vector3:
	var actor=game.get("local_player")
	if not is_instance_valid(actor):on_target=null;in_range=false;return Vector3.ZERO
	var rig=game.get("camera_rig")
	var camera:Camera3D=rig.get("aim_camera") if is_instance_valid(rig) else game.get("camera")
	var direction:Vector3=-camera.global_basis.z
	var along:float=maxf(0.0,(actor.global_position+Vector3.UP*1.3-camera.global_position).dot(direction))
	var start:Vector3=camera.global_position+direction*along
	var hit:Dictionary=actor.controller_cast(start,start+direction*70.0,true)
	var distance:float=start.distance_to(hit.position) if not hit.is_empty() else 70.0
	var point:Vector3=start+direction*distance
	on_target=null
	var best:float=distance;var reach:float=minf(distance,34.0)
	var finish:Vector3=start+direction*reach
	for enemy in game.get("actors"):
		if enemy.team_id==actor.team_id or not enemy.alive or enemy.submerged:continue
		var result:Vector2=segment_capsule_distance(start,finish,enemy.visual_position(),.38,.55 if enemy.form=="squid" else 1.45)
		if result.y<.58 and result.x*reach<best:best=result.x*reach;on_target=enemy
	var boss=game.get("boss")
	if is_instance_valid(boss):
		var boss_distance:float=boss.ray_distance(start,direction,best)
		if boss_distance>0.0 and boss_distance<best:on_target=boss;point=start+direction*boss_distance
	if is_instance_valid(on_target) and on_target!=boss:
		var height:float=.55 if on_target.get("form")=="squid" else 1.45
		var base:Vector3=on_target.call("visual_position")
		point=Vector3(base.x,clampf(start.y+direction.y*best,base.y+.2,base.y+height-.12),base.z)
	var weapon:Dictionary=InkRules.weapon(str(actor.get("weapon_id")))
	var kind:String=str(weapon.get("kind",actor.get("weapon_id")))
	var effective:float=float(weapon.get("rangeMax",12.0)) if kind=="charger" else (6.0 if kind=="roller" else float(weapon.get("range",12.0)))
	in_range=point.distance_to(actor.global_position)<=effective+.5
	actor.set("aim_point",point)
	return point

static func point_capsule_distance(point:Vector3,base:Vector3,radius:float,height:float)->float:
	var y:float=clampf(point.y,base.y+radius,base.y+maxf(radius,height-radius))
	return point.distance_to(Vector3(base.x,y,base.z))

static func segment_capsule_distance(begin:Vector3,end:Vector3,base:Vector3,radius:float,height:float)->Vector2:
	var best:float=INF;var best_t:float=0.0
	for i in 7:
		var t:float=float(i)/6.0
		var distance:float=point_capsule_distance(begin.lerp(end,t),base,radius,height)
		if distance<best:best=distance;best_t=t
	var low:float=maxf(0.0,best_t-1.0/6.0);var high:float=minf(1.0,best_t+1.0/6.0)
	for i in 8:
		var m1:float=low+(high-low)/3.0;var m2:float=high-(high-low)/3.0
		if point_capsule_distance(begin.lerp(end,m1),base,radius,height)<point_capsule_distance(begin.lerp(end,m2),base,radius,height):high=m2
		else:low=m1
	var t:float=(low+high)*.5
	return Vector2(t,point_capsule_distance(begin.lerp(end,t),base,radius,height))
