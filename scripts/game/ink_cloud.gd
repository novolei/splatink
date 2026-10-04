class_name InkCloud
extends Node3D

## Original 15-puff storm cloud, with two shared materials and two draw submissions.
static var _geometry: ArrayMesh
var groups: Array[MultiMesh] = []
var puffs: Array[Dictionary] = []

func configure(color: Color) -> void:
	if not _geometry:
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/cloud_geometry.json"))
		var vertices:=PackedVector3Array()
		var normals:=PackedVector3Array()
		var uv:=PackedVector2Array()
		var indices:=PackedInt32Array()
		for i in range(0,source.position.size(),3):
			vertices.append(Vector3(source.position[i],source.position[i+1],source.position[i+2]))
			normals.append(Vector3(source.normal[i],source.normal[i+1],source.normal[i+2]))
		for i in range(0,source.uv.size(),2):uv.append(Vector2(source.uv[i],source.uv[i+1]))
		for i in range(0,vertices.size(),3):indices.append_array(PackedInt32Array([i,i+2,i+1]))
		var arrays:Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_TEX_UV]=uv
		arrays[Mesh.ARRAY_INDEX]=indices
		_geometry=ArrayMesh.new()
		_geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for top:bool in [false,true]:
		var node:=MultiMeshInstance3D.new()
		var instances:=MultiMesh.new()
		instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.mesh=_geometry
		instances.instance_count=6 if top else 9
		instances.visible_instance_count=instances.instance_count
		node.multimesh=instances
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=color.lerp(Color.WHITE,.55 if top else .12)
		mat.albedo_color.a=.97
		mat.roughness=.95
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled=true
		mat.emission=color
		mat.emission_energy_multiplier=.08 if top else .16
		node.material_override=mat
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if OS.has_feature("mobile") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		groups.append(instances)
	_puff(Vector3.ZERO,1.9,0)
	for i in 8:
		var angle:float=float(i)/8.0*TAU+randf()*.3
		var radius:float=1.7+randf()*.6
		_puff(Vector3(cos(angle)*radius,-.1+randf()*.2,sin(angle)*radius),1.05+randf()*.45,0)
	for i in 5:
		var angle:float=float(i)/5.0*TAU+.4
		var radius:float=.6+randf()*.8
		_puff(Vector3(cos(angle)*radius,.75+randf()*.3,sin(angle)*radius),.9+randf()*.4,1)
	_puff(Vector3(0,1.15,0),1.0,1)
	scale=Vector3.ONE*.01
	update(0.0,.01)

func _puff(pos:Vector3,radius:float,group:int) -> void:
	var index:int=0
	for puff in puffs:
		if int(puff.group)==group:index+=1
	puffs.append({"pos":pos,"scale":Vector3(radius,radius*.68,radius),"bob":randf()*6.28,"group":group,"index":index})

func update(time:float,cloud_scale:float) -> void:
	scale=Vector3.ONE*cloud_scale
	for puff in puffs:
		puff.pos.y+=sin(time*1.6+float(puff.bob))*.0025
		var transform:=Transform3D(Basis.from_scale(puff.scale),puff.pos)
		groups[int(puff.group)].set_instance_transform(int(puff.index),transform)
