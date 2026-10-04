class_name InkHitResponse
extends RefCounted
## Source Character.trigger('hit') spring impulses. This additive visual layer
## preserves the current locomotion, aim and independent attacks.
enum Channel {PITCH,ROLL,YAW,PELVIS,HEAD_PITCH,HEAD_ROLL,CLAVICLE,STAGGER,SQ_PITCH,SQ_Y,WEAPON_PITCH,EAR_LEFT,EAR_RIGHT,GRIP}
const SPRINGS := [Vector2(3.4,.38),Vector2(3.4,.38),Vector2(3.4,.42),Vector2(3.4,.42),Vector2(3.2,.4),Vector2(3.2,.4),Vector2(3.5,.45),Vector2(2.2,.5),Vector2(4.0,.35),Vector2(5.0,.3),Vector2(2.6,.32),Vector2(3.6,.2),Vector2(3.6,.2),Vector2(5.2,.42)]
var values := PackedFloat32Array()
var direction := Vector2(0.0,1.0)
var amplitude := 1.0
var accumulated := 0.0
var stagger_time := 99.0
var stagger_revision:=0
var step_offset := Vector2.ZERO
var active := false
var random_source := Callable()
var _bones:Dictionary={}

func _init() -> void:
	values.resize(SPRINGS.size()*2)

func configure(rig:Skeleton3D) -> void:
	for name:String in ["hips","spine","chest","neck","head","clavL","clavR","uArmL","uArmR","earL","earR"]:
		_bones[name]=rig.find_bone(name)
	for finger:String in ["index","middle","ring","pinky"]:
		for segment:int in [1,2]:
			var name:="handR_"+finger+str(segment)
			_bones[name]=rig.find_bone(name)

func trigger(arg:Variant=null,kid:bool=true) -> Vector3:
	var x:=0.0
	var z:=1.0
	var amp:=1.0
	if arg is Dictionary:
		x=float(arg.get("x",0.0))
		z=float(arg.get("z",0.0))
		var length:=Vector2(x,z).length()
		if length>.0001:
			x/=length
			z/=length
		else:
			z=1.0
		amp=clampf(float(arg.get("amount",arg.get("amp",1.0))),.3,1.6)
	elif arg is float or arg is int:
		x=((float(random_source.call()) if random_source.is_valid() else randf())-.5)*1.2
		amp=clampf(float(arg),.3,1.4)
	else:
		x=((float(random_source.call()) if random_source.is_valid() else randf())-.5)*1.2
	direction=Vector2(x,z)
	amplitude=amp
	accumulated+=amp
	_impulse(Channel.PITCH,-z*6.5*amp)
	_impulse(Channel.ROLL,x*6.5*amp)
	_impulse(Channel.YAW,x*5.0*amp)
	_impulse(Channel.PELVIS,-.5*amp)
	_impulse(Channel.HEAD_PITCH,-z*7.5*amp)
	_impulse(Channel.HEAD_ROLL,x*7.0*amp)
	_impulse(Channel.CLAVICLE,3.5*amp)
	_impulse(Channel.WEAPON_PITCH,-2.0*amp)
	_impulse(Channel.EAR_LEFT,(4.0+3.0*x)*amp)
	_impulse(Channel.EAR_RIGHT,(4.0-3.0*x)*amp)
	_impulse(Channel.GRIP,3.0*amp)
	if accumulated>2.6 and stagger_time>.9:
		stagger_time=0.0
		stagger_revision+=1
		accumulated=0.0
		step_offset=Vector2(-.1*x,-.16*z)
		_impulse(Channel.STAGGER,-2.5)
	if not kid:
		_impulse(Channel.SQ_PITCH,5.0*amp)
		_impulse(Channel.SQ_Y,-3.0*amp)
	active=true
	# Original _hairKick input is independent of damage amplitude.
	return Vector3(x*1.5,1.2,-z*1.8)

func _impulse(channel:int,velocity:float) -> void:
	values[channel*2+1]+=velocity

func step(dt:float,dry_squid:bool=false,kid_visible:bool=true) -> void:
	var delta:=clampf(dt,0.0,.1)
	stagger_time+=delta
	accumulated=maxf(0.0,accumulated-delta*1.4)
	step_offset*=exp(-delta*2.2)
	if not active:return
	var magnitude:=0.0
	for channel:int in SPRINGS.size():
		var squid_channel:bool=channel in [Channel.SQ_PITCH,Channel.SQ_Y]
		if (squid_channel and not dry_squid) or (not squid_channel and not kid_visible):
			magnitude+=values[channel*2]*values[channel*2]+values[channel*2+1]*values[channel*2+1]
			continue
		var w:float=TAU*SPRINGS[channel].x
		var k:float=w*w
		var damping:float=2.0*SPRINGS[channel].y*w
		var index:=channel*2
		var x:=values[index]
		var velocity:=values[index+1]
		var count:=maxi(1,ceili(delta*w*1.1))
		var h:=delta/float(count)
		for substep:int in count:
			velocity+=(-k*x-damping*velocity)*h
			x+=velocity*h
		values[index]=x
		values[index+1]=velocity
		magnitude+=x*x+velocity*velocity
	active=magnitude>.0000000001

func sample(channel:int) -> float:
	return values[channel*2]

