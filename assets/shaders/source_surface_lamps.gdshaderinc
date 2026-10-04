// Original levelMaterial.js lamp pools. This runs on the GPU and only evaluates
// the BRDF inside each ten metre light radius; lamps have no shadow maps.
uniform vec3 lamp_positions[12];
uniform int lamp_count=0;
uniform vec3 lamp_color=vec3(0.0);
#include "res://assets/shaders/character_pbr.gdshaderinc"

vec3 source_lamp_radiance(vec3 position,mat3 view_basis,vec3 normal,vec3 view,vec3 albedo,float metallic,
                        float roughness,float ink,float fresh,float coat_roughness,float ao,out vec3 direct_diffuse){
 direct_diffuse=vec3(0.0);
 if(lamp_count==0)return vec3(0.0);
 vec3 N=normalize(normal),V=normalize(view);
 float nv=clamp(dot(N,V),0.0,1.0);
 vec3 f0=mix(vec3(0.04),albedo,metallic)*(1.0-0.7*ink);
 float f90=mix(1.0,0.35,ink);
 vec3 coat_f0=vec3(mix(0.04,0.055+0.015*fresh,ink));
 float coat_f90=mix(1.0,0.3,ink);
 vec2 fab=native_dfg(vec2(roughness,nv));
 vec3 compensation=vec3(1.0)+f0*(1.0/max(fab.x+fab.y,0.000001)-1.0);
 vec3 coat_attenuation=vec3(1.0)-ink*native_schlick(coat_f0,coat_f90,nv);
 vec3 result=vec3(0.0);
 for(int i=0;i<12;i++){
  if(i>=lamp_count)break;
  vec3 lw=lamp_positions[i]-position;
  float d2=dot(lw,lw);
  if(d2>100.0)continue;
  float window=clamp(1.0-d2*d2/10000.0,0.0,1.0);
  vec3 L=normalize(view_basis*lw),H=normalize(L+V);
  float nl=clamp(dot(N,L),0.0,1.0),nh=clamp(dot(N,H),0.0,1.0),vh=clamp(dot(V,H),0.0,1.0);
  vec3 irradiance=lamp_color*(window*window/max(d2,0.35))*nl;
  vec3 diffuse=albedo*(1.0-metallic)*(vec3(1.0)-native_schlick(f0,f90,vh))/PI;
  vec3 specular=native_ggx(f0,f90,roughness,nl,nv,nh,vh)*compensation;
  vec3 coat=ink*native_ggx(coat_f0,coat_f90,coat_roughness,nl,nv,nh,vh);
  direct_diffuse+=irradiance*diffuse;
  result+=irradiance*((diffuse*mix(1.0,ao,0.4)+specular)*coat_attenuation+coat);
 }
 return result;
}
