// Source UnrealBloomPass: half-resolution high-pass, five paired Gaussian levels.
#[vertex]
#version 450
void main(){vec2 p=vec2(gl_VertexIndex==1?2.0:0.0,gl_VertexIndex==2?2.0:0.0);gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
#[fragment]
#version 450
layout(set=0,binding=0)uniform sampler2D source_color;
layout(set=0,binding=1)uniform sampler2D blur1;
layout(set=0,binding=2)uniform sampler2D blur2;
layout(set=0,binding=3)uniform sampler2D blur3;
layout(set=0,binding=4)uniform sampler2D blur4;
layout(set=0,binding=5)uniform sampler2D blur5;
layout(location=0)out vec4 out_color;
layout(push_constant,std430)uniform Params{vec4 size_mode_kernel;vec4 direction_threshold_strength;vec4 radius_pad;vec4 reserved;}p;
const float centers[5]=float[5](0.1994700000,0.1196820000,0.08548714286,0.06649000000,0.05440090909);
const int pairs[5]=int[5](3,5,7,9,11);
const vec2 taps[55]=vec2[55](vec2(1.407333400,0.2970163279),
vec2(3.294214972,0.09175375661),
vec2(5.000000000,0.008764100150),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(1.466301165,0.2143825001),
vec2(3.421894767,0.1380806022),
vec2(5.378716405,0.06253996870),
vec2(7.337378163,0.01991332406),
vec2(9.000000000,0.003126262574),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(1.482787417,0.1615327822),
vec2(3.459907687,0.1287340360),
vec2(5.437195706,0.08555930155),
vec2(7.414744034,0.04742132242),
vec2(9.392640965,0.02191797951),
vec2(11.37096919,0.008447578272),
vec2(13.00000000,0.001765199911),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(1.489584840,0.1284697563),
vec2(3.475713571,0.1119182490),
vec2(5.461879674,0.08731326756),
vec2(7.448104233,0.06100111135),
vec2(9.434407975,0.03816557092),
vec2(11.42081115,0.02138356611),
vec2(13.40733340,0.01072902410),
vec2(15.39399368,0.004820686864),
vec2(17.00000000,0.001201009762),
vec2(0.000000000,0.000000000),
vec2(0.000000000,0.000000000),
vec2(1.493027312,0.1063123533),
vec2(3.483735080,0.09691539803),
vec2(5.474454081,0.08204439964),
vec2(7.465190699,0.06449885004),
vec2(9.455951267,0.04708705605),
vec2(11.44674205,0.03192252272),
vec2(13.43756924,0.02009733316),
vec2(15.42843893,0.01174964061),
vec2(17.41935707,0.006379034088),
vec2(19.41032953,0.003216093171),
vec2(21.00000000,0.0009013823527));
float factor(float f){return mix(f,1.2-f,p.radius_pad.x);}
void main(){
 vec2 uv=gl_FragCoord.xy/p.size_mode_kernel.xy;
 vec4 input_color=texture(source_color,uv);
 int mode=int(p.size_mode_kernel.z);
 if(mode==3){out_color=vec4(input_color.rgb+texture(blur1,uv).rgb,input_color.a);return;}
 if(mode==0){float lum=dot(input_color.rgb,vec3(.2126,.7152,.0722));float t=p.direction_threshold_strength.z;out_color=input_color*smoothstep(t,t+.01,lum);return;}
 if(mode==1){
  int kernel=int(p.size_mode_kernel.w);
  vec3 total=input_color.rgb*centers[kernel];
  for(int i=0;i<pairs[kernel];i++){
   vec2 tap=taps[kernel*11+i];vec2 offset=p.direction_threshold_strength.xy/p.size_mode_kernel.xy*tap.x;
   total+=(texture(source_color,uv+offset).rgb+texture(source_color,uv-offset).rgb)*tap.y;
  }
  out_color=vec4(total,1.0);return;
 }
 vec3 glow=3.0*p.direction_threshold_strength.w*(factor(1.0)*texture(blur1,uv).rgb+factor(.8)*texture(blur2,uv).rgb+factor(.6)*texture(blur3,uv).rgb+factor(.4)*texture(blur4,uv).rgb+factor(.2)*texture(blur5,uv).rgb);
 out_color=vec4(glow,max(glow.r,max(glow.g,glow.b)));
}
