// Execute the original Actor.update with deterministic controller inputs. The
// native contract exercises the integrated Actor rather than only query helpers.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Actor} from '../../src/game/actor.js';
import {Level} from '../../src/world/level.js';
import {Physics} from '../../src/game/physics.js';
import {G,on} from '../../src/core/ctx.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const layout={bounds:{minX:-15,maxX:15,minZ:-15,maxZ:15},spawnPads:[[0,0,-14],[0,0,14]],spawnBarrier:4.2,half:[],single:[
 {kind:'box',min:[-6,-1,-6],max:[0,0,6]},
 {kind:'box',min:[0,-1,-6],max:[1,.2,-2]},
 {kind:'box',min:[0,-1,2],max:[1,.1,6]},
 {kind:'box',min:[-4,1.34,-4],max:[-2,1.5,-2]},
 {kind:'box',min:[-1.5,1.5,-1],max:[-.5,1.6,1],grate:true},
 {kind:'box',min:[2,0,-3],max:[2.08,1.8,3],rail:true},
 {kind:'obox',center:[5,1,0],size:[1,2,5],rotY:37},
 {kind:'ramp',low:[-9,0,-5],high:[-9,2,5],width:3,thickness:.25,thin:true},
 {kind:'box',min:[7,1,6],max:[11,1.2,10],roof:true}
]};
class CharacterStub{
 constructor(){this.root=new THREE.Object3D();this.triggers=[];}
 setVisible(){} setHurt(){} setWeapon(){} update(){}
 trigger(action,arg){this.triggers.push({action,arg});}
}
G.level=new Level(layout);G.physics=new Physics(G.level);
G.teamColors=[new THREE.Color('#ff8a14'),new THREE.Color('#2f5bff')];
G.match={playing:()=>true,canRespawn:()=>true};
G.projectiles={throwStorm(){},throwBomb(){},fire(){},applyHit(){}};
G.actors=[];G.audio=null;G.fx=null;G.input=null;
let ink=0,events=[];
G.paint={sample:()=>ink,splat:()=>0};
on('actor:land',data=>events.push({kind:'land',speed:data.speed}));
on('actor:climb',data=>events.push({kind:'climb',on:data.on}));
on('superjump:land',()=>events.push({kind:'jump_land'}));
const traces=[];
for(const spec of [
 {name:'kid_curb',start:[-.7,0,-4],move:[1,0,0],frames:38},
 {name:'dry_squid_curb',start:[-.7,0,-4],move:[1,0,0],squid:true,frames:42},
 {name:'own_ink_curve',start:[-4,0,4],move:[1,0,0],squid:true,ink:1,frames:28},
 {name:'enemy_ink_brake',start:[-4,0,4],move:[1,0,0],ink:2,frames:38},
 {name:'ramp_up',start:[-9,1,0],move:[0,0,1],frames:42},
 {name:'rail_balance',start:[2.2,1.8,0],move:[0,0,1],frames:38},
 {name:'squid_through_grate',start:[-1,1.6,0],move:[0,0,0],squid:true,frames:28},
 {name:'kid_grate_support',start:[-1,1.6,0],move:[0,0,0],frames:28},
 {name:'roof_forced_slide',start:[9,1.2,8],move:[0,0,0],frames:42},
 {name:'jump_and_landing',start:[-3,0,4],move:[0,0,0],jump:4,frames:75},
 {name:'own_wall_attach_and_climb',start:[4.04,.1,.72],move:[.798635510047,0,-.60181502315],squid:true,ink:1,frames:26},
 {name:'storm_ground_resolve',start:[-3,0,4],move:[1,0,0],special:'storm',frames:40},
 {name:'slam_landing_resolve',start:[-3,0,4],move:[0,0,0],special:'slam',frames:75},
 {name:'superjump_base_landing',start:[-3,0,4],move:[0,0,0],superjump:[-3,0,-3],frames:154}
]){
 ink=spec.ink||0;events=[];G.time=0;
 const actor=new Actor({team:0,name:'source probe',weapon:spec.special==='storm'?'charger':'shooter',CharacterClass:CharacterStub});
 actor.spawnAt(new THREE.Vector3(...spec.start.map(Math.fround)),0);actor.invuln=0;
 if(spec.superjump)actor.superJump(new THREE.Vector3(...spec.superjump));
 if(spec.special)actor._startSpecial();
 const frames=[];
 for(let frame=0;frame<spec.frames;frame++){
  const input={move:spec.move.map(Math.fround),swim:!!spec.squid,jump:frame===spec.jump};
  actor.intent.move.set(...input.move);actor.intent.squid=input.swim;actor.intent.jump=input.jump;
  G.time+=(1/60);actor.update(1/60);
  frames.push({input,wanted:{position:actor.pos.toArray(),velocity:actor.vel.toArray(),grounded:actor.grounded,form:actor.form,submerged:actor.submerged,climbing:actor.climbing,hp:actor.hp,ink:actor.ink,smooth_y:actor.smoothY,land_speed:actor.landSpeed,alive:actor.alive,superjump:actor.superJumpState?.phase||'',special:actor.specialActive?.id||'',events}});
  events=[];
 }
 traces.push({...spec,frames});
}
await fs.writeFile(path.join(base,'data/actor_controller.json'),JSON.stringify({source:'unmodified src/game/actor.js Actor.update with original Physics; no renderer',layout,traces},null,2));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
