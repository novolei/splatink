// Execute the original cloud loop and Actor.damage/splat. Actor presentation
// and terrain are sinks; ownership, damage, kill attribution and event order
// remain the original code, including ghost clouds on each client's actors.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Projectiles} from '../../src/game/weapons.js';
import {Actor} from '../../src/game/actor.js';
import {Physics} from '../../src/game/physics.js';
import {G,on,rng} from '../../src/core/ctx.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const bytes=n=>{const b=Buffer.alloc(8);b.writeDoubleLE(n);return [...b];};
const V=a=>new THREE.Vector3(...a);
const cases=[
 {name:'offline_cloud_damage_team_and_alive_filter',online:false,ghost:false,ownerOwned:true,dt:.125,frames:4,actors:[{name:'owner',team:0,pos:[8,0,0],owned:true},{name:'enemy',team:1,pos:[0,0,0],owned:true},{name:'ally',team:0,pos:[0,0,1],owned:true},{name:'dead',team:1,pos:[1,0,0],owned:true,alive:false},{name:'outside',team:1,pos:[3.425,0,0],owned:true},{name:'above',team:1,pos:[0,5.25,0],owned:true}]},
 {name:'owned_cloud_does_not_send_duplicate_proxy_damage',online:true,ghost:false,ownerOwned:true,dt:.125,frames:4,actors:[{name:'owner',team:0,pos:[8,0,0],owned:true},{name:'owned_enemy',team:1,pos:[0,0,0],owned:true},{name:'foreign_enemy',team:1,pos:[1,0,0],owned:false}]},
 {name:'foreign_ghost_cloud_hurts_owned_actor',online:true,ghost:true,ownerOwned:false,dt:.125,frames:4,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'owned_enemy',team:1,pos:[0,0,0],owned:true},{name:'foreign_enemy',team:1,pos:[1,0,0],owned:false}]},
 {name:'foreign_ghost_cloud_owner_confirmed_kill',online:true,ghost:true,ownerOwned:false,dt:.125,frames:4,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'victim',team:1,pos:[0,0,0],owned:true,hp:8.5},{name:'foreign_victim',team:1,pos:[1,0,0],owned:false,hp:8.5}]},
 {name:'foreign_ghost_cloud_solid_ceiling_protects',online:true,ghost:true,ownerOwned:false,roof:2,dt:.125,frames:3,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'protected',team:1,pos:[0,0,0],owned:true}]},
 {name:'foreign_ghost_cloud_los_passes_grate',online:true,ghost:true,ownerOwned:false,roof:2,grate:true,dt:.125,frames:3,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'grate_victim',team:1,pos:[0,0,0],owned:true}]},
 {name:'foreign_ghost_cloud_invulnerability_and_slam_armor',online:true,ghost:true,ownerOwned:false,dt:.125,frames:3,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'invulnerable',team:1,pos:[0,0,0],owned:true,invuln:1},{name:'armored',team:1,pos:[1,0,0],owned:true,armor:true}]},
 {name:'foreign_ghost_cloud_exact_active_and_retirement_times',online:true,ghost:true,ownerOwned:false,dt:.125,frames:54,actors:[{name:'owner',team:0,pos:[8,0,0],owned:false},{name:'victim',team:1,pos:[0,0,0],owned:true,hp:1000}]},
];
const traces=[];
let recorded=[];
const unsub=['damage','splatted','hit','storm:end'].map(kind=>on(kind,data=>recorded.push({kind,victim:data.victim?.name||null,attacker:data.attacker?.name||null,amount:data.amount??data.damage??0,killed:data.killed??false,cause:data.cause??data.source??data.weaponId??null})));
for(const spec of cases){
 let contacts=[],paints=[],bossRain=0;
 Math.random=rng(417);
 const actors=spec.actors.map(a=>{
  const actor=Object.create(Actor.prototype);
  Object.assign(actor,{name:a.name,team:a.team,pos:V(a.pos),yaw:0,hp:a.hp??100,alive:a.alive??true,invuln:a.invuln??0,remote:spec.online&&!a.owned,isLocal:false,specialActive:a.armor?{armor:true}:null,special:0,hurtFlash:0,lastDamage:9,stats:{splats:0,deaths:0,turf:0},weapon:{specialCost:200},character:{trigger(){},setVisible(){}},weaponRunner:{onDeath(){}}});
  return actor;
 });
 const owner=actors[0],group=new THREE.Group(),scene=new THREE.Scene();scene.add(group);group.position.set(0,5,0);
 const c={owner,team:0,group,t:0,dur:6.5,dir:new THREE.Vector3(),rainT:0,ghost:spec.ghost};
 const projectiles=Object.create(Projectiles.prototype);projectiles.scene=scene;projectiles.clouds=[c];
 G.actors=actors;G.teamColors=[new THREE.Color('#ff8a14'),new THREE.Color('#2f5bff')];G.audio=null;G.fx=null;G.netm=spec.online?{}:null;G.local=null;
 G.paint={splat:(p,r)=>{paints.push({point:p.toArray(),radius:r});return 0;}};
 G.boss={rain(){bossRain++;}};
 G.physics={raycast:(p,d,length,out,skipGrates=false)=>{
  contacts.push({skipGrates,up:d.y>0,from:p.toArray(),length});out.hit=false;
  if(spec.roof!==undefined&&!(skipGrates&&spec.grate)&&Math.abs(d.y)>1e-8){const t=(spec.roof-p.y)/d.y;if(t>=0&&t<=length){out.hit=true;out.point.copy(p).addScaledVector(d,t);out.normal.set(0,d.y<0?1:-1,0);}}
  return out;
 },los:Physics.prototype.los};
 const frames=[];
 for(let i=0;i<spec.frames;i++){
  contacts=[];paints=[];recorded=[];bossRain=0;G.time=(i+1)*spec.dt;
  projectiles._updateClouds(spec.dt);
  frames.push({alive:projectiles.clouds.length>0,time:c.t,scale:group.scale.x,contacts,paintCount:paints.length,splatPaints:paints.filter(p=>p.radius===1.7).length,bossRain,events:[...recorded],actors:actors.map(a=>({name:a.name,hp:a.hp,alive:a.alive,splats:a.stats.splats,deaths:a.stats.deaths}))});
  if(!projectiles.clouds.length)break;
 }
 traces.push({input:{...spec,dt_f64:bytes(spec.dt)},frames});
}
for(const off of unsub)off();
await fs.writeFile(path.join(base,'data/storm_ownership.json'),JSON.stringify({source:'Unmodified Projectiles._updateClouds + Actor.damage/splat, Physics.los; each client damages its non-remote actors even under ghost clouds',traces}));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
