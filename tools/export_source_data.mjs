// Extracts source geometry, face grids and collider data without changing the web project.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createCanvas,GlobalFonts} from '@napi-rs/canvas';
import * as THREE from 'three';
import * as config from '../../src/config.js';
import * as styles from '../../src/game/character-style.js';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {PaintSystem} from '../../src/world/paint.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
import {Decor} from '../../src/world/decor.js';
import {createMuralTexture} from '../../src/world/murals.js';
import {G} from '../../src/core/ctx.js';
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
globalThis.document={createElement:(tag)=>{if(tag==='canvas')return createCanvas(1,1);throw new Error(tag);},fonts:{add(){}}};
for(const [font,family] of [['InkDisplay-Latin.ttf','InkwavePropsDisplay'],['InkBody-Latin.ttf','InkwavePropsText']]){
  GlobalFonts.registerFromPath('H:/GDP/mini-tanks/assets/fonts/'+font,family);
}
await fs.mkdir(path.join(out,'data'),{recursive:true});
await fs.mkdir(path.join(out,'assets/world'),{recursive:true});
await fs.mkdir(path.join(out,'assets/textures'),{recursive:true});
await fs.mkdir(path.join(out,'assets/licenses'),{recursive:true});
const serial=(x)=>JSON.parse(JSON.stringify(x,(_,v)=>typeof v==='function'?undefined:v));
await fs.writeFile(path.join(out,'data/config.json'),JSON.stringify(serial(config),null,2));
await fs.writeFile(path.join(out,'data/styles.json'),JSON.stringify(serial(styles),null,2));
await fs.copyFile(path.join(out,'../LICENSE'),path.join(out,'assets/licenses/INKWAVE-MIT.txt'));
let bytes=[],offset=0;
function chunk(array,type='f32'){
 const a=type==='u32'?new Uint32Array(array):type==='u8'?new Uint8Array(array):new Float32Array(array);
 const pad=(4-offset%4)%4;if(pad){bytes.push(Buffer.alloc(pad));offset+=pad;}
 const b=Buffer.from(a.buffer,a.byteOffset,a.byteLength),record={offset,length:a.length,type};bytes.push(b);offset+=b.length;return record;
}
function meshRecord(mesh,name=mesh.name){
 const geo=mesh.geometry;const attrs={};
 for(const [key,a] of Object.entries(geo.attributes)){attrs[key]={...chunk(a.array),size:a.itemSize};}
 mesh.updateWorldMatrix(true,false);
 const record={name,attributes:attrs,index:geo.index?chunk(geo.index.array,'u32'):null,transform:mesh.matrixWorld.toArray(),material:materialRecord(mesh.material),cast_shadow:mesh.castShadow};
 if(mesh.isInstancedMesh){record.instances=[];let m=new THREE.Matrix4(),c=new THREE.Color();for(let i=0;i<mesh.count;i++){mesh.getMatrixAt(i,m);if(mesh.instanceColor)mesh.getColorAt(i,c);record.instances.push({transform:m.toArray(),color:mesh.instanceColor?c.toArray():[1,1,1]});}}
 return record;
}
const textureIds=new Map();let texN=0;
function textureRecord(tex){
 if(!tex?.image?.toBuffer)return null;if(textureIds.has(tex))return textureIds.get(tex);
 const filename='source_'+String(texN++).padStart(3,'0')+'.png';textureIds.set(tex,filename);return filename;
}
function materialRecord(m){
 if(Array.isArray(m))m=m[0];if(!m)return {};
 const uniforms={},texture_uniforms={};for(const [k,u]of Object.entries(m.uniforms||{})){const v=u.value;if(v?.isColor)uniforms[k]=v.toArray();else if(typeof v==='number')uniforms[k]=v;else if(v?.isTexture)texture_uniforms[k]=textureRecord(v);}
 return {type:m.type,color:m.color?.toArray()||[1,1,1],roughness:m.roughness??0.55,metalness:m.metalness??0,clearcoat:m.clearcoat??0,clearcoat_roughness:m.clearcoatRoughness??.0525,env_map_intensity:m.envMapIntensity??1,specular_intensity:m.specularIntensity??1,emissive_intensity:m.emissiveIntensity??1,transparent:!!m.transparent,opacity:m.opacity??1,alpha_test:m.alphaTest||0,double_side:m.side===THREE.DoubleSide,emission:m.emissive?.toArray(),unlit:!!m.isMeshBasicMaterial,map:textureRecord(m.map),uniforms,texture_uniforms};
}
const summary=[];
for(const [id,layout]of Object.entries(MAP_LAYOUTS)){
 bytes=[];offset=0;const scene=new THREE.Scene(),kit=new PropKit(scene,{quality:'high'}),colliders=[];
 for(const p of dressingFor(id)){colliders.push(...kit.add(p.type,p).colliders);}kit.build();
 const lvl=new Level(layout,colliders);G.level=lvl;G.scene=scene;G.settings={quality:'high'};
 // Use the exact original packing + buried-face mask. GPU initialization is deliberately omitted.
 const paint=Object.create(PaintSystem.prototype);paint.level=lvl;paint.size=2048;paint.cell=.25;paint.pad=8;paint._layout(18);paint._initGrid();
 const lm=JSON.parse(await fs.readFile(path.join(out,'../assets/lightmaps',id+'.json'),'utf8'));lvl.layoutLightmap(lm.ppm,lm.size);
 await fs.copyFile(path.join(out,'../assets/lightmaps',id+'.png'),path.join(out,'assets/textures',id+'_ao.png'));
 const meshes=[];
 for(const [name,filter]of [['level',(b)=>!b.grate],['grates',(b)=>b.grate]]){const g=lvl.buildGeometry(2048,filter);if(g.index.count){const mesh=new THREE.Mesh(g,new THREE.MeshStandardMaterial({vertexColors:true}));mesh.castShadow=name==='level';mesh.receiveShadow=true;meshes.push(meshRecord(mesh,name));}}
 kit.group.updateMatrixWorld(true);kit.group.traverse(n=>{if(n.isMesh)meshes.push(meshRecord(n));});
 const decor=new Decor(scene,lvl);decor.setTeamColors?.([new THREE.Color('#ff3f9e'),new THREE.Color('#18d48c')]);decor.group.updateMatrixWorld(true);decor.group.traverse(n=>{if(n.isMesh)meshes.push(meshRecord(n));});
 const faces=lvl.faces.map(f=>({id:f.id,block:f.block,n:f.n.toArray(),u:f.u.toArray(),v:f.v.toArray(),origin:f.origin.toArray(),su:f.su,sv:f.sv,wall:f.wall,turf:f.turf,paintable:f.paintable,pattern:f.pattern,atlas:f.atlas,grid:f.grid,nu:f.nu,nv:f.nv,cu:f.cu,cv:f.cv}));
 const blocks=lvl.blocks.map(b=>({id:b.id,center:b.center.toArray(),half:b.half.toArray(),axes:b.axes.map(a=>a.toArray()),paint:b.paint,solid:b.solid,grate:b.grate,rail:b.rail,roof:b.roof,perch:b.perch,tag:b.tag,hidden:b.hidden}));
 const murals=await createMuralTexture(id);await fs.writeFile(path.join(out,'assets/textures',id+'_murals.png'),murals.image.toBuffer('image/png'));
 const data={id,layout,blocks,faces,meshes,murals:murals.userData.murals,atlas_size:2048,ppm:paint.ppm,grid_length:paint.grid.length,dead:chunk(paint.dead,'u8'),turf_total:paint.turfTotal,turf_area:paint.turfArea,light_size:lm.size,source_lightmap_valid:lvl.layoutHash===lm.hash};
 await fs.writeFile(path.join(out,'data',id+'.json'),JSON.stringify(data));await fs.writeFile(path.join(out,'assets/world',id+'.bin'),Buffer.concat(bytes));
 summary.push({id,blocks:blocks.length,faces:faces.length,meshes:meshes.length,placements:kit.count,vertices:meshes.reduce((s,m)=>s+m.attributes.position.length/3,0),bytes:offset,paint_ppm:paint.ppm});
 console.log(JSON.stringify(summary.at(-1)));
}
for(const [tex,name]of textureIds)await fs.writeFile(path.join(out,'assets/textures',name),tex.image.toBuffer('image/png'));
await fs.writeFile(path.join(out,'data/source_manifest.json'),JSON.stringify({generated_at:new Date().toISOString(),source:'INKWAVE original procedural source',maps:summary,textures:textureIds.size},null,2));
