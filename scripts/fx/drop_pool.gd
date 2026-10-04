class_name InkDropPool
extends MultiMeshInstance3D
## Fixed storage; live entries are packed into one draw call. No per-drop nodes or tweens.
const FxColors = preload("res://scripts/fx/ink_fx_colors.gd")
const F_PAINT:int=1
const F_RING:int=2
const F_NOCOL:int=4
const F_QUIET:int=8
const F_MATTE:int=16
const INSTANCE_STRIDE:int=20

var capacity: int = 2048
var quality: float = 1.0
var alive: Array[int] = []
var _free: Array[int] = []
var _position: PackedVector3Array = []
var _velocity: PackedVector3Array = []
var _age: PackedFloat32Array = []
var _life: PackedFloat32Array = []
var _radius: PackedFloat32Array = []
var _gravity: PackedFloat32Array = []
var _stretch: PackedFloat32Array = []
var _gloss: PackedFloat32Array = []
var _growth: PackedFloat32Array = []
var _seed: PackedFloat32Array = []
var _flags: PackedByteArray = []
var _colors: PackedColorArray = []
var _shader: ShaderMaterial
var game: Node
var collision_budget: int = 24
var _probe_position: PackedVector3Array = []
var _paint: PackedByteArray = []
var _probe_cursor: int = 0
var _recycle:int=0
var water_y:float=-1.6
var gravity:float=17.0
var landing_flags:int=0
var collision_checks:int=0
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []
## Experimental submission only; the authoritative Float32 update is shared.
var batch_submission_enabled:bool=false
var profile_updates:bool=false
var profile_update:Dictionary={"integrate_us":0,"collision_land_us":0,"draw_submit_us":0,"submission_calls":0,"batch_enabled":0,"buffer_floats":0}
var _batch_buffer:PackedFloat32Array=[]
signal landed(position: Vector3, normal: Vector3, color: Color, radius: float, paint: bool, water: bool)

func initialize(limit: int) -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--fx-drop-batch" or arg=="--fx-drop-batch=true":batch_submission_enabled=true
		if arg.begins_with("--profile-render"):profile_updates=true
	capacity = limit
	alive.clear()
	_free.clear()
	render_packets.clear()
	_recycle=0
	_position.resize(limit)
	_velocity.resize(limit)
	_age.resize(limit)
	_life.resize(limit)
	_radius.resize(limit)
	_gravity.resize(limit)
	_stretch.resize(limit)
	_gloss.resize(limit)
	_growth.resize(limit)
	_seed.resize(limit)
	_flags.resize(limit)
	_colors.resize(limit)
	_probe_position.resize(limit)
	_paint.resize(limit)
	# Keep the full fixed-capacity buffer: MultiMesh requires instance_count*stride.
	# No resize/slice or per-instance array allocation occurs during submission.
	_batch_buffer.resize(limit*INSTANCE_STRIDE)
	_batch_buffer.fill(0.0)
	for index: int in limit: _free.append(index)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	multimesh.mesh = quad
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	_shader = ShaderMaterial.new()
	_shader.shader = preload("res://assets/shaders/fx_ink_drop.gdshader")
	material_override = _shader
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func set_lighting(light:Dictionary) -> void:
	_shader.set_shader_parameter("sun_direction",light.sun_direction)
	# The shader's source_color hint performs the sole GPU decode. Encode these
	# original numeric linear lighting colors for that boundary, including HDR bounce.
	for key in ["sun_color","sky_color","ground_color"]:_shader.set_shader_parameter(key,(light[key] as Color).linear_to_srgb())

func _random() -> float:
	return randf()

func drop(position: Vector3, velocity: Vector3, color: Color, radius: float = 0.1, life: float = 1.2, gravity_scale: float = 1.0, stretch: float = 1.0, gloss: float = 1.0, growth: float = 0.0, cosmetic: bool = false, input_linear: bool = false, flags:int=0) -> void:
	if capacity<=0:return
	var id:int
	if _free.is_empty():
		id=alive[_recycle%capacity]
		_recycle+=7
	else:
		id=_free.pop_back()
		alive.append(id)
	_position[id] = position
	_velocity[id] = velocity
	_age[id] = 0
	_life[id] = life
	_radius[id] = radius
	_gravity[id] = gravity_scale
	_stretch[id] = stretch
	_gloss[id] = gloss
	_growth[id] = growth
	_seed[id]=_random()
	_flags[id]=flags | (F_PAINT if cosmetic else 0) | (F_MATTE if gloss<=0.0 else 0)
	# Existing direct palette callers use sRGB; InkFx recipes opt into linear input.
	_colors[id] = color if input_linear else FxColors.from_srgb(color)
	_probe_position[id] = position
	_paint[id] = 1 if (_flags[id]&F_PAINT)!=0 else 0

