import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const source=await fs.readFile(path.join(root,'src/world/paint.js'),'utf8');
let fragment=source.match(/const PAINT_FS = \/\* glsl \*\/`([\s\S]*?)`;/)[1];
fragment=fragment.replace('precision highp float;','').replace(/varying (vec\d) (\w+);/g,(_,type,name)=>`layout(location=${['vLocal','vSplat','vStretch','vGrow'].indexOf(name)}) in ${type} ${name};`);
fragment=fragment.replaceAll('${BAND_L}','0.55').replaceAll('${BAND_W}','0.62').replaceAll('${BAND_R}','0.1');
fragment=fragment.replace('void main() {','void main() {\n  if(control.x < 0.0){outColor=vec4(0.0,control.y,0.0,0.0);return;}').replace(/gl_FragColor/g,'outColor');
const vertex=`#version 450
layout(set=0,binding=0,std430) readonly buffer Brushes {vec4 data[];} brushes;
layout(push_constant,std430) uniform Params {vec4 control;};
layout(location=0) out vec3 vLocal;
layout(location=1) out vec4 vSplat;
layout(location=2) out vec3 vStretch;
layout(location=3) out vec4 vGrow;
void main(){
 int corner[6]=int[](0,1,2,0,2,3);int c=corner[gl_VertexIndex%6];
 if(control.x<0.0){vec2 p=vec2(c==1||c==2?1.0:0.0,c>=2?1.0:0.0);gl_Position=vec4(p*2.0-1.0,0.0,1.0);vLocal=vec3(0.0);vSplat=vec4(0.0);vStretch=vec3(0.0);vGrow=vec4(0.0);return;}
 int b=(gl_VertexIndex/6)*5;vec4 rect=brushes.data[b],atlas=brushes.data[b+1];
 vec2 pixel=vec2(c==1||c==2?rect.z:rect.x,c>=2?rect.w:rect.y);
 gl_Position=vec4(pixel/control.z*2.0-1.0,0.0,1.0);
 vLocal=vec3((pixel-atlas.xy)/atlas.z,atlas.w);vSplat=brushes.data[b+2];vStretch=brushes.data[b+3].xyz;vGrow=brushes.data[b+4];
}`;
const header=`#version 450\nlayout(push_constant,std430) uniform Params {vec4 control;};\nlayout(location=0) out vec4 outColor;\n`;
await fs.writeFile(path.join(root,'splatink/assets/shaders/source_paint.glsl'),'// Original INKWAVE paint.js brush SDF and blending. Native GPU atlas architecture also reviewed against novolei/godot-splatoon-paint.\n#[vertex]\n'+vertex+'\n#[fragment]\n'+header+fragment);
