// Original area attacks and Physics.los determine these contacts. This fixture
// leaves their offsets, near-end clipping, ordering and exclusions untouched.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Projectiles} from '../../src/game/weapons.js';
import {Actor} from '../../src/game/actor.js';
import {Physics} from '../../src/game/physics.js';
import {G,rng} from '../../src/core/ctx.js';
import {SPECIALS} from '../../src/config.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const V=a=>new THREE.Vector3(...a);
const cases=[];
for(const kind of ['bomb','blaster','slosh','slam']){
 const x=kind==='slosh'?1:2;
 const common={kind,pos:[0,0,0],actors:[{name:'owner',team:0,pos:[8,0,0]},{name:'enemy',team:1,pos:[x,0,0]},{name:'friendly',team:0,pos:[0,0,0]},{name:'dead',team:1,pos:[0,0,0],alive:false},{name:'outside',team:1,pos:[8,0,0]}]};
 cases.push({...common,name:kind+'_clear'});
 cases.push({...common,name:kind+'_solid_cover',wall:x*.5});
 cases.push({...common,name:kind+'_cover_25cm_before_victim',wall:x-.25});
 cases.push({...common,name:kind+'_last_25mm_ignored_by_source_los',wall:x-.025});
 cases.push({...common,name:kind+'_last_65mm_blocks_source_los',wall:x-.065});
 cases.push({...common,name:kind+'_grate_ignored_by_source_los',wall:x*.5,grate:true});
}
cases.push({name:'blaster_source_los_begins_at_burst_without_30cm_lift',kind:'blaster',pos:[0,0,0],wall:.25,minY:.02,maxY:.15,actors:[{name:'owner',team:0,pos:[8,0,0]},{name:'enemy',team:1,pos:[2,0,0]}]});
cases.push({name:'slosh_direct_and_prior_volley_victim_exclusion',kind:'slosh',pos:[0,0,0],direct:'direct',prior:['prior'],actors:[{name:'owner',team:0,pos:[8,0,0]},{name:'direct',team:1,pos:[.5,0,0]},{name:'prior',team:1,pos:[.75,0,0]},{name:'fresh',team:1,pos:[1,0,0]}]});
cases.push({name:'blaster_direct_victim_exclusion',kind:'blaster',pos:[0,0,0],direct:'direct',actors:[{name:'owner',team:0,pos:[8,0,0]},{name:'direct',team:1,pos:[.5,0,0]},{name:'fresh',team:1,pos:[2,0,0]}]});
cases.push({name:'slam_kill_radius_and_edge_falloff',kind:'slam',pos:[0,0,0],actors:[{name:'owner',team:0,pos:[8,0,0]},{name:'inner',team:1,pos:[3.125,0,0]},{name:'outer',team:1,pos:[4,0,0]},{name:'edge',team:1,pos:[5.2,0,0]}]});
const traces=[];
for(const spec of cases){
 let contacts=[],hits=[];
 Math.random=rng(801);
 const actors=spec.actors.map(s=>({name:s.name,team:s.team,pos:V(s.pos),alive:s.alive??true,isLocal:false,color:new THREE.Color(s.team?'#2f5bff':'#ff8a14'),addTurf(){}}));
 const owner=actors[0],attack=Object.create(Projectiles.prototype);
 attack.applyHit=(_a,e,damage,weapon)=>hits.push({name:e.name,damage,weapon});
 G.projectiles=attack;G.actors=actors;G.local=null;G.fx=null;G.audio=null;G.boss=null;G.netm=null;G.camera={position:new THREE.Vector3()};G.teamColors=[owner.color,new THREE.Color('#2f5bff')];G.paint={splat:()=>0};
 G.physics={los:Physics.prototype.los,raycast:(p,d,length,out,skipGrates=false)=>{
  contacts.push({skipGrates,from:p.toArray(),to:p.clone().addScaledVector(d,length).toArray()});out.hit=false;
  if(spec.wall!==undefined&&!(skipGrates&&spec.grate)&&Math.abs(d.x)>1e-8){
   const t=(spec.wall-p.x)/d.x,y=p.y+d.y*t;
   if(t>=0&&t<=length&&y>=(spec.minY??-Infinity)&&y<=(spec.maxY??Infinity)){out.hit=true;out.point.copy(p).addScaledVector(d,t);out.normal.set(-1,0,0);out.dist=t;}
  }
  return out;
 }};
 const direct=actors.find(a=>a.name===spec.direct)||null;
 if(spec.kind==='bomb')attack._explodeBomb({owner,team:0,pos:V(spec.pos)});
 else if(spec.kind==='blaster')attack._blastBurst({owner,team:0},V(spec.pos),direct);
 else if(spec.kind==='slosh')attack._sloshSplash({owner,team:0,wid:'slosher',vol:{hits:actors.filter(a=>spec.prior?.includes(a.name))}},V(spec.pos),direct);
 else {
  const slamActor=Object.create(Actor.prototype);Object.assign(slamActor,{team:0,pos:V(spec.pos),isLocal:false,stats:{turf:0}});
  // Keep the source owner identity in applyHit, without requiring visuals.
  attack.applyHit=(_a,e,damage,weapon)=>hits.push({name:e.name,damage,weapon});
  slamActor._slamImpact(SPECIALS.slam);
 }
 traces.push({input:spec,hits,contacts});
}
await fs.writeFile(path.join(base,'data/area_contacts.json'),JSON.stringify({source:'Unmodified bomb/blaster/slosh/slam source attack methods and Physics.los len-.05, skipGrates=true',traces}));
console.log(JSON.stringify({traces:traces.length,hits:traces.reduce((n,t)=>n+t.hits.length,0)}));