func _kill(index:int) -> void:
	_free.append(alive[index])
	alive[index]=alive.back()
	alive.pop_back()

func _land(id:int,p:Vector3,normal:Vector3,water:bool,camera:Camera3D) -> void:
	landing_flags=int(_flags[id])
	# Painting precedes presentation in source _landDrop; matte grains and
	# no-collide secondary beads must not acquire a cosmetic ink speck.
	if not water and is_instance_valid(game):
		var flags:int=int(_flags[id])
		if (flags&F_PAINT)!=0 or ((flags&F_MATTE)==0 and _radius[id]>.012):
			var colors=game.get("team_colors")
			var team:int=FxColors.team_of(_colors[id],colors) if colors is Array and colors.size()>=2 else -1
			if team>=0:
				if (flags&F_PAINT)!=0:
					var network=game.get("network")
					if not (is_instance_valid(network) and bool(network.get("active"))):
						game.call("paint_splat",p+normal*.05,normal,clampf(_radius[id]*2.4,.12,.45),team,{})
				elif _radius[id]>=.014 and camera.global_position.distance_squared_to(p)<26.0*26.0:
					game.call("paint_splat",p+normal*.04,normal,minf(.11,_radius[id]*1.7),team,{"cosmetic":true,"kind":"speck","instant":true})
	landed.emit(p,normal,_colors[id],_radius[id],_paint[id]>0,water)

