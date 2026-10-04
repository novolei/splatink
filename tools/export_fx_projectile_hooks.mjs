// Execute original FxHooks polling and original sloshTrail, recording effects.
// Presentation and collision calls are sinks; original eligibility and distance
// clocks remain untouched.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let seed=9714321,random=[];
Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const v=seed/4294967296;random.push(v);return v;};
const {initFxHooks}=await import('../../src/fx/fxHooks.js');
const {FX}=await import('../../src/fx/fx.js');
const V=a=>new THREE.Vector3(...a);
const bytes=n=>{const b=Buffer.alloc(8);b.writeDoubleLE(n);return [...b];};
const color=new THREE.Color('#ff8a14');
const owner={color,team:0};
const kinds=['shooter','dualies','splatling','blaster','flick','slosherHead','slosherTail'];
const sourceKind=k=>k==='blaster'?'blast':k==='flick'?'drop':k.startsWith('slosher')?'slosh':'shot';
const traces=[];
for(const kind of kinds){
 const step=kind==='blaster'?.55:kind==='flick'?1.1:kind==='slosherHead'?.45:kind==='slosherTail'?1:.8;
 const frames=Array.from({length:22},(_,i)=>({dt:.125,age:i===18?.125:(i+1)*.125,delay:i===0?.25:-.1,pos:[i<8?0:i<14?31:0,1,0],vel:[0,0,step*8]}));
 // Early age, delay and recycled age boundaries use the actual source checks.
 frames[0].age=.02;frames[1].age=.03;frames[2].delay=1;
 frames[15].pos=[30,0,0];
 traces.push({name:kind,bullets:[{kind}],frames});
}
traces.push({name:'distance_reset_before_visibility_and_late_birth',bullets:[{kind:'shooter'}],frames:[
 {dt:.016,age:0,delay:.2,pos:[0,1,0],vel:[0,0,100]},
 {dt:.016,age:.016,delay:.184,pos:[0,1,0],vel:[0,0,100]},
 {dt:.016,age:.032,delay:-.001,pos:[0,1,0],vel:[0,0,100]},
 {dt:.016,age:.048,delay:-.001,pos:[36,1,0],vel:[0,0,100]},
 {dt:.016,age:.064,delay:-.001,pos:[0,1,0],vel:[0,0,1]},
 {dt:.016,age:.08,delay:-.001,pos:[0,1,0],vel:[0,0,100]},
]});
traces.push({name:'48_effect_shared_frame_budget',bullets:Array.from({length:64},(_,i)=>({kind:kinds[i%kinds.length]})),frames:[{dt:.125,age:.5,delay:0,pos:[0,1,0],vel:[0,0,20]},{dt:.125,age:.625,delay:0,pos:[0,1,0],vel:[0,0,20]}]});
for(const trace of traces){
 let effects=[];
 const fx={shotTrail:(p,v,c,big)=>effects.push({kind:big?'blaster':'shot',pos:p.toArray()}),sloshTrail:(p,v,c,head)=>effects.push({kind:head?'slosherHead':'slosherTail',pos:p.toArray()})};
 const g={fx,camera:{position:new THREE.Vector3()},teamColors:[color,color],level:null,paint:null};
 const hooks=initFxHooks(g);hooks.seen['weapon:fire']=true;
 const bullets=trace.bullets.map(b=>({type:sourceKind(b.kind),head:b.kind==='slosherHead',owner,pos:new THREE.Vector3(),vel:new THREE.Vector3(),age:0,delay:0}));
 for(const frame of trace.frames){
  // Both implementations receive the native physics Vector3 values; retain
  // source Float64 clocks independently of Godot's JSON decimal parser.
  frame.pos=frame.pos.map(Math.fround);frame.vel=frame.vel.map(Math.fround);
  frame.dt_f64=bytes(frame.dt);frame.age_f64=bytes(frame.age);frame.delay_f64=bytes(frame.delay);
  effects=[];
  for(const p of bullets)Object.assign(p,{age:frame.age,delay:frame.delay,pos:V(frame.pos),vel:V(frame.vel)});
  hooks.stamp++;hooks.time+=frame.dt;
  hooks._projectiles({list:bullets},frame.dt);
  frame.expected={effects,distances:bullets.map(p=>p._fxD),ages:bullets.map(p=>p._fxAge)};
 }
}
const recipes=[];
for(const head of [false,true])for(let i=0;i<32;i++){
 const fx=Object.create(FX.prototype);fx._col=new THREE.Color();fx._colCache=new Map();
 const drops=[];fx._spawnDrop=(px,py,pz,vx,vy,vz,c,size,life,gravity,stretch,flags)=>drops.push({pos:[px,py,pz],vel:[vx,vy,vz],color:[c.r,c.g,c.b],size,life,gravity,stretch,flags});
 const pos=[1.1,2.2,-3.3],vel=[4.4,5.5,-6.6];random=[];
 fx.sloshTrail(V(pos),V(vel),color,head);
 recipes.push({head,pos,vel,color:[color.r,color.g,color.b],random,drops});
}
await fs.writeFile(path.join(base,'data/fx_projectile_hooks.json'),JSON.stringify({source:'Unmodified FxHooks._projectiles and FX.sloshTrail',traces,recipes}));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0),recipes:recipes.length}));
