// Source procedural-animation hooks, sampled on the same 30 Hz clock as the native Boss clips.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {buildRig} from '../../src/boss/bossModelGeo.js';
import {BossAnimator} from '../../src/boss/bossAnim.js';
import {buildBossClipSpecs} from './boss_clip_specs.mjs';
function sample(name,duration,state={}){
 const rig=buildRig(),root=new THREE.Group();root.add(rig.by.base);root.updateMatrixWorld(true);
 const events=[];let t=-1,capturing=false;
 const record=e=>{if(capturing)events.push({time:t,...e});};
 const model={root,physics:null,
  _emitFoot(leg,pos,strength){record({kind:'foot',leg,pos:pos.toArray(),strength});},
  _emitImpact(socket,strength){record({kind:'impact',socket,strength});},
  _emitEvent(name,socket,data){record({kind:'fx',name,socket,data});}};
 const st={phase:1,speed:0,move:null,grounded:true,...state};
 const anim=new BossAnimator(model,rig);anim.prevPhase=st.phase;anim.update(0,{phase:st.phase});
 for(let i=0;i<30;i++)anim.update(1/30,{phase:st.phase});
 if(st.movePhase&&st.movePhase!=='tele'){
  const until=st.movePhase==='act'?0:1;
  const durations=st._capture_durations;
  for(let phase=0;phase<=until;phase++)for(let i=0;i<=Math.ceil(durations[phase]*30);i++){
   const now=Math.min(i/30,durations[phase]),previous=i===0?0:Math.min((i-1)/30,durations[phase]);
   anim.update(now-previous,{...st,movePhase:['tele','act','rec'][phase],moveT:now,phaseDur:durations[phase]});
  }
 }
 capturing=true;
 for(let i=0;i<=Math.ceil(duration*30);i++){
  t=Math.min(i/30,duration);const previous=i===0?0:Math.min((i-1)/30,duration);
  if(st.speed>0)root.position.z=t*st.speed;if(st.move)st.moveT=t;
  anim.update(t-previous,st);
 }
 return {duration,events};
}
const clips={};
for(const spec of buildBossClipSpecs())clips[spec.key]=sample(spec.name,spec.duration,spec.state);
// Retain the phase lookup contract for pre-variant assets and native tests.
for(const phaseName of ['tele','act','rec'])clips[`boss_slam_${phaseName}`].phase_events={2:clips[`boss_p2_slam_${phaseName}`].events,3:clips[`boss_p3_slam_${phaseName}`].events};
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../data/boss_events.json');
await fs.writeFile(out,JSON.stringify({source:'src/boss/bossAnim.js exact animation hook records',fps:30,clips},null,2));
console.log(JSON.stringify({clips:Object.keys(clips).length,hooks:Object.values(clips).reduce((n,c)=>n+c.events.length,0)}));