func update(delta: float, camera: Camera3D) -> void:
	if profile_updates:
		profile_update.integrate_us=0;profile_update.collision_land_us=0;profile_update.draw_submit_us=0
		profile_update.submission_calls=0;profile_update.batch_enabled=1 if batch_submission_enabled else 0
		profile_update.buffer_floats=_batch_buffer.size()
	if camera == null: return
	collision_checks=0
	if capture_render_packets:render_packets.clear()
	var right: Vector3 = camera.global_basis.x
	var up: Vector3 = camera.global_basis.y
	var back: Vector3 = camera.global_basis.z
	_shader.set_shader_parameter("camera_right", right)
	_shader.set_shader_parameter("camera_up", up)
	_shader.set_shader_parameter("camera_back", back)
	# Forward packed traversal matches original kill/swap order, including beads
	# appended by a landing callback. The native capacity/ray quota stays bounded.
	var integrate_started:int=Time.get_ticks_usec() if profile_updates else 0
	var collision_land_us:int=0
	var index:int=0
	while index<alive.size():
		var id: int = alive[index]
		_age[id] += delta
		if _age[id] >= _life[id]:
			_kill(index)
			continue
		var damping:float=1.0-.35*delta
		var v:Vector3=_velocity[id]
		v=Vector3(v.x*damping,v.y*damping-gravity*float(_gravity[id])*delta,v.z*damping)
		_velocity[id]=v
		var old:Vector3=_position[id]
		# Each assignment rounds once, as an original Float32Array write does.
		var next:Vector3=Vector3(old.x+v.x*delta,old.y+v.y*delta,old.z+v.z*delta)
		_position[id]=next
		var flags:int=int(_flags[id])
		if (flags&F_NOCOL)==0 and is_instance_valid(game) and collision_checks<collision_budget:
			var collision_started:int=Time.get_ticks_usec() if profile_updates else 0
			collision_checks+=1
			var hit:Dictionary=game.call("cast",_probe_position[id],next,[])
			_probe_position[id]=next
			if not hit.is_empty():
				_land(id,hit.position,hit.normal,false,camera)
				_kill(index)
				if profile_updates:collision_land_us+=Time.get_ticks_usec()-collision_started
				continue
			if profile_updates:collision_land_us+=Time.get_ticks_usec()-collision_started
		elif (flags&F_NOCOL)!=0:_probe_position[id]=next
		if old.y>=water_y and next.y<water_y:
			var water_started:int=Time.get_ticks_usec() if profile_updates else 0
			var t:float=(float(old.y)-water_y)/maxf(.00001,float(old.y)-float(next.y))
			_land(id,Vector3(old.x+(float(next.x)-float(old.x))*t,water_y,old.z+(float(next.z)-float(old.z))*t),Vector3.UP,true,camera)
			_kill(index)
			if profile_updates:collision_land_us+=Time.get_ticks_usec()-water_started
			continue
		index+=1
	var draw_started:int=Time.get_ticks_usec() if profile_updates else 0
	if profile_updates:
		profile_update.collision_land_us=collision_land_us
		# Exclusive packed traversal; timed casts, callbacks and contact retirement
		# are reported separately. Profiling overhead remains in these spans.
		profile_update.integrate_us=draw_started-integrate_started-collision_land_us
	for draw_index: int in alive.size():
		var id: int = alive[draw_index]
		var age:float=float(_age[id])
		var life:float=float(_life[id])
		var radius:float=Vector2(float(_radius[id])*minf(1.0,age*22.0+.35)*minf(1.0,(life-age)/.12),0).x
		var velocity: Vector3 = _velocity[id]
		var speed:float=sqrt(float(velocity.x)*float(velocity.x)+float(velocity.y)*float(velocity.y)+float(velocity.z)*float(velocity.z))
		var raw_stretch:float=1.0+minf(speed*.062*float(_stretch[id]),2.3*float(_stretch[id]))
		raw_stretch*=1.0+.14*sin(age*38.0+float(_seed[id])*20.0)*minf(1.0,age*6.0)
		raw_stretch=Vector2(maxf(1.0,raw_stretch),0).x
		var direction: Vector2 = Vector2(velocity.dot(right), velocity.dot(up))
		var length: float = direction.length()
		var axis: Vector2 = direction / length if length > .0001 else Vector2.UP
		var stretch:float=1.0+(raw_stretch-1.0)*(length/speed if speed>.0001 else 0.0)
		var x_axis: Vector3 = right * axis.y - up * axis.x
		var y_axis: Vector3 = right * axis.x + up * axis.y
		var basis: Basis = Basis(x_axis * radius / sqrt(stretch), y_axis * radius * stretch, back * radius)
		var transform:=Transform3D(basis,_position[id])
		var gloss:float=0.0 if (_flags[id]&F_MATTE)!=0 else 1.0
		if batch_submission_enabled:
			var offset:int=draw_index*INSTANCE_STRIDE
			# RenderingServer's 3D matrix is row-major, followed by raw linear
			# RGBA and raw custom floats; no shader source_color decode is added.
			_batch_buffer[offset]=basis.x.x;_batch_buffer[offset+1]=basis.y.x;_batch_buffer[offset+2]=basis.z.x;_batch_buffer[offset+3]=transform.origin.x
			_batch_buffer[offset+4]=basis.x.y;_batch_buffer[offset+5]=basis.y.y;_batch_buffer[offset+6]=basis.z.y;_batch_buffer[offset+7]=transform.origin.y
			_batch_buffer[offset+8]=basis.x.z;_batch_buffer[offset+9]=basis.y.z;_batch_buffer[offset+10]=basis.z.z;_batch_buffer[offset+11]=transform.origin.z
			var color:Color=_colors[id]
			_batch_buffer[offset+12]=color.r;_batch_buffer[offset+13]=color.g;_batch_buffer[offset+14]=color.b;_batch_buffer[offset+15]=color.a
			_batch_buffer[offset+16]=radius;_batch_buffer[offset+17]=stretch;_batch_buffer[offset+18]=gloss;_batch_buffer[offset+19]=1.0
		else:
			multimesh.set_instance_transform(draw_index,transform)
			multimesh.set_instance_color(draw_index, _colors[id])
			multimesh.set_instance_custom_data(draw_index,Color(radius,stretch,gloss,1.0))
		if capture_render_packets:render_packets.append({"color":_colors[id],"transform":transform,"radius":radius,"stretch":raw_stretch,"gloss":gloss})
	if batch_submission_enabled and not alive.is_empty():multimesh.buffer=_batch_buffer
	multimesh.visible_instance_count = alive.size()
	if profile_updates:
		profile_update.draw_submit_us=Time.get_ticks_usec()-draw_started
		profile_update.submission_calls=(1 if not alive.is_empty() else 0) if batch_submission_enabled else alive.size()*3

func clear() -> void:
	for id: int in alive: _free.append(id)
	alive.clear()
	render_packets.clear()
	if multimesh != null: multimesh.visible_instance_count = 0