func apply(rig:Skeleton3D,hat:int=0,head_parameters:Array[Node3D]=[]) -> void:
	if not active:return
	var hp:=sample(Channel.PITCH)
	var roll:=sample(Channel.ROLL)
	var yaw:=sample(Channel.YAW)
	var old_head_local:=rig.get_bone_pose_rotation(int(_bones.head))
	var old_head_global:=rig.get_bone_global_pose(int(_bones.head)).basis.orthonormalized()
	var head_parent:int=rig.get_bone_parent(int(_bones.head))
	var old_parent:=rig.get_bone_global_pose(head_parent).basis.orthonormalized().get_rotation_quaternion()
	_offset(rig,"hips",Vector3(hp*.2,0.0,0.0))
	_offset(rig,"spine",Vector3(hp*.5,yaw*.5,roll*.5))
	_offset(rig,"chest",Vector3(hp*.6,yaw*.6,roll*.5))
	var hips_index:int=_bones.hips
	var hips:=rig.get_bone_pose_position(hips_index)
	hips.y+=clampf(sample(Channel.PELVIS),-.2,.08)-absf(hp)*.08
	hips.z+=hp*.04+sample(Channel.STAGGER)*.05
	rig.set_bone_pose_position(hips_index,hips)
	var clav:=sample(Channel.CLAVICLE)
	_offset(rig,"clavL",Vector3(0,0,clav*.12))
	_offset(rig,"clavR",Vector3(0,0,-clav*.12))
	_offset(rig,"uArmL",Vector3(0,0,-clav*.08))
	_offset(rig,"uArmR",Vector3(0,0,clav*.08))
	var head_pitch:=sample(Channel.HEAD_PITCH)
	var head_roll:=sample(Channel.HEAD_ROLL)
	rig.force_update_all_bone_transforms()
	var parent_basis:=rig.get_bone_global_pose(head_parent).basis.orthonormalized()
	if head_parameters.size()==3 and head_parameters[0]!=null:
		var fk_values:Vector3=head_parameters[0].position
		var look_values:Vector3=head_parameters[1].position
		var torso_values:Vector3=head_parameters[2].position
		var base:=solve_head(fk_values,look_values,torso_values,old_parent)
		var hit:=solve_head(fk_values,look_values,torso_values,parent_basis.get_rotation_quaternion(),hp,roll,head_pitch,head_roll)
		# Apply only the source reaction difference, retaining the accepted
		# inertialized base look rather than restarting its blended head pose.
		rig.set_bone_pose_rotation(int(_bones.head),(old_head_local*base.inverse()*hit).normalized())
	else:
		# Compatibility for an imported body predating its source parameter tracks.
		var fk:=Basis.from_euler(Basis(old_head_local).get_euler(EULER_ORDER_YXZ)+Vector3(head_pitch*.5,0,head_roll*.4),EULER_ORDER_YXZ).get_rotation_quaternion()
		var target:=Basis.from_euler(old_head_global.get_euler(EULER_ORDER_YXZ)+Vector3(head_pitch*.65+hp*.52,0,head_roll*.4+roll*.35),EULER_ORDER_YXZ)
		var stabilized:=(rig.get_bone_rest(int(_bones.head)).basis.inverse()*parent_basis.inverse()*target).get_rotation_quaternion()
		rig.set_bone_pose_rotation(int(_bones.head),fk.slerp(stabilized,.82))
	var ear_rest:=-.35 if hat==3 else -.3 if hat==1 else 0.0
	var ear_lo:=ear_rest-.3 if not is_zero_approx(ear_rest) else -.45
	var ear_hi:=ear_rest+.08 if not is_zero_approx(ear_rest) else .35
	_ear(rig,"earL",sample(Channel.EAR_LEFT),1.0,ear_lo,ear_hi)
	_ear(rig,"earR",sample(Channel.EAR_RIGHT),-1.0,ear_lo,ear_hi)
	var grip:=clampf(sample(Channel.GRIP)*.05,-.2,.14)
	for finger:String in ["index","middle","ring","pinky"]:
		_offset(rig,"handR_"+finger+"1",Vector3(0,0,grip))
		_offset(rig,"handR_"+finger+"2",Vector3(0,0,grip*1.3))

static func solve_head(fk:Vector3,look:Vector3,torso:Vector3,parent:Quaternion,hit_pitch:float=0.0,hit_roll:float=0.0,head_pitch:float=0.0,head_roll:float=0.0) -> Quaternion:
	var e:=fk+Vector3(head_pitch*.5,0,head_roll*.4)
	var local_fk:=Basis.from_euler(e,EULER_ORDER_YXZ).get_rotation_quaternion()
	var look_pitch:=look.x-head_pitch*.4
	if look.z>.001:
		var target:=Basis.from_euler(Vector3(-look_pitch+e.x*.5+(torso.x+hit_pitch*1.3)*.4,look.y,e.z+(torso.y+hit_roll)*.35),EULER_ORDER_YXZ).get_rotation_quaternion()
		return local_fk.slerp(parent.inverse()*target,look.z).normalized()
	if absf(look.y)+absf(look_pitch)>.0001:
		return (Basis.from_euler(Vector3(-look_pitch,look.y,0),EULER_ORDER_YXZ).get_rotation_quaternion()*local_fk).normalized()
	return local_fk

func _offset(rig:Skeleton3D,name:String,delta:Vector3) -> void:
	var index:int=_bones.get(name,-1)
	if index<0:return
	var rotation:=Basis(rig.get_bone_pose_rotation(index)).get_euler(EULER_ORDER_XYZ)
	rig.set_bone_pose_rotation(index,Basis.from_euler(rotation+delta,EULER_ORDER_XYZ).get_rotation_quaternion())

func _ear(rig:Skeleton3D,name:String,delta:float,side:float,lo:float,hi:float) -> void:
	var index:int=_bones.get(name,-1)
	if index<0:return
	var rotation:=Basis(rig.get_bone_pose_rotation(index)).get_euler(EULER_ORDER_XYZ)
	rotation.z=side*clampf(rotation.z*side+delta,lo,hi)
	rig.set_bone_pose_rotation(index,Basis.from_euler(rotation,EULER_ORDER_XYZ).get_rotation_quaternion())
