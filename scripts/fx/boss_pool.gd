class_name InkBossFxPool
extends Node3D

## bossModelFx.js: two fixed pools. The blobs land at their authored ground plane,
## never raycast or modify turf; their glossy geometry remains for .7 seconds.
var quality:float=1.0
var ink_limit:int=320
var steam_limit:int=140
var ink_mesh:MultiMeshInstance3D
var steam_mesh:MultiMeshInstance3D
var _material:StandardMaterial3D
var _p:Array[Vector3]=[]
var _v:Array[Vector3]=[]
var _age:PackedFloat32Array=[]
var _life:PackedFloat32Array=[]
var _size:PackedFloat32Array=[]
var _ground:PackedFloat32Array=[]
var _splat:PackedByteArray=[]
var _sp:Array[Vector3]=[]
var _sv:Array[Vector3]=[]
var _sa:PackedFloat32Array=[]
var _sl:PackedFloat32Array=[]
var _ss:PackedFloat32Array=[]
var _seed:PackedFloat32Array=[]
var ink_count:int=0
var steam_count:int=0
var _rng:int=9001
var _geyser_time:float=-1
var _geyser_duration:float=3.6
var _geyser_position:Vector3
var _ink_acc:float=0
var _steam_acc:float=0

func initialize() -> void:
	_material=StandardMaterial3D.new()
	_material.roughness=.12;_material.clearcoat_enabled=true;_material.clearcoat=1;_material.clearcoat_roughness=.04
	ink_mesh=_mesh(_geometry(1),_material,384,false)
	var quad:=QuadMesh.new();quad.size=Vector2.ONE
	var steam_material:=ShaderMaterial.new();steam_material.shader=preload("res://assets/shaders/fx_boss_steam.gdshader")
	steam_mesh=_mesh(quad,steam_material,168,true)
	for i in 384:_p.append(Vector3.ZERO);_v.append(Vector3.ZERO)
	for i in 168:_sp.append(Vector3.ZERO);_sv.append(Vector3.ZERO)
	# Packed arrays have value semantics, so resize the member storage explicitly.
	_age.resize(384);_life.resize(384);_size.resize(384);_ground.resize(384);_splat.resize(384)
	_sa.resize(168);_sl.resize(168);_ss.resize(168);_seed.resize(168)

func _mesh(geometry:Mesh,material:Material,count:int,custom:bool) -> MultiMeshInstance3D:
	var node:=MultiMeshInstance3D.new();add_child(node)
	node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data=custom;node.multimesh.mesh=geometry
	node.multimesh.instance_count=count;node.multimesh.visible_instance_count=0
	node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb=AABB(Vector3(-512,-64,-512),Vector3(1024,200,1024))
	return node

