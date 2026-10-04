class_name InkCatchStep
extends RefCounted
## Original standing settle steps for the temporary stance shift caused by
## repeated hits. Ordinary locomotion and its world contact policy stay separate.
static var _parameters:Dictionary={}
var _feet:Array[Dictionary]=[]
var _bones:=PackedInt32Array()
var _stance:=PackedFloat32Array()
var _last_revision:=0
var _cooldown:=0.0
var active:=false
var touchdown_count:=0
var maximum_lift:=0.0

func configure(rig:Skeleton3D) -> void:
	if _parameters.is_empty():_parameters=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/motion_parameters.json"))
	_bones=PackedInt32Array([rig.find_bone("footL"),rig.find_bone("footR")])
	_stance=PackedFloat32Array(_parameters.idle_stance)

func step(dt:float,rig:Skeleton3D,actor:Transform3D,ground:Callable,hit:InkHitResponse,velocity:Vector3,hold:Dictionary,aim_weight:float,enabled:bool=true) -> Array[Dictionary]:
	var targets:Array[Dictionary]=[]
	if not enabled or velocity.length()>.62:
		active=false
		_feet.clear()
		return targets
	var preset:Array=hold.get("stance",_parameters.idle_stance)
	var idle:Array=_parameters.idle_stance
	for i:int in 6:
		_stance[i]=lerpf(_stance[i],lerpf(float(idle[i]),float(preset[i]),aim_weight),1.0-exp(-dt*9.0))
	if not active and hit.stagger_revision>_last_revision and hit.stagger_time<1.5:
		_capture(rig)
		_last_revision=hit.stagger_revision
		active=true
		_cooldown=0.0
	if not active:return targets
	var yaw:=atan2(actor.basis.z.x,actor.basis.z.z)
	var swinging:=0
	for i:int in 2:
		var foot:Dictionary=_feet[i]
		if not bool(foot.swing):continue
		foot.phase=minf(1.0,float(foot.phase)+dt/float(foot.duration))
		var goal:=_ideal(i,actor.origin,yaw,hit.step_offset,ground)
		foot.to=goal.position
		foot.toYaw=goal.yaw
		if float(foot.phase)>=1.0:
			foot.pw=foot.to
			foot.yaw=foot.toYaw
			foot.swing=false
			foot.planted=true
			foot.phase=0.0
			_cooldown=.045
			touchdown_count+=1
		else:
			swinging+=1
	_cooldown-=dt
	if swinging==0 and _cooldown<=0.0:
		var errors:=Vector2.ZERO
		for i:int in 2:
			var goal:=_ideal(i,actor.origin,yaw,hit.step_offset,ground)
			var foot:Dictionary=_feet[i]
			var current:Vector3=foot.pw
			var desired:Vector3=goal.position
			errors[i]=Vector2(current.x-desired.x,current.z-desired.z).length()+.11*absf(wrapf(float(foot.yaw)-float(goal.yaw),-PI,PI))
		var worst:=0 if errors.x>=errors.y else 1
		var error:=maxf(errors.x,errors.y)
		if error>.068:
			var goal:=_ideal(worst,actor.origin,yaw,hit.step_offset,ground)
			start_settle(_feet[worst],goal.position,float(goal.yaw),error)
	for foot:Dictionary in _feet:
		var posed:=pose_foot(foot)
		if not bool(foot.swing):foot.pitch=posed.pitch
		maximum_lift=maxf(maximum_lift,float(posed.position.y)-(foot.from as Vector3).y)
		targets.append({"position":ankle_position(posed.position,float(posed.yaw),float(posed.pitch)),"rotation":Basis.from_euler(Vector3(float(posed.pitch),float(posed.yaw),0),EULER_ORDER_YXZ).get_rotation_quaternion(),"planted":bool(foot.planted)})
	if swinging==0 and hit.stagger_time>1.5 and hit.step_offset.length()<.015:
		active=false
	return targets

