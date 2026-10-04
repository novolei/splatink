// Preserve Three's actual bilinear Gaussian taps; no per-pixel exponentials.
import fs from 'node:fs/promises';
import {UnrealBloomPass} from '../../vendor/three/jsm/postprocessing/UnrealBloomPass.js';
import {Vector2} from 'three';
const bloom=new UnrealBloomPass(new Vector2(1280,720),.28,.45,2.4);
const kernels=bloom.separableBlurMaterials.map(m=>Object.fromEntries(
 ['centerWeight','gaussianOffsets','gaussianWeights'].map(k=>[k,m.uniforms[k].value])));
const num=v=>Number(v).toPrecision(10);
const centers=kernels.map(k=>num(k.centerWeight)).join(',');
const pairs=kernels.map(k=>k.gaussianOffsets.length).join(',');
const taps=kernels.flatMap(k=>Array.from({length:11},(_,i)=>`vec2(${num(k.gaussianOffsets[i]??0)},${num(k.gaussianWeights[i]??0)})`)).join(',\n');
const shader=`// Source UnrealBloomPass: half-resolution high-pass, five paired Gaussian levels.
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
const float centers[5]=float[5](${centers});
const int pairs[5]=int[5](${pairs});
const vec2 taps[55]=vec2[55](${taps});
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
`;
await fs.writeFile(new URL('../assets/shaders/source_bloom.glsl',import.meta.url),shader);
await fs.writeFile(new URL('../data/source_bloom.json',import.meta.url),JSON.stringify({kernels,factors:[1,.8,.6,.4,.2],alphaIntensity:3,smoothWidth:.01}));
console.log('Source bloom exported: 5 levels, '+kernels.map(k=>k.gaussianOffsets.length).join('/')+' paired taps');
