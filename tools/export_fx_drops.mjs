// Original fixed Float32 droplet storage and unmodified spawn/update methods.
// Landing is record-only, isolating trajectory, pooling and contact precedence.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let seed=6441341,draws=[];
Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const v=seed/4294967296;draws.push(v);return v;};
const {FX}=await import('../../src/fx/fx.js');
const bytes=n=>{const b=Buffer.alloc(8);b.writeDoubleLE(n);return [...b];};
function pool(cap){return {dCap:cap,dN:0,_recycle:0,dP:new Float32Array(cap*3),dV:new Float32Array(cap*3),dC:new Float32Array(cap*3),dK:new Float32Array(cap*3),dA:new Float32Array(cap*8),gravity:17,waterY:-1.6,maxChecks:24,_checks:0,dGeo:{instanceCount:0,userData:{dyn:[]},attributes:Object.fromEntries(['aPosR','aVelS','aColA'].map(k=>[k,{array:new Float32Array(cap*4)}]))}};}
const drop=(options={})=>({pos:[0,10,0],vel:[1.2,2.3,-3.4],color:[.63,.23,1.23],size:.071,life:1.3,gravity:1.2,stretch:1.5,flags:0,...options});
const cases=[
 {name:'source_grow_fade_stretch_and_float32',cap:8,dt:1/60,frames:85,specs:[drop(),drop({vel:[0,0,0],stretch:0,gravity:0}),drop({vel:[40,0,0],stretch:3,size:.032}),drop({life:.135,size:.018,flags:16}),drop({life:.45,size:.025,flags:4})]},
 {name:'144hz_original_float32_rounding',cap:5,dt:1/144,frames:200,specs:[drop({life:.89}),drop({vel:[-6.3,-9.4,2.8],flags:8,life:.61}),drop({life:1.29,gravity:0,stretch:.4})]},
 {name:'expiry_forward_swap_preserves_particle_order',cap:8,dt:.125,frames:12,specs:[drop({life:.125}),drop({life:.5}),drop({life:.25}),drop({life:1.1}),drop({life:.75}),drop({life:.375})]},
 {name:'source_overflow_seven_stride_replacement',cap:3,dt:.016,frames:68,specs:Array.from({length:13},(_,i)=>drop({pos:[i*.4,20,-i*.1],life:.24+i*.06,gravity:.2,vel:[i,-i*.1,2.5]}))},
 {name:'long_frame_drag_unclamped',cap:4,dt:3.2,frames:3,specs:[drop({life:8,gravity:0}),drop({life:10,gravity:.04,pos:[0,30,0]}),drop({life:3.1})]},
 {name:'water_crossing_interpolates_x_z_and_retires',cap:4,dt:.1,frames:2,specs:[drop({pos:[1,-1.5,2],vel:[8,-4,3],gravity:0,flags:4}),drop({pos:[2,-1.4,3],vel:[-2,-2,8],gravity:.3,flags:8})]},
 {name:'world_hit_precedes_water_in_same_segment',cap:4,dt:.1,frames:2,collider:{floor:-1.7},specs:[drop({pos:[0,-1.5,0],vel:[4,-5,3],gravity:0,flags:1}),drop({pos:[2,-1.5,0],vel:[1,-5,0],gravity:0,flags:4})]},
 {name:'no_collide_flags_leave_probe_point_current',cap:4,dt:.05,frames:7,collider:{floor:0},specs:[drop({pos:[0,.12,0],vel:[0,-2,0],gravity:0,flags:4}),drop({pos:[1,.12,0],vel:[0,-2,0],gravity:0,flags:0}),drop({pos:[2,.12,0],vel:[0,-2,0],gravity:0,flags:16})]},
];
const traces=[];
for(const c of cases){
 const fx=Object.assign(Object.create(FX.prototype),pool(c.cap));
 let landings=[];fx._landDrop=(i,...args)=>landings.push({pos:args.slice(0,3),normal:args.slice(3,6),water:args[6],size:fx.dA[i*8],flags:fx.dA[i*8+7],color:[...fx.dC.slice(i*3,i*3+3)]});
 if(c.collider)fx.collider=(a,b)=>{
  const y=c.collider.floor;
  if(a.y>=y&&b.y<y)return {point:a.clone().lerp(b,(a.y-y)/(a.y-b.y)),normal:new THREE.Vector3(0,1,0)};
  return null;
 };
 const operations=[];
 for(const s of c.specs){
  draws=[];fx._spawnDrop(...s.pos,...s.vel,{r:s.color[0],g:s.color[1],b:s.color[2]},s.size,s.life,s.gravity,s.stretch,s.flags);
  operations.push({input:s,random:draws});
 }
 const frames=[];
 for(let f=0;f<c.frames;f++){
  fx._checks=0;landings=[];fx._updateDrops(c.dt);
  const records=Array.from({length:fx.dN},(_,i)=>({p:[...fx.dP.slice(i*3,i*3+3)],v:[...fx.dV.slice(i*3,i*3+3)],c:[...fx.dC.slice(i*3,i*3+3)],probe:[...fx.dK.slice(i*3,i*3+3)],a:[...fx.dA.slice(i*8,i*8+8)],position_radius:[...fx.dGeo.attributes.aPosR.array.slice(i*4,i*4+4)],velocity_stretch:[...fx.dGeo.attributes.aVelS.array.slice(i*4,i*4+4)],color_gloss:[...fx.dGeo.attributes.aColA.array.slice(i*4,i*4+4)]}));
  frames.push({dt:c.dt,dt_f64:bytes(c.dt),count:fx.dN,checks:fx._checks,records,landings});
 }
 traces.push({name:c.name,capacity:c.cap,collider:c.collider||null,operations,frames});
}
await fs.writeFile(path.join(base,'data/fx_drops.json'),JSON.stringify({source:'Unmodified FX._spawnDrop/_updateDrops with source Float32 arrays; _landDrop is record-only',traces}));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