func _capture(rig:Skeleton3D) -> void:
	_feet.clear()
	rig.force_update_all_bone_transforms()
	for index:int in _bones:
		var transform:=rig.global_transform*rig.get_bone_global_pose(index)
		var rotation:=transform.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		var contact:=transform.origin-ankle_position(Vector3.ZERO,rotation.y,rotation.x)
		_feet.append({"pw":contact,"yaw":rotation.y,"pitch":rotation.x,"swing":false,"planted":true,"phase":0.0,"duration":.2,"lift":0.0,"from":contact,"to":contact,"fromYaw":rotation.y,"toYaw":rotation.y,"toe":.25,"land":.12})

func _ideal(index:int,root:Vector3,yaw:float,shift:Vector2,ground:Callable) -> Dictionary:
	var base:=index*3
	var x:=_stance[base]+shift.x
	var z:=_stance[base+1]+shift.y
	var position:=Vector3(root.x+x*cos(yaw)+z*sin(yaw),root.y,root.z-x*sin(yaw)+z*cos(yaw))
	if ground.is_valid():
		var height:=float(ground.call(position.x,position.z,root.y+.45))
		if is_finite(height):position.y=height
	return {"position":position,"yaw":yaw+_stance[base+2]}

static func start_settle(foot:Dictionary,goal:Vector3,yaw:float,error:float) -> void:
	foot.planted=false
	foot.swing=true
	foot.phase=0.0
	foot.from=foot.pw
	foot.fromYaw=foot.yaw
	foot.to=goal
	foot.toYaw=yaw
	foot.duration=clampf(.15+error*.42,.15,.3)
	foot.lift=clampf(.028+error*.22,.03,.085)+maxf(0.0,goal.y-(foot.from as Vector3).y)
	foot.toe=.25
	foot.land=.12

static func pose_foot(foot:Dictionary,run_weight:float=0.0) -> Dictionary:
	if bool(foot.planted) or not bool(foot.swing):
		return {"position":foot.pw,"yaw":float(foot.yaw),"pitch":float(foot.pitch)*exp(-12.0/60.0)}
	var u:float=foot.phase
	var jerk:=u*u*u*(10.0+u*(6.0*u-15.0))
	var ease:=lerpf(u,jerk,.8)
	var from:Vector3=foot.from
	var to:Vector3=foot.to
	var rise:=maxf(0.0,to.y-from.y)
	var gy:=lerpf(from.y,to.y,smoothstep(.15,.7,u))
	var peak:=lerpf(.5,.4,run_weight)
	var lift_curve:=sin(u/peak*PI*.5) if u<peak else cos((u-peak)/(1.0-peak)*PI*.5)
	var position:=Vector3(lerpf(from.x,to.x,ease),gy+(float(foot.lift)+rise*.6)*pow(maxf(0.0,lift_curve),1.15),lerpf(from.z,to.z,ease))
	var yaw:=float(foot.fromYaw)+wrapf(float(foot.toYaw)-float(foot.fromYaw),-PI,PI)*ease
	var pitch:=float(foot.toe)*(1.0-smoothstep(0.0,.5,u))-float(foot.land)*smoothstep(.55,.96,u)+.12*sin(PI*u)*run_weight
	return {"position":position,"yaw":yaw,"pitch":pitch}

static func ankle_position(contact:Vector3,yaw:float,pitch:float) -> Vector3:
	var ankle:float=_parameters.get("ankle_height",.085)
	var ball:float=_parameters.get("ball_z",.11)
	var heel:float=_parameters.get("heel_z",.065)
	var ay:=ankle*cos(pitch)+(ball if pitch>=0.0 else -heel)*sin(pitch)
	var az:=ball+ankle*sin(pitch)-ball*cos(pitch) if pitch>=0.0 else -heel+ankle*sin(pitch)+heel*cos(pitch)
	return contact+Quaternion(Vector3.UP,yaw)*Vector3(0,ay,az)
