// Original Three PMREM CubeUV layout and roughness-to-filter mapping. The atlas
// contains all prefiltered lobes, so no environment convolution runs per frame.
uniform sampler2D source_pmrem:filter_linear,repeat_disable;
uniform bool source_pmrem_enabled=false;
uniform float source_env_intensity=0.45;
uniform float source_pmrem_max_mip=8.0;
uniform vec2 source_pmrem_size=vec2(768.0,1024.0);

float source_cube_face(vec3 direction){
 vec3 a=abs(direction);
 if(a.x>a.z){if(a.x>a.y)return direction.x>0.0?0.0:3.0;return direction.y>0.0?1.0:4.0;}
 if(a.z>a.y)return direction.z>0.0?2.0:5.0;
 return direction.y>0.0?1.0:4.0;
}
vec2 source_cube_face_uv(vec3 d,float face){
 vec2 uv;
 if(face==0.0)uv=vec2(d.z,d.y)/abs(d.x);
 else if(face==1.0)uv=vec2(-d.x,-d.z)/abs(d.y);
 else if(face==2.0)uv=vec2(-d.x,d.y)/abs(d.z);
 else if(face==3.0)uv=vec2(-d.z,d.y)/abs(d.x);
 else if(face==4.0)uv=vec2(-d.x,d.z)/abs(d.y);
 else uv=vec2(d.x,d.y)/abs(d.z);
 return (uv+vec2(1.0))*0.5;
}
vec3 source_cube_bilinear(vec3 direction,float mip){
 float face=source_cube_face(direction),filter_mip=max(4.0-mip,0.0);
 float face_size=exp2(max(mip,4.0));
 vec2 uv=source_cube_face_uv(direction,face)*(face_size-2.0)+vec2(1.0);
 if(face>2.0){uv.y+=face_size;face-=3.0;}
 uv.x+=face*face_size+filter_mip*48.0;
 uv.y+=4.0*(exp2(source_pmrem_max_mip)-face_size);
 return textureLod(source_pmrem,uv/source_pmrem_size,0.0).rgb;
}
float source_roughness_mip(float rough){
 if(rough>=0.8)return (1.0-rough)*5.0-2.0;
 if(rough>=0.4)return (0.8-rough)*7.5-1.0;
 if(rough>=0.305)return (0.4-rough)/0.095+2.0;
 if(rough>=0.21)return (0.305-rough)/0.095+3.0;
 return -2.0*log2(1.16*max(rough,0.0001));
}
vec3 source_cube_uv(vec3 direction,float rough){
 float mip=clamp(source_roughness_mip(rough),-2.0,source_pmrem_max_mip),level=floor(mip);
 vec3 color=source_cube_bilinear(direction,level);
 float fraction=fract(mip);
 if(fraction==0.0)return color;
 return mix(color,source_cube_bilinear(direction,level+1.0),fraction);
}
vec3 source_ibl_irradiance(vec3 environment_normal){
 return source_pmrem_enabled?source_cube_uv(normalize(environment_normal),1.0)*PI*source_env_intensity:vec3(0.0);
}
vec3 source_ibl_radiance(vec3 environment_normal,vec3 environment_view,float rough){
 vec3 reflection=reflect(-normalize(environment_view),normalize(environment_normal));
 reflection=normalize(mix(reflection,normalize(environment_normal),pow(rough,4.0)));
 return source_pmrem_enabled?source_cube_uv(reflection,rough)*source_env_intensity:vec3(0.0);
}
