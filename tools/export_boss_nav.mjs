// Bake the original BossNav clearance fields, including the original decorative collision boxes.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import * as THREE from 'three';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
import {BossNav} from '../../src/boss/bossNav.js';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {createCanvas}=require('@napi-rs/canvas');
globalThis.document={createElement:()=>createCanvas(1,1),fonts:{add(){}}};
globalThis.requestIdleCallback=()=>0;
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
await fs.mkdir(path.join(out,'assets/boss_nav'),{recursive:true});
await fs.mkdir(path.join(out,'data/boss_nav'),{recursive:true});
for(const[id,layout]of Object.entries(MAP_LAYOUTS)){
 const kit=new PropKit(new THREE.Scene(),{quality:'high'}),colliders=[];
 for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
 const nav=new BossNav(new Level(layout,colliders)),N=nav.nx*nav.nz,fields=new Float32Array(N*5);
 for(let i=0;i<N;i++)fields.set([nav.floor[i],nav.Dw[i],nav.Dv[i],nav.kind[i],nav.plan[i]],i*5);
 let sx=0,sz=0;for(const i of nav.planIds){const[x,z]=nav.xz(i);sx+=x;sz+=z;}
 const n=Math.max(1,nav.planIds.length),cx=sx/n,cz=sz/n;let best=-1,score=-Infinity;
 for(const i of nav.planIds){const[x,z]=nav.xz(i),s=Math.min(nav.Dw[i],6)*1.5+Math.min(nav.Dv[i],5)-Math.hypot(x-cx,z-cz)*.25;if(s>score){score=s;best=i;}}
 const spawn=best>=0?nav.xz(best):[0,0];spawn.splice(1,0,nav.floorAt(...spawn));
 let yaw=Math.atan2(nav.pads[0].x-spawn[0],nav.pads[0].z-spawn[2]);
 for(let k=0;k<24&&!nav.turnOk(spawn[0],spawn[2],yaw);k++)yaw+=(k%2?1:-1)*k*.13;
 const probes=[];
 for(const i of [0,Math.floor(N/3),Math.floor(N/2),N-1,...nav.planIds.filter((_,i)=>i%Math.max(1,Math.floor(nav.planIds.length/12))===0).slice(0,12)]){
  const[x,z]=nav.xz(i);probes.push({i,x,z,kind:nav.kindAt(x,z),floor:nav.floorAt(x,z),wall:nav.wallClear(x,z),drop:nav.floorClear(x,z),plan:nav.isPlan(x,z),pose:nav.poseOk(x,z,yaw),turn:nav.turnOk(x,z,yaw),lane:nav.cast(x,z,yaw,34)});
 }
 const paths=[];
 for(const f of [.1,.35,.65]){const start=nav.xz(nav.planIds[Math.floor(nav.planIds.length*f)]),end=nav.xz(nav.planIds[Math.floor(nav.planIds.length*(1-f))]);paths.push({start,end,path:nav.path(...start,...end)});}
 await fs.writeFile(path.join(out,'assets/boss_nav',id+'.bin'),Buffer.from(fields.buffer));
 await fs.writeFile(path.join(out,'data/boss_nav',id+'.json'),JSON.stringify({source:'src/boss/bossNav.js exact _build',stage:id,x0:nav.x0,z0:nav.z0,nx:nav.nx,nz:nav.nz,step:nav.step,floor_y:nav.floorY,pads:nav.pads,area:nav.area,spawn,yaw,fields:'res://assets/boss_nav/'+id+'.bin',probes,paths},null,2));
 console.log(JSON.stringify({stage:id,cells:N,plan:nav.planIds.length,area:nav.area,spawn,yaw}));
}
