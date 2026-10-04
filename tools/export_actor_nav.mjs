// Bake the source 1m multi-floor navigation graph once. The native solver keeps
// source edge order, costs, step/jump/drop kinds and enemy spawn-zone filtering.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import * as THREE from 'three';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
import {NavGraph} from '../../src/game/nav.js';
import {PaintSystem} from '../../src/world/paint.js';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {createCanvas}=require('@napi-rs/canvas');
globalThis.document={createElement:()=>createCanvas(1,1),fonts:{add(){}}};
globalThis.requestIdleCallback=()=>0;
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
await fs.mkdir(path.join(out,'assets/actor_nav'),{recursive:true});
await fs.mkdir(path.join(out,'data/actor_nav'),{recursive:true});
await fs.mkdir(path.join(out,'data/level_queries'),{recursive:true});
for(const[id,layout]of Object.entries(MAP_LAYOUTS)){
 const kit=new PropKit(new THREE.Scene(),{quality:'high'}),colliders=[];
 for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
 const level=new Level(layout,colliders),nav=new NavGraph(level,null),N=nav.nodes.length;
 const positions=new Float64Array(N*3),zones=new Int32Array(N),valid=nav.valid,offsets=new Int32Array(N+1),targets=[],costs=[],types=[];
 for(const n of nav.nodes){positions.set([n.x,n.y,n.z],n.id*3);zones[n.id]=n.zone;offsets[n.id]=targets.length;for(const e of n.nb){targets.push(e.to);costs.push(e.cost);types.push(['walk','jump','drop'].indexOf(e.type));}}offsets[N]=targets.length;
 const cellOffsets=new Int32Array(nav.cells.length+1),cellIds=[];
 nav.cells.forEach((list,i)=>{cellOffsets[i]=cellIds.length;cellIds.push(...list);});cellOffsets[nav.cells.length]=cellIds.length;
 const sections={},parts=[];let bytes=0;
 for(const[name,array]of Object.entries({positions,zones,valid,offsets,targets:Int32Array.from(targets),costs:Float64Array.from(costs),types:Uint8Array.from(types),cell_offsets:cellOffsets,cell_ids:Int32Array.from(cellIds)})){
  const data=Buffer.from(array.buffer,array.byteOffset,array.byteLength);sections[name]={offset:bytes,bytes:data.length};parts.push(data);bytes+=data.length;
 }
 const probes=[];
 for(const fraction of [0,.1,.25,.4,.55,.7,.9,.99]){
  const n=nav.nodes[nav.validIds[Math.floor(fraction*(nav.validIds.length-1))]];
  for(const delta of [[0,0,0],[.49,.8,-.49],[-.51,-1.5,.51]]){
   const pos=new THREE.Vector3(n.x+delta[0],n.y+delta[1],n.z+delta[2]);probes.push({pos:pos.toArray(),max_up:.8,id:nav.nearest(pos,.8)});
  }
 }
 const paths=[];
 for(const fraction of [.1,.3,.65])for(const team of [0,1]){
  const from=nav.validIds[Math.floor(nav.validIds.length*fraction)],to=nav.validIds[Math.floor(nav.validIds.length*(1-fraction))];
  paths.push({from,to,team,path:nav.path(from,to,team)});
 }
 await fs.writeFile(path.join(out,'assets/actor_nav',id+'.bin'),Buffer.concat(parts));
 await fs.writeFile(path.join(out,'data/actor_nav',id+'.json'),JSON.stringify({source:'src/game/nav.js exact _build + original dressing colliders',stage:id,nodes:N,edges:targets.length,x0:nav.x0,z0:nav.z0,nx:nav.nx,nz:nav.nz,step:nav.step,fields:'res://assets/actor_nav/'+id+'.bin',sections,probes,paths},null,2));
 const paint=Object.create(PaintSystem.prototype);paint.level=level;paint.size=2048;paint.pad=8;paint.cell=.25;paint._layout(30);paint._initGrid();
 for(let i=0;i<paint.grid.length;i++)paint.grid[i]=(i*13+(i>>3))%3;
 const queries=[];
 for(const fraction of [0,.08,.2,.33,.5,.7,.88,.99]){
  const n=nav.nodes[nav.validIds[Math.floor(fraction*(nav.validIds.length-1))]];
  for(const radius of [1.2,2.5,3.5]){
   const p=[n.x,n.y,n.z];queries.push({pos:p,radius,blocks:level.queryBlocks(n.x-radius,n.z-radius,n.x+radius,n.z+radius,[]),ground:level.groundHeight(n.x,n.z,n.y+1.2),stats:[0,1].map(team=>paint.regionStats(...p,radius,team))});
  }
 }
 await fs.writeFile(path.join(out,'data/level_queries',id+'.json'),JSON.stringify({source:'Level.queryBlocks/groundHeight + PaintSystem.regionStats exact CPU queries',grid_length:paint.grid.length,queries},null,2));
 console.log(JSON.stringify({stage:id,nodes:N,valid:nav.validIds.length,edges:targets.length,bytes}));
}
