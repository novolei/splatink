// Execute unmodified original Projectiles._updateBombs. Native backend fixtures
// receive these exact inputs; physics/presentation sinks report contact masks,
// throw clocks and cloud/explosion moments without altering the source loop.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Projectiles} from '../../src/game/weapons.js';
import {G} from '../../src/core/ctx.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const bytes=n=>{const b=Buffer.alloc(8);b.writeDoubleLE(n);return [...b];};
const V=a=>new THREE.Vector3(...a);
const cases=[
 {name:'bomb_floor_bounce_arm_fuse',kind:'bomb',pos:[0,3,0],vel:[4,-3,8],dt:1/60,frames:130,planes:[{point:[0,0,0],normal:[0,1,0]}]},
 {name:'bomb_lateral_wall_then_floor',kind:'bomb',pos:[0,3,0],vel:[0,3,13],dt:1/60,frames:130,planes:[{point:[0,0,4],normal:[0,0,-1]},{point:[0,0,0],normal:[0,1,0]}]},
 {name:'bomb_hits_grate_and_arms',kind:'bomb',pos:[0,3,0],vel:[4,-2,3],dt:1/60,frames:130,planes:[{point:[0,1,0],normal:[0,1,0],grate:true}]},
 {name:'bomb_steep_face_bounce_keeps_unarmed',kind:'bomb',pos:[0,4,0],vel:[-2,-3,5],dt:.125,frames:30,planes:[{point:[0,0,0],normal:[.8,.59,0]}]},
 {name:'storm_pod_spawns_on_grate',kind:'storm_pod',pos:[0,2,0],vel:[2,-3,5],dt:1/60,frames:90,planes:[{point:[0,1,0],normal:[0,1,0],grate:true}]},
 {name:'storm_pod_spawns_on_wall',kind:'storm_pod',pos:[0,8,0],vel:[0,3,16],dt:1/60,frames:90,planes:[{point:[0,0,4],normal:[0,0,-1]}]},
 {name:'storm_pod_strict_1_1_seconds',kind:'storm_pod',pos:[0,100,0],vel:[4,0,3],dt:.55,frames:4,planes:[]},
 {name:'bomb_original_has_no_8_second_air_timeout',kind:'bomb',pos:[0,1500,0],vel:[0,0,0],dt:.25,frames:38,planes:[]},
];
const traces=[];
for(const spec of cases){
 let contacts=[],audio=[],bursts=[],clouds=[];
 const owner={isLocal:false,remote:false,team:0,color:new THREE.Color('#ff8a14')};
 const projectile=Object.create(Projectiles.prototype);projectile.scene=new THREE.Scene();projectile.bombs=[];projectile.clouds=[];
 projectile._explodeBomb=b=>bursts.push(b.pos.toArray());
 projectile._spawnCloud=b=>{clouds.push(b.pos.toArray());projectile.clouds.push({ghost:false});};
 spec.spin=spec.kind==='storm_pod'?[4,6,0]:[3,5,0];
 const b={kind:spec.kind==='storm_pod'?'storm':'bomb',owner,team:0,pos:V(spec.pos),vel:V(spec.vel),mesh:new THREE.Group(),body:{material:{emissiveIntensity:0}},age:0,fuse:-1,beepT:0,spin:V(spec.spin),dir:V(spec.vel).setY(0).normalize()};
 projectile.bombs=[b];
 G.boss=null;G.netm=null;G.camera={position:new THREE.Vector3()};G.audio={play:(name,options={})=>audio.push({name,volume:options.volume,pitch:options.pitch})};
 G.physics={segment:(a,z,out,skipGrates=false)=>{
  contacts.push({skipGrates});let best=Infinity,hit=null;
  for(const plane of spec.planes){
   if(skipGrates&&plane.grate)continue;
   const p=V(plane.point),n=V(plane.normal).normalize(),da=a.clone().sub(p).dot(n),dz=z.clone().sub(p).dot(n);
   if(da>=0&&dz<0){const t=da/(da-dz);if(t<best){best=t;hit={point:a.clone().lerp(z,t),normal:n};}}
  }
  Object.assign(out,{hit:!!hit});if(hit)Object.assign(out,hit);return out;
 }};
 const frames=[];
 for(let i=0;i<spec.frames;i++){
  contacts=[];audio=[];bursts=[];clouds=[];
  projectile._updateBombs(spec.dt);
  frames.push({alive:projectile.bombs.length>0,age:b.age,fuse:b.fuse,beep:b.beepT,pos:b.pos.toArray(),vel:b.vel.toArray(),rotation:[b.mesh.rotation.x,b.mesh.rotation.z],scale:b.mesh.scale.toArray(),contacts,audio,bursts,clouds});
  if(!projectile.bombs.length)break;
 }
 traces.push({input:{...spec,dt_f64:bytes(spec.dt)},frames});
}
await fs.writeFile(path.join(base,'data/throwables.json'),JSON.stringify({source:'Unmodified Projectiles._updateBombs, default false grate mask, original bounce/fuse/expiry branch order',traces}));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
