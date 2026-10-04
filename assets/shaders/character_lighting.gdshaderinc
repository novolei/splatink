// Source Three MeshPhysicalMaterial direct lobes and original INKWAVE light hooks.
// Godot LIGHT_COLOR includes PI; native lights use source intensity / PI.
// Fragment-to-light varyings keep the authored per-pixel material classes.
#include "res://assets/shaders/character_pbr.gdshaderinc"
// Pack scalars into eight slots; hero skin already uses seventeen varying slots.
varying vec4 native_spec0;
varying vec4 native_spec1;
varying vec4 native_sheen0;
varying vec4 native_params;
varying vec4 native_gum0;
varying vec4 native_energy0;
varying vec3 native_coat_attenuation;
varying vec3 native_coat_normal;
#define native_specularColor native_spec0.rgb
#define native_specularF90 native_spec0.a
#define native_specularColorBlended native_spec1.rgb
#define native_clearcoat native_spec1.a
#define native_sheenColor native_sheen0.rgb
#define native_sheenRoughness native_sheen0.a
#define native_clearcoatRoughness native_params.x
#define native_sss native_params.y
#define native_thin native_params.z
#define native_direct_ao native_params.w
#define native_gum_trans native_gum0.rgb
#define native_gum_thin native_gum0.a
#define native_energy_comp native_energy0.rgb
#define native_gum_on native_energy0.a

void light(){
	vec3 N=normalize(NORMAL),L=normalize(LIGHT),V=normalize(VIEW);
	vec3 H=normalize(L+V);
	float signed_nl=dot(N,L);
	float nl=clamp(signed_nl,0.0,1.0),nv=clamp(dot(N,V),0.0,1.0);
	float nh=clamp(dot(N,H),0.0,1.0),vh=clamp(dot(V,H),0.0,1.0);
	vec3 light_energy=LIGHT_COLOR*ATTENUATION;
	vec3 fresnel=native_schlick(native_specularColor,native_specularF90,vh);
	float sheen_max=max(native_sheenColor.r,max(native_sheenColor.g,native_sheenColor.b));
	float sheen_energy=1.0-sheen_max*max(native_sheen_albedo(nv,native_sheenRoughness),native_sheen_albedo(nl,native_sheenRoughness));
	vec3 diffuse_coefficient=vec3(nl*sheen_energy)/PI*(vec3(1.0)-fresnel);
#ifdef SOURCE_SKIN
	if(native_sss>0.001){
		vec3 w=uSSSW*native_sss;
		vec3 lam=vec3(nl);
		vec3 wrapped=clamp((vec3(signed_nl)+w)/(vec3(1.0)+w),vec3(0.0),vec3(1.0));
		wrapped=lam+max(wrapped-lam,vec3(0.0))*(1.0-smoothstep(0.05,0.55,signed_nl));
		float band=clamp(1.0-abs(signed_nl)*3.2,0.0,1.0)*native_sss;
		vec3 scattered=wrapped*mix(vec3(1.0),uSSSTint*1.6,band*0.4);
		diffuse_coefficient=mix(lam,scattered,0.85)/PI*(vec3(1.0)-fresnel);
		float back=pow(clamp(dot(V,-L),0.0,1.0),2.5);
		diffuse_coefficient+=uSSSTint*(native_thin*back*0.55+native_thin*0.12*clamp(-signed_nl+0.3,0.0,1.0));
	}
#endif
	// Engine multiplies DIFFUSE_LIGHT by ALBEDO*(1-METALLIC) after all lights.
	DIFFUSE_LIGHT+=light_energy*diffuse_coefficient*native_coat_attenuation*native_direct_ao;
	if(native_gum_on>0.001){
		float wrap=clamp((signed_nl+0.6)/1.6,0.0,1.0);
		float soak=max(wrap*wrap-nl,0.0);
		vec3 bent=normalize(L+N*0.45);
		float back=pow(clamp(dot(V,-bent),0.0,1.0),3.0);
		vec3 trans=pow(max(native_gum_trans,vec3(0.0001)),vec3(mix(2.1,0.85,native_gum_thin)));
		vec3 bleed=trans*back*(0.12+2.6*native_gum_thin*native_gum_thin+0.35*native_gum_thin)+pow(max(native_gum_trans,vec3(0.0001)),vec3(1.8))*soak*0.4;
		// Transmission is already colored, so accumulate the radiance without a
		// second ALBEDO multiplication. Godot applies no BRDF to this accumulator.
		SPECULAR_LIGHT+=native_gum_on*light_energy*bleed/PI*native_coat_attenuation;
	}
	vec3 base_spec=nl*sheen_energy*native_ggx(native_specularColorBlended,native_specularF90,ROUGHNESS,nl,nv,nh,vh)*native_energy_comp;
	vec3 sheen_spec=nl*native_sheen_brdf(native_sheenColor,native_sheenRoughness,nl,nv,nh);
	// Three coats the smooth geometric surface; only the base lobe receives
	// authored bumps. This keeps ink gloss broad over pores and cloth grooves.
	vec3 coat_normal=normalize(native_coat_normal);
	float coat_nl=clamp(dot(coat_normal,L),0.0,1.0);
	float coat_nv=clamp(dot(coat_normal,V),0.0,1.0);
	float coat_nh=clamp(dot(coat_normal,H),0.0,1.0);
	vec3 coat_spec=coat_nl*native_ggx(vec3(0.04),1.0,native_clearcoatRoughness,coat_nl,coat_nv,coat_nh,vh)*native_clearcoat;
	SPECULAR_LIGHT+=light_energy*((base_spec+sheen_spec)*native_coat_attenuation+coat_spec)*SPECULAR_AMOUNT;
}
