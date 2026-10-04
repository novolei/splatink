// Export the original Minimap raster/shading and exact CPU turf-cell projection once per stage/viewer.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import * as THREE from 'three';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {PaintSystem} from '../../src/world/paint.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
import {Minimap} from '../../src/game/minimap.js';
import {G} from '../../src/core/ctx.js';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {createCanvas}=require('@napi-rs/canvas');
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
globalThis.document={createElement:tag=>{if(tag==='canvas')return createCanvas(1,1);throw Error(tag);},fonts:{add(){}}};
globalThis.requestIdleCallback=()=>0;
await fs.mkdir(path.join(out,'assets/minimap'),{recursive:true});
await fs.mkdir(path.join(out,'data/minimap'),{recursive:true});
const summary=[];
for(const[id,layout]of Object.entries(MAP_LAYOUTS)){
 const kit=new PropKit(new THREE.Scene(),{quality:'high'}),colliders=[];
 for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
 const level=new Level(layout,colliders),paint=Object.create(PaintSystem.prototype);
 paint.level=level;paint.size=2048;paint.cell=.25;paint.pad=8;paint._layout(18);paint._initGrid();
 const native=JSON.parse(await fs.readFile(path.join(out,'data',id+'.json'),'utf8'));
 if(native.grid_length!==paint.grid.length)throw Error(id+' native/source grid size mismatch');
 const map=new Minimap(level,paint,7);
 const meta={version:1,source:'src/game/minimap.js',stage:id,bounds:layout.bounds,width:map.w,height:map.h,px_per_m:7,grid_length:paint.grid.length,grid_width:512,viewers:[]};
 for(const viewer of [0,1]){
  map.flip=viewer===1;map._build();
  const n=map.w*map.h,projection=new Float32Array(n*4);let valid=0;
  for(let i=0;i<n;i++){
   const o=i*4;projection[o]=map.pixCell[i];projection[o+1]=map.pixFx[i]*256+map.pixFy[i];projection[o+2]=map.pixSx[i];projection[o+3]=map.pixSy[i];
   if(map.pixCell[i]>=0)valid++;
  }
  const prefix=id+'_'+viewer;
  await fs.writeFile(path.join(out,'assets/minimap',prefix+'_cells.bin'),Buffer.from(projection.buffer));
  for(const theme of ['day','sunset']){
   G.game={theme};map._drawBase();
   await fs.writeFile(path.join(out,'assets/minimap',prefix+'_'+theme+'.png'),map.base.toBuffer('image/png'));
  }
  meta.viewers.push({team:viewer,projection:'res://assets/minimap/'+prefix+'_cells.bin',bases:{day:'res://assets/minimap/'+prefix+'_day.png',sunset:'res://assets/minimap/'+prefix+'_sunset.png'},turf_pixels:valid});
 }
 await fs.writeFile(path.join(out,'data/minimap',id+'.json'),JSON.stringify(meta));
 summary.push({stage:id,width:map.w,height:map.h,grid:paint.grid.length,turf:meta.viewers.map(x=>x.turf_pixels)});
 console.log(JSON.stringify(summary.at(-1)));
}
await fs.writeFile(path.join(out,'data/minimap/manifest.json'),JSON.stringify({source:'INKWAVE original Minimap._build/_drawBase',stages:summary},null,2));
