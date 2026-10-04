class_name SourceMesh
extends RefCounted

static func floats(file: FileAccess, record: Dictionary) -> PackedFloat32Array:
	file.seek(int(record.offset))
	return file.get_buffer(int(record.length) * 4).to_float32_array()

static func vectors3(values: PackedFloat32Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(values.size() / 3)
	for i in result.size(): result[i] = Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2])
	return result

static func vectors2(values: PackedFloat32Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(values.size() / 2)
	for i in result.size(): result[i] = Vector2(values[i * 2], values[i * 2 + 1])
	return result

static func transform_matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[4],values[5],values[6]),Vector3(values[8],values[9],values[10])),Vector3(values[12],values[13],values[14]))

static func build(file: FileAccess, record: Dictionary, paint_uv_override: PackedFloat32Array=PackedFloat32Array()) -> ArrayMesh:
	var attrs: Dictionary = record.attributes
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vectors3(floats(file, attrs.position))
	if attrs.has("normal"): arrays[Mesh.ARRAY_NORMAL] = vectors3(floats(file, attrs.normal))
	if attrs.has("color"):
		var data := floats(file, attrs.color)
		var colors := PackedColorArray()
		var size: int = int(attrs.color.size)
		colors.resize(data.size() / size)
		for i in colors.size(): colors[i] = Color(data[i*size],data[i*size+1],data[i*size+2],data[i*size+3] if size==4 else 1.0)
		arrays[Mesh.ARRAY_COLOR] = colors
	if attrs.has("faceUv"):
		arrays[Mesh.ARRAY_TEX_UV] = vectors2(floats(file, attrs.faceUv))
	elif attrs.has("uv"):
		var uv := vectors2(floats(file, attrs.uv))
		for i in uv.size(): uv[i].y = 1.0 - uv[i].y
		arrays[Mesh.ARRAY_TEX_UV] = uv
	var flags: int = 0
	if attrs.has("paintUv"): arrays[Mesh.ARRAY_TEX_UV2] = vectors2(paint_uv_override if not paint_uv_override.is_empty() else floats(file, attrs.paintUv))
	if attrs.has("faceData"):
		arrays[Mesh.ARRAY_CUSTOM0] = floats(file, attrs.faceData)
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var light := floats(file,attrs.lightUv)
		var face_flags := floats(file,attrs.faceFlags)
		var aux := PackedFloat32Array()
		aux.resize(light.size() * 2)
		for i in light.size()/2:
			aux[i*4] = light[i*2]; aux[i*4+1] = light[i*2+1]
			aux[i*4+2] = face_flags[i*3+2]; aux[i*4+3] = face_flags[i*3]
		arrays[Mesh.ARRAY_CUSTOM1] = aux
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		arrays[Mesh.ARRAY_CUSTOM2] = floats(file,attrs.faceTan)
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
		arrays[Mesh.ARRAY_CUSTOM3] = face_flags
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT
	var indices := PackedInt32Array()
	if record.get("index") != null:
		file.seek(int(record.index.offset))
		indices = file.get_buffer(int(record.index.length)*4).to_int32_array()
	else:
		indices.resize(arrays[Mesh.ARRAY_VERTEX].size())
		for i in indices.size(): indices[i] = i
	# Three.js front faces are counterclockwise; Godot front faces are clockwise.
	for i in range(0,indices.size()-2,3):
		var temp: int = indices[i+1];indices[i+1]=indices[i+2];indices[i+2]=temp
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
	return mesh

static func material(data: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode=BaseMaterial3D.DIFFUSE_LAMBERT
	var col: Array = data.get("color",[1,1,1])
	mat.albedo_color = Color(col[0],col[1],col[2],data.get("opacity",1))
	mat.vertex_color_use_as_albedo = true
	mat.roughness = data.get("roughness",.6)
	mat.metallic = data.get("metalness",0)
	if data.get("double_side",false): mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if data.get("unlit",false): mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if data.get("transparent",false): mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif data.get("alpha_test",0)>0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = data.alpha_test
	if data.get("emission") != null:
		var c: Array = data.emission
		mat.emission_enabled = true
		mat.emission = Color(c[0],c[1],c[2])
	if data.get("map") != null:
		mat.albedo_texture = load("res://assets/textures/"+data.map)
	return mat
