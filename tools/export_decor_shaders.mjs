import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const source=await fs.readFile(path.join(root,'src/world/decor.js'),'utf8');
function constant(name){const match=source.match(new RegExp('const '+name+' = /\\* glsl \\*/`([\\s\\S]*?)`;'));if(!match)throw Error(name);return match[1];}
for(const [name,file] of [['PAD_FRAG','native_spawn_pad'],['BARRIER_FRAG','native_spawn_barrier']]){
 let body=constant(name).replace('${HASH}',constant('HASH')).replace('${OUT}','');
 body=body.replace(/varying [^;]+;/g,'').replace(/texture2D\(/g,'texture(').replace(/cameraPosition/g,'CAMERA_POSITION_WORLD').replace(/void main\(\)/,'void fragment()');
 body=body.replace(/gl_FragColor = vec4\(([^;]+)\);/,(_,args)=>{const comma=args.lastIndexOf(',');return `ALBEDO = ${args.slice(0,comma)}; ALPHA = ${args.slice(comma+1)};`;});
 const header=`// Port of the original INKWAVE decor.js ${name}.\nshader_type spatial;\nrender_mode unshaded, cull_disabled${name==='BARRIER_FRAG'?', depth_draw_never':''};\nvarying vec2 vUv; varying vec3 vW; varying vec3 vN;\nvoid vertex(){vUv=vec2(UV.x,1.0-UV.y);vW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=mat3(MODEL_MATRIX)*NORMAL;}\n`;
 await fs.writeFile(path.join(root,'splatink/assets/shaders',file+'.gdshader'),header+body);
}
