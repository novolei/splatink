// Three RE_IndirectDiffuse/Specular with original prefiltered CubeUV atlas.
// PBR math is supplied by character_lighting; source hemisphere is irradiance/PI.
// Caller includes source_cube_uv.gdshaderinc once, alongside the PBR math.
vec3 native_multi_scatter(vec2 fab,vec3 f0,float f90){
	vec3 single=f0*fab.x+vec3(f90*fab.y);
	float missing=1.0-fab.x-fab.y;
	vec3 average=f0+(vec3(1.0)-f0)*0.047619;
	return single*average/(vec3(1.0)-missing*average)*missing;
}
vec3 native_source_indirect_coated(vec3 albedo,float metal,vec3 f0,float f90,float rough,
		vec3 sheen,float sheen_rough,float coat,float coat_rough,vec3 indirect_normal,
		vec3 indirect_view,vec3 hemi,float diffuse_ao,float specular_ao,vec3 indirect_coat_normal){
	float nv=clamp(dot(normalize(indirect_normal),normalize(indirect_view)),0.0,1.0);
	vec2 fab=native_dfg(vec2(rough,nv));
	vec3 single_dielectric=f0*fab.x+vec3(f90*fab.y);
	vec3 single_metal=albedo*fab.x+vec3(f90*fab.y);
	vec3 multi_dielectric=native_multi_scatter(fab,f0,f90);
	vec3 multi_metal=native_multi_scatter(fab,albedo,f90);
	vec3 irradiance=source_ibl_irradiance(indirect_normal)/PI;
	vec3 radiance=source_ibl_radiance(indirect_normal,indirect_view,rough);
	float sheen_albedo=native_sheen_albedo(nv,sheen_rough);
	float sheen_energy=1.0-max(sheen.r,max(sheen.g,sheen.b))*sheen_albedo;
	vec3 diffuse=albedo*(1.0-metal)*(hemi+irradiance)*(vec3(1.0)-single_dielectric-multi_dielectric)*sheen_energy*diffuse_ao;
	vec3 specular=(radiance*mix(single_dielectric,single_metal,metal)+irradiance*mix(multi_dielectric,multi_metal,metal))*sheen_energy*specular_ao;
	vec3 sheen_light=(hemi+irradiance)*sheen*sheen_albedo;
	float coat_nv=clamp(dot(normalize(indirect_coat_normal),normalize(indirect_view)),0.0,1.0);
	vec2 coat_fab=native_dfg(vec2(coat_rough,coat_nv));
	vec3 coat_light=source_ibl_radiance(indirect_coat_normal,indirect_view,coat_rough)*(vec3(0.04)*coat_fab.x+vec3(coat_fab.y))*coat;
	vec3 coat_mask=vec3(1.0)-coat*native_schlick(vec3(0.04),1.0,coat_nv);
	return (diffuse+specular+sheen_light)*coat_mask+coat_light;
}
// Ordinary props and terrain have no independent clearcoat normal.
vec3 native_source_indirect(vec3 albedo,float metal,vec3 f0,float f90,float rough,
		vec3 sheen,float sheen_rough,float coat,float coat_rough,vec3 indirect_normal,
		vec3 indirect_view,vec3 hemi,float diffuse_ao,float specular_ao){
	return native_source_indirect_coated(albedo,metal,f0,f90,rough,sheen,sheen_rough,
		coat,coat_rough,indirect_normal,indirect_view,hemi,diffuse_ao,specular_ao,indirect_normal);
}
