// Unmodified original delayed update/_step on rounds. Renderer and impact
// presentation are record-only; collision-free integration remains original.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Projectiles} from '../../src/game/weapons.js';
import {G} from '../../src/core/ctx.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const V=values=>new THREE.Vector3(...values);
const bytes=n=>{const b=Buffer.alloc(8);b.writeDoubleLE(n);return [...b];};
let seed=43321;Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
const specs=[
 {name:'shooter_60hz_straight_gravity_drag',kind:'shooter',pos:[0,8,0],vel:[0,3,34],life:1.2,straight:.13,gravity:28,drag:.8,dt:1/60,frames:90},
 {name:'dualies_144hz_motion',kind:'dualies',pos:[0,8,0],vel:[10,2,25],life:1.2,straight:.12,gravity:28,drag:.8,dt:1/144,frames:180},
 {name:'splatling_60hz_motion',kind:'splatling',pos:[0,8,0],vel:[-5,3,34],life:1.2,straight:.13,gravity:28,drag:.8,dt:1/60,frames:90},
 {name:'roller_drop_gravity_drag',kind:'flick',pos:[0,12,0],vel:[4,8,9],life:1.4,straight:0,gravity:26,drag:.4,dt:1/60,frames:95},
 {name:'slosh_head_first_delay_crossing',kind:'slosher',pos:[0,9,0],vel:[0,9,12],life:2.4,straight:0,gravity:26,drag:0,delay:.012,dt:1/60,frames:165},
 {name:'slosh_tail_multiple_delay_crossing',kind:'slosher',pos:[0,9,0],vel:[3,6,12],life:2.4,straight:0,gravity:26,drag:0,delay:.036,dt:1/60,frames:165},
 {name:'delay_exact_boundary_steps_same_frame',kind:'slosher',pos:[0,8,0],vel:[0,0,8],life:.25,straight:99,gravity:0,drag:0,delay:.125,dt:.125,frames:5},
 {name:'strict_round_lifetime_equal',kind:'shooter',pos:[0,8,0],vel:[0,0,8],life:.25,straight:99,gravity:0,drag:0,dt:.125,frames:4},
 {name:'strict_blaster_lifetime_equal',kind:'blaster',pos:[0,8,0],vel:[0,0,8],life:.25,straight:99,gravity:0,drag:0,dt:.125,frames:4},
 {name:'trail_equal_does_not_emit',kind:'shooter',pos:[0,1.5,0],vel:[0,0,8],life:1,straight:99,gravity:0,drag:0,trail:0,trailEvery:1,trailRadius:.45,dt:.125,frames:9},
 {name:'straight_equal_frame_has_no_gravity',kind:'shooter',pos:[0,8,0],vel:[0,0,8],life:.75,straight:.25,gravity:8,drag:.5,dt:.125,frames:8},
 {name:'source_low_frame_drag_not_clamped',kind:'flick',pos:[0,20,0],vel:[1,3,2],life:3,straight:0,gravity:1,drag:3,dt:.4,frames:8},
 {name:'sea_culls_strict_below_minus3_4',kind:'shooter',pos:[0,-3.3,0],vel:[0,-.8,0],life:2,straight:99,gravity:0,drag:0,dt:.125,frames:4},
];
const traces=[];
for(const spec of specs){
 const sourceType=spec.kind==='flick'?'drop':spec.kind==='blaster'?'blast':spec.kind==='slosher'?'slosh':'shot';
 const owner={color:new THREE.Color('#ff8a14'),team:0,addTurf:()=>{},isLocal:false};
 const p={type:sourceType,wid:['dualies','splatling'].includes(spec.kind)?spec.kind:null,owner,team:0,pos:V(spec.pos),prev:V(spec.pos),start:V(spec.pos),vel:V(spec.vel),age:0,life:spec.life,straight:spec.straight,grav:spec.gravity,drag:spec.drag,delay:spec.delay||0,size:spec.kind==='blaster'?.26:.15,radius:.8,damage:35,seed:.5,trail:spec.trail||0,trailEvery:spec.trailEvery||0,trailRadius:spec.trailRadius||0};
 let paints=[],bursts=[];
 G.actors=[];G.boss=null;G.fx=null;G.audio=null;G.netm=null;
 G.physics={segment:(_a,_b,out)=>Object.assign(out,{hit:false}),raycast:(pos,dir,range,out)=>Object.assign(out,{hit:pos.y>=0&&pos.y<=range,point:new THREE.Vector3(pos.x,0,pos.z),normal:new THREE.Vector3(0,1,0)})};
 G.paint={splat:(pos,radius,team)=>{paints.push({pos:pos.toArray(),radius,team});return 0;}};
 const projectiles=Object.create(Projectiles.prototype);projectiles.list=[p];projectiles.pool=[];
 projectiles._updateBombs=()=>{};projectiles._updateClouds=()=>{};projectiles._updateBeams=()=>{};projectiles._draw=()=>{};
 projectiles._blastBurst=(_p,at)=>bursts.push(at.toArray());
 const frames=[];
 for(let i=0;i<spec.frames;i++){
  paints=[];bursts=[];Projectiles.prototype.update.call(projectiles,spec.dt);
  frames.push({alive:projectiles.list.length>0,age:p.age,delay:p.delay,pos:p.pos.toArray(),vel:p.vel.toArray(),trail:p.trail,paints,bursts});
  if(!projectiles.list.length)break;
 }
 // Exact IEEE-754 input avoids Godot JSON's decimal-parser rounding changing
 // the strict age > life result at the 72nd 1/60-second source update.
 traces.push({input:{...spec,dt_f64:bytes(spec.dt),life_f64:bytes(spec.life)},frames});
}
await fs.writeFile(path.join(base,'data/projectile_motion.json'),JSON.stringify({source:'Unmodified Projectiles.update/_step with no actor/world contact; source clocks, integration, trail threshold and lifetime branches',traces},null,2));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
