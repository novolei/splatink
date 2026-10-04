// Source Standard/Physical props: original linear colors, atlas and all light lobes.
shader_type spatial;
render_mode diffuse_lambert,cull_disabled,ambient_light_disabled;
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"
uniform vec4 base_color=vec4(1.0);
uniform float base_roughness=0.6;
uniform float base_metallic=0.0;
uniform float base_specular=0.5;
uniform float base_clearcoat=0.0;
uniform float base_clearcoat_roughness=0.1;
uniform sampler2D atlas:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform float has_atlas=0.0;
uniform float vertex_color_factor=1.0;
uniform vec2 uv_scale=vec2(1.0);
uniform vec2 uv_offset=vec2(0.0);
uniform vec3 emission_color=vec3(0.0);
uniform vec3 hemi_sky=vec3(0.0);
uniform vec3 hemi_ground=vec3(0.0);
uniform float alpha_cutoff=0.5;
void fragment(){
	vec4 surface=base_color*mix(vec4(1.0),COLOR,vertex_color_factor);
	if(has_atlas>0.5)surface*=texture(atlas,UV*uv_scale+uv_offset);
	ALBEDO=surface.rgb;METALLIC=base_metallic;SPECULAR=base_specular;
	vec3 dxy=max(abs(dFdx(NORMAL)),abs(dFdy(NORMAL)));
	float geometry_roughness=max(dxy.x,max(dxy.y,dxy.z));
	ROUGHNESS=min(max(base_roughness,0.0525)+geometry_roughness,1.0);
	native_specularColor=vec3(0.16*base_specular*base_specular);
	native_specularColorBlended=mix(native_specularColor,ALBEDO,METALLIC);
	native_specularF90=1.0;
	native_clearcoat=base_clearcoat;
	native_clearcoatRoughness=min(max(base_clearcoat_roughness,0.0525)+geometry_roughness,1.0);
	native_sheenColor=vec3(0.0);native_sheenRoughness=0.6;
	native_sss=0.0;native_thin=0.0;native_direct_ao=1.0;
	native_gum_on=0.0;native_gum_thin=0.0;native_gum_trans=vec3(0.0);
	float nv=clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0);
	vec2 fab=native_dfg(vec2(ROUGHNESS,nv));
	native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(fab.x+fab.y,0.000001)-1.0);
	native_coat_normal=normalize(NORMAL);
	native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,nv);
	vec3 world_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	vec3 world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
	vec3 hemi=mix(hemi_ground,hemi_sky,clamp(world_normal.y*0.5+0.5,0.0,1.0));
	EMISSION=emission_color*native_coat_attenuation;
	// SOURCE_INDIRECT
	// SOURCE_ALPHA
}
