// Capture original projectile routing and beam contacts by executing the
// unmodified source Projectiles methods. Renderer/paint callbacks record only.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Projectiles} from '../../src/game/weapons.js';
import {WEAPONS} from '../../src/config.js';
import {G,on} from '../../src/core/ctx.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let events=[],hits=[],impacts=[];
on('weapon:fire',d=>{if(d.weapon==='charger')events.push({len:d.len,charge:d.charge});});
on('weapon:impact',d=>impacts.push({kind:d.kind==='charger'?'beam':'contact',point:d.pos.toArray(),...(d.kind==='charger'?{}:{target:d.victim?.name||''})}));
G.fx=null;G.audio=null;G.input=null;G.camera=new THREE.PerspectiveCamera();G.time=1/60;
G.paint={splat:()=>0};
const actor=(name,z,x=0,form='kid',y=0)=>({name,pos:new THREE.Vector3(x,y,z),smoothY:0,form,team:1,alive:true});
const rows=[];
for(const kind of ['shooter','dualies','splatling','blaster','slosher_head','slosher_tail','flick']){
 const size=kind==='blaster'?.26:kind==='slosher_head'?.2:kind==='slosher_tail'?.14:.15;
 const threshold=.38*.95+size;
 for(const x of [threshold-.001,threshold+.001])for(const form of ['kid','squid'])rows.push({name:`${kind}_${form}_edge_${x<threshold?'inside':'outside'}`,kind,from:[0,.5,0],to:[0,.5,2],actors:[actor('enemy',1.2,x,form)],world:-1,boss:-1});
}
rows.push(
 {name:'actor_array_order_far_first',kind:'shooter',from:[0,.8,0],to:[0,.8,2.5],actors:[actor('far',2),actor('near',.75)],world:-1,boss:-1},
 {name:'actor_array_equal_distance',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[actor('first',1.2,.2),actor('second',1.2,-.2)],world:-1,boss:-1},
 {name:'wall_before_actor_source_priority',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[actor('behind_wall',1.4)],world:.5,boss:-1},
 {name:'actor_before_closer_boss',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[actor('enemy',1.4)],world:.7,boss:.3},
 {name:'boss_before_closer_wall',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[],world:.4,boss:1.2},
 {name:'world_when_no_actor_or_boss',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[],world:.4,boss:-1},
 {name:'fast_round_endpoint_broad_phase',kind:'shooter',from:[0,.8,0],to:[0,.8,12],actors:[actor('near_start',2)],world:-1,boss:-1},
 {name:'squid_high_shot_misses',kind:'shooter',from:[0,1.05,0],to:[0,1.05,2],actors:[actor('dry_squid',1.2,0,'squid')],world:-1,boss:-1},
 {name:'swim_visual_still_gameplay_squid',kind:'shooter',from:[0,.4,0],to:[0,.4,2],actors:[{...actor('swimmer',1.2,0,'squid'),swim:true}],world:-1,boss:-1},
 {name:'ally_then_dead_then_valid',kind:'shooter',from:[0,.8,0],to:[0,.8,2],actors:[{...actor('ally',.5),team:0},{...actor('dead',.8),alive:false},actor('enemy',1.2)],world:-1,boss:-1},
 {name:'visual_smooth_height',kind:'shooter',from:[0,1.65,0],to:[0,1.65,2],actors:[{...actor('smooth',1.2),smoothY:.4}],world:-1,boss:-1},
 {name:'slosh_volley_repeated_actor',kind:'slosher_head',from:[0,.8,0],to:[0,.8,2],actors:[actor('enemy',1.2)],world:-1,boss:-1,repeat:true},
 {name:'flick_actual_impact_falloff',kind:'flick',from:[0,.8,0],to:[0,.8,2],actors:[actor('enemy',1.4)],world:-1,boss:-1,start:[0,.8,-2]},
 {name:'flick_actual_boss_falloff',kind:'flick',from:[0,.8,0],to:[0,.8,2],actors:[],world:-1,boss:1.1,start:[0,.8,-2]}
);
const traces=[];
for(const spec of rows){
 hits=[];impacts=[];events=[];
 const owner={team:0,color:new THREE.Color('#ff8a14'),isLocal:false,_nearCamera:()=>false,addTurf(){}};
 const type=spec.kind==='blaster'?'blast':spec.kind==='flick'?'drop':spec.kind.startsWith('slosher')?'slosh':'shot';
 const p={type,wid:spec.kind.startsWith('slosher')?'slosher':type==='blast'||type==='drop'?null:spec.kind,owner,team:0,age:0,life:2,straight:99,radius:.8,damage:125,dmgFar:30,size:type==='blast'?.26:type==='slosh'?(spec.kind.endsWith('head')?.2:.14):.15,grav:0,drag:0,trailEvery:0,head:spec.kind.endsWith('head'),pos:new THREE.Vector3(...spec.from.map(Math.fround)),prev:new THREE.Vector3(),start:new THREE.Vector3(...(spec.start||spec.from).map(Math.fround)),vel:new THREE.Vector3(...spec.to.map(Math.fround)).sub(new THREE.Vector3(...spec.from.map(Math.fround))).multiplyScalar(60)};
 if(type==='slosh')p.vol={hits:spec.repeat?[spec.actors[0]]:[]};
 G.actors=spec.actors;
 G.boss=spec.boss>=0?{segHit:()=>({dist:spec.boss,point:new THREE.Vector3(0,spec.from[1],spec.from[2]+spec.boss),target:{}}),hit:(_a,d,_t,w,at)=>hits.push({target:'boss',damage:d,weapon:w,point:at.toArray()})}:null;
 G.physics={segment:(a,b,out)=>Object.assign(out,{hit:spec.world>=0,point:new THREE.Vector3(0,spec.from[1],spec.from[2]+Math.max(0,spec.world)),normal:new THREE.Vector3(0,0,-1)})};
 const projectiles=Object.create(Projectiles.prototype);
 projectiles.applyHit=(_a,e,d,w)=>hits.push({target:e.name,damage:d,weapon:w});
 projectiles._blastBurst=(_p,at,direct)=>impacts.push({kind:'blast',point:at.toArray(),target:direct?.name||direct||''});
 projectiles._sloshSplash=(_p,at,direct)=>impacts.push({kind:'slosh',point:at.toArray(),target:direct?.name||direct||''});
 projectiles._impact=(_p,hit)=>impacts.push({kind:'world',point:hit.point.toArray()});
 const dead=Projectiles.prototype._step.call(projectiles,p,1/60);
 traces.push({input:{...spec,actors:spec.actors.map(a=>({...a,pos:a.pos.toArray()}))},wanted:{dead,hits,impacts,end:p.pos.toArray()}});
}
const beams=[];
for(const spec of [
 {name:'charger_nearest_actor',actors:[actor('far',8),actor('near',3)],world:-1,boss:-1},
 {name:'charger_world_caps_actor',actors:[actor('behind_wall',5)],world:2,boss:-1},
 {name:'charger_boss_before_actor',actors:[actor('enemy',6)],world:-1,boss:2},
 {name:'charger_actor_before_boss',actors:[actor('enemy',2)],world:-1,boss:6},
 {name:'charger_world_cap_boss',actors:[],world:3,boss:-1},
 {name:'charger_axis_radius_near_foot',actors:[actor('enemy',4,0,'kid')],world:-1,boss:-1,y:.02},
 {name:'charger_squid_halfmetre_axis',actors:[actor('enemy',4,.519,'squid')],world:-1,boss:-1,y:.5},
 {name:'charger_outside_threshold',actors:[actor('enemy',4,.521,'squid')],world:-1,boss:-1,y:.5}
]){
 hits=[];impacts=[];events=[];
 const y=spec.y??1.05,owner={pos:new THREE.Vector3(0,0,0),color:new THREE.Color('#ff8a14'),weapon:WEAPONS.charger,team:0,isLocal:false,_nearCamera:()=>false,addTurf(){}};
 G.actors=spec.actors;
 G.physics={raycast:(origin,dir,range,out)=>Object.assign(out,{hit:dir.z>.9&&spec.world>=0,dist:spec.world>=0?spec.world:range,point:new THREE.Vector3(0,y,Math.max(0,spec.world)),normal:new THREE.Vector3(0,0,-1)})};
 G.boss=spec.boss>=0?{segHit:()=>({dist:spec.boss,point:new THREE.Vector3(0,y,spec.boss),target:{}}),hit:(_a,d,_t,w,at)=>hits.push({target:'boss',damage:d,weapon:w,point:at.toArray()})}:null;
 const projectiles=Object.create(Projectiles.prototype);
 projectiles._muzzle=()=>new THREE.Vector3(0,y,0);projectiles._aimFrom=()=>new THREE.Vector3(0,0,1);
 projectiles.applyHit=(_a,e,d,w)=>hits.push({target:e.name,damage:d,weapon:w});
 projectiles.beams=[];projectiles._beamMesh=()=>Object.assign(new THREE.Object3D(),{material:{color:new THREE.Color(),uniforms:Object.fromEntries(['uColor','uT','uLife','uLen','uCharge','uSeed','uWidth'].map(k=>[k,{value:k==='uColor'?new THREE.Color():0}]))}});
 Projectiles.prototype.fireCharger.call(projectiles,owner,WEAPONS.charger,1);
 beams.push({input:{...spec,y,actors:spec.actors.map(a=>({...a,pos:a.pos.toArray()}))},wanted:{hits,len:events[0].len,end:impacts[0].point}});
}
await fs.writeFile(path.join(base,'data/projectile_contacts.json'),JSON.stringify({source:'unmodified src/game/weapons.js Projectiles._step and fireCharger with original Physics.segmentCapsuleDist',traces,beams},null,2));
console.log(JSON.stringify({rounds:traces.length,beams:beams.length}));
