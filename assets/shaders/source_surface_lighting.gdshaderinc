#include "res://assets/shaders/source_surface_lamps.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"
varying vec4 surface_specular;
varying vec4 surface_coat;
varying vec3 surface_energy;
varying vec3 surface_indirect;
varying vec4 surface_ink;
varying vec3 surface_lamp_diffuse;
varying float surface_ao;

void light(){
 vec3 N=normalize(NORMAL),L=normalize(LIGHT),V=normalize(VIEW),H=normalize(L+V);
 float nl=clamp(dot(N,L),0.0,1.0),nv=clamp(dot(N,V),0.0,1.0);
 float nh=clamp(dot(N,H),0.0,1.0),vh=clamp(dot(V,H),0.0,1.0);
 vec3 energy=LIGHT_COLOR*ATTENUATION;
 vec3 coat_f0=vec3(surface_coat.z);
 vec3 coat_mask=vec3(1.0)-surface_coat.x*native_schlick(coat_f0,surface_coat.w,nv);
 vec3 diffuse=energy*nl*(vec3(1.0)-native_schlick(surface_specular.rgb,surface_specular.a,vh))/PI;
 DIFFUSE_LIGHT+=diffuse*coat_mask*mix(1.0,surface_ao,0.4);
 vec3 specular=nl*native_ggx(surface_specular.rgb,surface_specular.a,ROUGHNESS,nl,nv,nh,vh)*surface_energy;
 vec3 coat=surface_coat.x*nl*native_ggx(coat_f0,surface_coat.w,surface_coat.y,nl,nv,nh,vh);
 SPECULAR_LIGHT+=energy*(specular*coat_mask+coat)*SPECULAR_AMOUNT;
 // Source INK_SHADE is evaluated after direct lighting. Carry the unoccluded
 // indirect pigment into this pass so the real sun shadow drives its richness.
 if(surface_ink.a>0.0){
  vec3 lw=vec3(0.2126,0.7152,0.0722);
  float dl=dot(diffuse*ALBEDO*(1.0-METALLIC)+surface_lamp_diffuse,lw);
  float il=dot(surface_indirect,lw);
  float shade=1.0-smoothstep(0.1,0.6,dl/max(dl+il,0.00001));
  vec3 c2=surface_ink.rgb*surface_ink.rgb;
  vec3 rich=c2*(dot(surface_ink.rgb,lw)/max(dot(c2,lw),0.0001));
  vec3 indirect_rich=rich*(il/max(dot(surface_ink.rgb,lw),0.0001));
  vec3 indirect=mix(surface_indirect,indirect_rich,0.5*shade)*(1.0+0.6*shade);
  SPECULAR_LIGHT+=(indirect-surface_indirect)*surface_ink.a*surface_ao*coat_mask;
 }
}