func _geometry(detail:int) -> ArrayMesh:
	var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/game/boss_ink_geometry_%s.json"%detail))
	var positions:PackedVector3Array=[];var normals:PackedVector3Array=[];var uvs:PackedVector2Array=[]
	for i in range(0,record.position.size(),3):positions.append(Vector3(record.position[i],record.position[i+1],record.position[i+2]));normals.append(Vector3(record.normal[i],record.normal[i+1],record.normal[i+2]))
	for i in range(0,record.uv.size(),2):uvs.append(Vector2(record.uv[i],record.uv[i+1]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var indices:PackedInt32Array=[]
	for i in range(0,positions.size(),3):indices.append(i);indices.append(i+2);indices.append(i+1)
	arrays[Mesh.ARRAY_INDEX]=indices
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func set_quality(value:float) -> void:
	quality=value;ink_limit=roundi(320*value);steam_limit=roundi(140*value)
	if ink_count>ink_limit:ink_count=ink_limit
	if steam_count>steam_limit:steam_count=steam_limit
	if ink_mesh:ink_mesh.multimesh.mesh=_geometry(0 if value<=.4 else 1)

func set_ink(color:Color) -> void:
	# Recipes pass linear THREE.Color; StandardMaterial decodes its sRGB color itself.
	_material.albedo_color=color.linear_to_srgb()

func _rnd() -> float:
	_rng=(_rng+0x6d2b79f5)&0xffffffff
	var t:int=((_rng^(_rng>>15))*(1|_rng))&0xffffffff
	t=(t^((t+(((t^(t>>7))*(61|t))&0xffffffff))&0xffffffff))&0xffffffff
	return float((t^(t>>14))&0xffffffff)/4294967296.0

func _slot(age:PackedFloat32Array,life:PackedFloat32Array,count:int) -> int:
	var best:int=0;var remaining:float=INF
	for i in count:
		var value:float=life[i]-age[i]
		if value<remaining:remaining=value;best=i
	return best

func ink(pos:Vector3,count:int,dir:Vector3,speed:float,spread:float=.6,size:float=.18,ground_y:float=0,life:float=2.2) -> void:
	for k in maxi(1,roundi(count*quality)):
		var i:int=ink_count if ink_count<ink_limit else _slot(_age,_life,ink_count)
		if ink_count<ink_limit:ink_count+=1
		_p[i]=pos+Vector3(_rnd()-.5,_rnd()-.5,_rnd()-.5)*.2
		var direction:Vector3=(dir+Vector3(_rnd()-.5,_rnd()-.5,_rnd()-.5)*2*spread).normalized()
		_v[i]=direction*speed*(.55+_rnd()*.6);_age[i]=0;_life[i]=life*(.7+_rnd()*.5)
		var rs:float=_rnd();_size[i]=size*(.3+rs*rs*1.3);_ground[i]=ground_y;_splat[i]=0

func steam(pos:Vector3,count:int,dir:Vector3,speed:float,size:float=1.2,life:float=1.6) -> void:
	for k in maxi(1,roundi(count*quality)):
		var i:int=steam_count if steam_count<steam_limit else _slot(_sa,_sl,steam_count)
		if steam_count<steam_limit:steam_count+=1
		_sp[i]=pos+Vector3(_rnd()-.5,_rnd()-.5,_rnd()-.5)*.3
		var sp:float=speed*(.6+_rnd()*.6)
		_sv[i]=(dir+Vector3((_rnd()-.5)*.5,(_rnd()-.5)*.3,(_rnd()-.5)*.5))*sp+Vector3.UP*.6
		_sa[i]=0;_sl[i]=life*(.7+_rnd()*.6);_ss[i]=size*(.6+_rnd()*.8);_seed[i]=_rnd()*10

func geyser(pos:Vector3,duration:float=3.6) -> void:
	_geyser_position=pos;_geyser_time=duration;_geyser_duration=duration

func update(dt:float,camera:Camera3D) -> void:
	if dt<=0:return
	if _geyser_time>0:
		_geyser_time-=dt
		var k:float=maxf(0,minf(1,_geyser_time/.8)*minf(1,(_geyser_duration-_geyser_time)/.2))
		_ink_acc+=dt*130*k
		while _ink_acc>=1:_ink_acc-=1;ink(_geyser_position,1,Vector3.UP,16*(.6+.4*k),.2,.15,_geyser_position.y-4.2,3)
		_steam_acc+=dt*10*k
		while _steam_acc>=1:_steam_acc-=1;steam(_geyser_position,1,Vector3.UP,3,2.4,2)
	var live:int=0
	for i in ink_count:
		_age[i]+=dt
		if _age[i]>=_life[i]:continue
		if not _splat[i]:
			_v[i].y-=16*dt;_v[i].x*=1-.4*dt;_v[i].z*=1-.4*dt;_p[i]+=_v[i]*dt
			if _p[i].y<_ground[i]+.02 and _v[i].y<0:_splat[i]=1;_p[i].y=_ground[i]+.02;_life[i]=minf(_life[i],_age[i]+.7)
		var age:float=_age[i]/_life[i]
		var size:float=_size[i]*(1-(age-.8)/.2 if age>.8 else 1)
		var basis:=Basis.IDENTITY
		if _splat[i]:basis=Basis.from_scale(Vector3(size*1.9,size*.18,size*1.9))
		else:
			var speed:float=_v[i].length();var stretch:float=1+minf(2.6,speed*.16)
			if speed>.0001:basis=Basis(Quaternion(Vector3.BACK,_v[i]/speed))
			basis=Basis(basis.x*(size/sqrt(stretch)),basis.y*(size/sqrt(stretch)),basis.z*(size*stretch))
		ink_mesh.multimesh.set_instance_transform(live,Transform3D(basis,_p[i]));live+=1
	ink_mesh.multimesh.visible_instance_count=live
	if live==0:ink_count=0
	var steam_live:int=0
	for i in steam_count:
		_sa[i]+=dt
		if _sa[i]>=_sl[i]:continue
		var fraction:float=_sa[i]/_sl[i];var drag:float=1-1.4*dt
		_sv[i]*=drag;_sv[i].y+=.9*dt;_sp[i]+=_sv[i]*dt
		var size:float=_ss[i]*(.5+1.6*sqrt(fraction))
		var alpha:float=.42*minf(1,fraction*6)*pow(1-fraction,2)
		var basis:Basis=Basis(camera.global_basis.x*size,camera.global_basis.y*size,camera.global_basis.z*size) if camera else Basis.from_scale(Vector3.ONE*size)
		steam_mesh.multimesh.set_instance_transform(steam_live,Transform3D(basis,_sp[i]))
		steam_mesh.multimesh.set_instance_custom_data(steam_live,Color(alpha,_seed[i],0,0));steam_live+=1
	steam_mesh.multimesh.visible_instance_count=steam_live
	if steam_live==0:steam_count=0

func clear() -> void:
	ink_count=0;steam_count=0;_geyser_time=-1;_ink_acc=0;_steam_acc=0
	if ink_mesh:ink_mesh.multimesh.visible_instance_count=0
	if steam_mesh:steam_mesh.multimesh.visible_instance_count=0
