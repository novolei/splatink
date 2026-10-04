// High/ultra retain the web game's original 4096 atlas density; grid scoring is unchanged.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createCanvas} from '@napi-rs/canvas';
import * as THREE from 'three';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {PaintSystem} from '../../src/world/paint.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
globalThis.document={createElement:tag=>{if(tag==='canvas')return createCanvas(1,1);throw Error(tag);}};
for(const[id,layout]of Object.entries(MAP_LAYOUTS)){
 const kit=new PropKit(new THREE.Scene(),{quality:'high'}),colliders=[];
 for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
 const level=new Level(layout,colliders),paint=Object.create(PaintSystem.prototype);
 paint.level=level;paint.size=4096;paint.cell=.25;paint.pad=8;paint._layout(30);paint._initGrid();
 const files=[],meshes={};let offset=0;
 for(const[name,filter]of [['level',b=>!b.grate],['grates',b=>b.grate]]){
  const geometry=level.buildGeometry(4096,filter),uv=geometry.getAttribute('paintUv').array;
  if(!uv.length)continue;const bytes=Buffer.from(uv.buffer,uv.byteOffset,uv.byteLength);meshes[name]={offset,length:uv.length};offset+=bytes.length;files.push(bytes);
 }
 const data={size:4096,ppm:paint.ppm,faces:level.faces.map(f=>f.atlas||null),meshes};
 await fs.writeFile(path.join(out,'data',id+'_paint_high.json'),JSON.stringify(data));
 await fs.writeFile(path.join(out,'assets/world',id+'_paint_high.bin'),Buffer.concat(files));
 console.log(JSON.stringify({id,ppm:paint.ppm,bytes:offset}));
}
