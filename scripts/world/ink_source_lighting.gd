class_name InkSourceLighting
extends RefCounted
## Shared source Standard/Physical BRDF and cached, original CubeUV illumination.
## Original exported material colors / vertex RGB are already linear; texture PNGs
## use source_color decoding. Cached variants avoid a shader compile per prop.
static var _shaders: Dictionary = {}
const TEMPLATE := "res://assets/shaders/environment_source_material.gdshader"
const Source = preload("res://scripts/world/source_mesh.gd")

static func make(data: Dictionary, lighting: Dictionary = {}) -> Material:
	var original := Source.material(data)
	original.emission_energy_multiplier = float(data.get("intensity",data.get("emissive_intensity",1.0)))
	var material := from_standard(original,lighting) as ShaderMaterial
	configure_data(material,data)
	configure(material,lighting)
	return material

static func configure_data(material: ShaderMaterial, data: Dictionary) -> void:
	material.set_shader_parameter("base_clearcoat",float(data.get("clearcoat",0.0)))
	material.set_shader_parameter("base_clearcoat_roughness",float(data.get("clearcoat_roughness",0.1)))
	material.set_shader_parameter("base_specular",0.5*sqrt(float(data.get("specular_intensity",1.0))))
	material.set_meta("source_env_map_intensity",float(data.get("env_map_intensity",1.0)))

static func from_standard(source: StandardMaterial3D, theme: Dictionary = {}) -> Material:
	if source == null: return null
	var unlit := source.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED
	var blend := source.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA
	var mask := source.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var cull := source.cull_mode
	var key := "%d%d%d%d"%[int(unlit),int(blend),int(mask),int(cull)]
	if not _shaders.has(key):
		var code := FileAccess.get_file_as_string(TEMPLATE)
		var modes := "diffuse_lambert,"+("cull_disabled" if cull==BaseMaterial3D.CULL_DISABLED else "cull_front" if cull==BaseMaterial3D.CULL_FRONT else "cull_back")+",ambient_light_disabled"
		if unlit: modes += ",unshaded"
		if blend: modes += ",blend_mix,depth_draw_never"
		code = code.replace("render_mode diffuse_lambert,cull_disabled,ambient_light_disabled;","render_mode "+modes+";")
		code = code.replace("// SOURCE_ALPHA", "ALPHA=surface.a;ALPHA_SCISSOR_THRESHOLD=alpha_cutoff;" if mask else "ALPHA=surface.a;" if blend else "")
		code = code.replace("// SOURCE_INDIRECT","EMISSION=emission_color;" if unlit else "EMISSION+=native_source_indirect(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,world_normal,world_view,hemi,1.0,1.0);")
		var shader := Shader.new()
		shader.code = code
		_shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[key]
	var color := source.albedo_color
	material.set_shader_parameter("base_color",Vector4(color.r,color.g,color.b,color.a))
	material.set_shader_parameter("base_roughness",source.roughness)
	material.set_shader_parameter("base_metallic",source.metallic)
	material.set_shader_parameter("base_specular",source.metallic_specular)
	material.set_shader_parameter("base_clearcoat",source.clearcoat if source.clearcoat_enabled else 0.0)
	material.set_shader_parameter("base_clearcoat_roughness",source.clearcoat_roughness)
	material.set_shader_parameter("vertex_color_factor",1.0 if source.vertex_color_use_as_albedo else 0.0)
	material.set_shader_parameter("has_atlas",1.0 if source.albedo_texture != null else 0.0)
	if source.albedo_texture != null: material.set_shader_parameter("atlas",source.albedo_texture)
	material.set_shader_parameter("uv_scale",Vector2(source.uv1_scale.x,source.uv1_scale.y))
	material.set_shader_parameter("uv_offset",Vector2(source.uv1_offset.x,source.uv1_offset.y))
	material.set_shader_parameter("alpha_cutoff",source.alpha_scissor_threshold)
	var emission := source.emission
	material.set_shader_parameter("emission_color",Vector3(emission.r,emission.g,emission.b)*source.emission_energy_multiplier if source.emission_enabled else Vector3.ZERO)
	material.render_priority = source.render_priority
	material.set_meta("source_hemi",true)
	configure(material,theme)
	return material

static func configure(material: Material, theme: Dictionary) -> void:
	if not material is ShaderMaterial: return
	var parameters := InkAvatar._hemi_parameters(theme)
	(material as ShaderMaterial).set_shader_parameter("hemi_sky",parameters.sky)
	(material as ShaderMaterial).set_shader_parameter("hemi_ground",parameters.ground)
	var pmrem := theme.get("source_pmrem") as Texture2D
	(material as ShaderMaterial).set_shader_parameter("source_pmrem_enabled",pmrem!=null)
	if pmrem!=null:
		(material as ShaderMaterial).set_shader_parameter("source_pmrem",pmrem)
		(material as ShaderMaterial).set_shader_parameter("source_pmrem_size",Vector2(pmrem.get_width(),pmrem.get_height()))
		(material as ShaderMaterial).set_shader_parameter("source_pmrem_max_mip",log(float(pmrem.get_height())/4.0)/log(2.0))
	(material as ShaderMaterial).set_shader_parameter("source_env_intensity",float(theme.get("envK",theme.get("source_env_intensity",0.45)))*float(material.get_meta("source_env_map_intensity",1.0)))
