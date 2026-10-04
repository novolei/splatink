class_name InkCrabletAnimator
extends RefCounted
## Direct port of source bossModel.js Crablet.update, including spawn tumble,
## alternating tripod gait, claws/eye wobble, and the 0.14 second ink pop.
var _root: Node3D
var _rig: Skeleton3D
var _bones: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _rest_scale := Vector3.ONE
var time := 0.0
var phase := 0.0
var seed := 0.0
var pop_time := -1.0
var flash := 0.0
var finished := false

func configure(root: Node3D) -> void:
	_root = root
	_rest_scale = root.scale
	for node in root.find_children("*","Skeleton3D",true,false):
		_rig = node as Skeleton3D
		break
	if _rig == null: return
	for i in _rig.get_bone_count(): _bones[String(_rig.get_bone_name(i))] = i
	for node in root.find_children("*","MeshInstance3D",true,false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null: _materials.append(material)
	var random := RandomNumberGenerator.new()
	random.seed = int(root.get_instance_id())*1664525+1013904223
	phase = random.randf()
	seed = random.randf()*10.0
	update(0.0)

func update(dt: float, speed: float = 0.0, dead: bool = false) -> bool:
	if _rig == null or finished: return finished
	time += dt
	if dead and pop_time<0.0: pop_time = 0.0
	var sp := minf(1.0,speed/3.0)
	phase += dt*(1.2+speed*2.4)
	var ph := phase*TAU
	var tumble := maxf(0.0,1.0-time/0.55)
	var land := sin(((time-0.5)/0.3)*PI) if time>0.5 and time<0.8 else 0.0
	_rotate("body",Vector3(tumble*tumble*6.0,0.0,tumble*2.5+sin(ph*2.0)*0.06*sp))
	_rig.set_bone_pose_position(int(_bones.body),Vector3(0.0,0.26+absf(sin(ph))*0.035*sp+sin(time*3.0+seed)*0.008-land*0.05+tumble*0.2,0.0))
	_rig.set_bone_pose_scale(int(_bones.body),Vector3(1.0+land*0.12,1.0-land*0.15,1.0+land*0.12))
	_rotate("lid",Vector3(-0.05*absf(sin(ph*2.0))*sp-land*0.1,0,0))
	for i in 6:
		var group := (i%2)^(1 if i>=3 else 0)
		var angle := ph+float(group)*PI
		var side := 1.0 if i<3 else -1.0
		_rotate("leg"+("L" if i<3 else "R")+str(i%3),Vector3(0,sin(angle)*0.45*sp,side*(maxf(0.0,cos(angle))*0.5*sp+tumble*0.9)))
	var snap := pow(maxf(0.0,sin(time*5.0+seed)),6.0)
	_rotate("clawL",Vector3(-0.3*snap-0.15*sin(ph)*sp,0,0))
	_rotate("clawR",Vector3(-0.3*pow(maxf(0.0,sin(time*5.0+seed+1.7)),6.0)+0.15*sin(ph)*sp,0,0))
	_rotate("eyeL",Vector3(0,0,sin(time*7.0+seed)*0.15))
	_rotate("eyeR",Vector3(0,0,sin(time*7.3+seed+1.0)*0.15))
	if pop_time>=0.0:
		pop_time += dt
		var u := minf(1.0,pop_time/0.14)
		_root.scale = _rest_scale*(1.0+0.45*u*u)
		flash = u
		if pop_time>=0.14:
			_root.visible = false
			finished = true
	else:
		flash = maxf(0.0,flash-dt*6.0)
	for material in _materials:
		material.set_shader_parameter("uTime",time)
		material.set_shader_parameter("uFlash",flash)
	return finished

func hit() -> void:
	flash = 1.0

func _rotate(name: String, rotation: Vector3) -> void:
	_rig.set_bone_pose_rotation(int(_bones[name]),Basis.from_euler(rotation,EULER_ORDER_YXZ).get_rotation_quaternion())
