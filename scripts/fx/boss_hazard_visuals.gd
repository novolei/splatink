class_name InkBossHazardVisuals
extends RefCounted

## Source HazardFX geometry and GPU fragment recipes; shape data is reused by LAN proxies.
static var _geometries:Dictionary={}
static var _beam_material:StandardMaterial3D

static func make_material(kind:String,color:Color) -> Material:
	if kind=="beam":
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(color,.92)
		material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.no_depth_test=false;material.disable_fog=true
		material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED;material.render_priority=9
		return material
	var material:=ShaderMaterial.new()
	match kind:
		"ring":material.shader=preload("res://assets/shaders/fx_boss_ring.gdshader")
		"fan":material.shader=preload("res://assets/shaders/fx_boss_fan.gdshader")
		"lane":material.shader=preload("res://assets/shaders/fx_boss_lane.gdshader")
		_:material.shader=preload("res://assets/shaders/fx_boss_mark.gdshader")
	material.set_shader_parameter("uColor",color)
	material.render_priority=7
	return material

static func _array_mesh(positions:PackedVector3Array,normals:PackedVector3Array,uvs:PackedVector2Array,indices:PackedInt32Array,custom0:PackedFloat32Array=[]) -> ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	var flags:int=0
	if not custom0.is_empty():
		arrays[Mesh.ARRAY_CUSTOM0]=custom0
		flags=Mesh.ARRAY_CUSTOM_RGB_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
	return mesh

static func source_geometry(name:String) -> Mesh:
	if _geometries.has(name):return _geometries[name]
	if name=="mark":
		var plane:=PlaneMesh.new();plane.size=Vector2(2,2);_geometries[name]=plane;return plane
	var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/game/boss_%s_geometry.json"%name))
	var positions:PackedVector3Array=[];var normals:PackedVector3Array=[];var uvs:PackedVector2Array=[];var indices:PackedInt32Array=[]
	for i in range(0,record.position.size(),3):positions.append(Vector3(record.position[i],record.position[i+1],record.position[i+2]));normals.append(Vector3(record.normal[i],record.normal[i+1],record.normal[i+2]))
	for i in range(0,record.uv.size(),2):uvs.append(Vector2(record.uv[i],record.uv[i+1]))
	for i in range(0,record.index.size(),3):indices.append(int(record.index[i]));indices.append(int(record.index[i+2]));indices.append(int(record.index[i+1]))
	var mesh:ArrayMesh=_array_mesh(positions,normals,uvs,indices)
	_geometries[name]=mesh;return mesh

static func ring_mesh(reach:PackedFloat32Array) -> ArrayMesh:
	var positions:PackedVector3Array=[];var normals:PackedVector3Array=[];var uvs:PackedVector2Array=[];var indices:PackedInt32Array=[];var custom0:PackedFloat32Array=[]
	for segment in 96:
		var start:int=segment*4
		for corner in 4:
			positions.append(Vector3.ZERO);normals.append(Vector3.UP);uvs.append(Vector2.ZERO)
			# COLOR is RGBA8 in ArrayMesh and rounds heading/reach. Source attributes
			# are float32, so CUSTOM0 preserves the actual angle, side and floor cut.
			custom0.append_array(PackedFloat32Array([float(segment+(1 if corner>=2 else 0))/96.0*TAU,float(corner%2)*2.0-1.0,reach[segment]]))
		indices.append_array(PackedInt32Array([start,start+1,start+2,start+2,start+1,start+3]))
	return _array_mesh(positions,normals,uvs,indices,custom0)

static func fan_mesh(a0:float,a1:float,radii:PackedFloat32Array) -> ArrayMesh:
	var positions:PackedVector3Array=[Vector3.ZERO];var normals:PackedVector3Array=[Vector3.UP];var uvs:PackedVector2Array=[Vector2.ZERO];var indices:PackedInt32Array=[]
	var segments:int=radii.size()-1
	for i in radii.size():
		var angle:float=lerpf(a0,a1,float(i)/float(segments))
		positions.append(Vector3(sin(angle),0,cos(angle))*radii[i]);normals.append(Vector3.UP);uvs.append(Vector2(1,0))
		if i:indices.append_array(PackedInt32Array([0,i,i+1]))
	return _array_mesh(positions,normals,uvs,indices)

static func configure_mesh(node:MeshInstance3D,kind:String,recipe:Dictionary,color:Color) -> void:
	node.set_meta("boss_visual_kind",kind);node.set_meta("boss_visual_recipe",recipe)
	match kind:
		"ring":node.mesh=ring_mesh(PackedFloat32Array(recipe.reach))
		"fan":node.mesh=fan_mesh(float(recipe.a0),float(recipe.a1),PackedFloat32Array(recipe.radii))
		_:node.mesh=source_geometry(kind)
	node.material_override=make_material(kind,color)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb=AABB(Vector3(-40,-4,-40),Vector3(80,12,80))

static func describe(node:MeshInstance3D) -> Dictionary:
	var uniforms:Dictionary={}
	if node.material_override is ShaderMaterial:
		for key in ["uAlpha","uTime","uK","uR","uW"]:
			var value=node.material_override.get_shader_parameter(key)
			if value is float:uniforms[key]=value
	return {"kind":node.get_meta("boss_visual_kind","mark"),"recipe":node.get_meta("boss_visual_recipe",{}),"uniforms":uniforms}

static func apply_description(node:MeshInstance3D,record:Dictionary,color:Color) -> void:
	var kind:String=str(record.get("kind","mark"));var recipe:Dictionary=record.get("recipe",{})
	var signature:String=kind+JSON.stringify(recipe)
	if str(node.get_meta("boss_visual_signature",""))!=signature:
		configure_mesh(node,kind,recipe,color);node.set_meta("boss_visual_signature",signature)
	if node.material_override is ShaderMaterial:
		for key in record.get("uniforms",{}):node.material_override.set_shader_parameter(key,record.uniforms[key])
