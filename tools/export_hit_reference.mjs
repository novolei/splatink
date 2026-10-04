/** Capture actual source Character hit impulses and spring evolution. */
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Character} from '../../src/game/character.js';
import {G} from '../../src/core/ctx.js';
import * as THREE from 'three';
import {springIndices as indices,sourceHeadParameters} from './source_character_layout.mjs';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
G.settings={quality:'high'};
const names=['S_HITP','S_HITR','S_HITY','S_PELY','S_HEADP','S_HEADR','S_CLAV','S_STAG','S_SQP','S_SQY','S_WRX','S_EARL','S_EARR','S_GRIP'];
for(const name of names)if(indices[name]===undefined)throw new Error('Missing actual source spring '+name);
const scenarios=[
  {name:'front',form:'kid',events:[{frame:0,arg:{x:0,z:1,amp:1}}]},
  {name:'back',form:'kid',events:[{frame:0,arg:{x:0,z:-1,amp:1}}]},
  {name:'left',form:'kid',events:[{frame:0,arg:{x:1,z:0,amp:1}}]},
  {name:'right',form:'kid',events:[{frame:0,arg:{x:-1,z:0,amp:1}}]},
  {name:'diagonal_soft',form:'kid',events:[{frame:0,arg:{x:7,z:-4,amount:.6}}]},
  {name:'zero_direction_clamp',form:'kid',events:[{frame:0,arg:{x:0,z:0,amp:2}}]},
  {name:'numeric_low',form:'kid',events:[{frame:0,arg:.1}]},
  {name:'numeric_high',form:'kid',events:[{frame:0,arg:2}]},
  {name:'repeated_stagger',form:'kid',events:[{frame:0,arg:{x:1,z:1,amp:1.2}},{frame:4,arg:{x:-1,z:1,amp:1.2}},{frame:8,arg:{x:1,z:-1,amp:1.2}}]},
  {name:'squid',form:'squid',events:[{frame:0,arg:{x:1,z:0,amp:.8}}]},
  {name:'swim_hold',form:'swim',events:[{frame:0,arg:{x:0,z:1,amp:1}}]}
];
const cases=[];
for(const fps of [30,60,144])for(const scenario of scenarios){
  const c=new Character({name:'Hit reference',weapon:'shooter',style:{hair:0,hat:0}});
  const base=new Character({name:'Hit reference',weapon:'shooter',style:{hair:0,hat:0}});
  const state={form:scenario.form,grounded:true,speed:0,ink:1,localMove:{x:0,z:0}};
  c.setLod('hero');base.setLod('hero');
  for(let warm=0;warm<60;warm++){c.update(1/30,state);base.update(1/30,state);}
  const samples=[];
  for(let frame=0;frame<Math.ceil(.85*fps);frame++){
    for(const event of scenario.events)if(event.frame===frame)c.trigger('hit',event.arg);
    c.update(1/fps,state);base.update(1/fps,state);
    const values=names.map(name=>[c.sp[indices[name]]-base.sp[indices[name]],c.sp[indices[name]+1]-base.sp[indices[name]+1]]);
    const neck=new THREE.Quaternion();c._kidXform(c.bones.neck,new THREE.Vector3(),neck);
    const head={parameters:sourceHeadParameters(c),parent:neck.toArray(),rotation:c.bones.head.quaternion.toArray()};
    const feet=c.feet.map(f=>({contact:f.cw.toArray(),yaw:f.cyaw,pitch:f.pitch,swing:f.sw,phase:f.su,duration:f.dur,lift:f.lift,from:f.from.toArray(),to:f.to.toArray(),fromYaw:f.fromYaw,toYaw:f.toYaw,toe:f.toe,land:f.land,planted:f.planted}));
    samples.push({values,direction:[c.hitX,c.hitZ],amplitude:c.hitAmp,accumulated:c.hitAcc,stepOffset:[c.stepOfsX,c.stepOfsZ],head,feet,run_weight:c.runW});
  }
  cases.push({...scenario,fps,samples});c.dispose();base.dispose();
}
const idle=new Character({name:'Stance reference',style:{hair:0,hat:0}});
const report={source:'Actual Character.trigger + Character.update Float32 spring bank',channels:names,idle_stance:Array.from(idle.stance),ankle_height:idle.rest.footL.y,ball_z:.11,heel_z:.065,cases};
report.settle=[];
for(const error of [.05,.068,.12,.2,.5]){
  idle.root.position.set(2,1,-3);idle.yaw=.7;idle.stepOfsX=-.1;idle.stepOfsZ=-.16;
  const foot=idle.feet[0];foot.pw.set(2.11,1,-2.98);foot.yaw=.3;
  idle._startSettle(foot,error);
  report.settle.push({error,from:foot.from.toArray(),fromYaw:foot.fromYaw,to:foot.to.toArray(),toYaw:foot.toYaw,duration:foot.dur,lift:foot.lift,toe:foot.toe,land:foot.land});
}
await fs.writeFile(path.join(project,'assets/characters/motion_parameters.json'),JSON.stringify({source:'Character constructor resting foot stance and sole pivots',idle_stance:report.idle_stance,ankle_height:report.ankle_height,ball_z:report.ball_z,heel_z:report.heel_z},null,2));
idle.dispose();
await fs.writeFile(path.join(project,'data/hit_reference.json'),JSON.stringify(report));
console.log(JSON.stringify({cases:cases.length,samples:cases.reduce((sum,c)=>sum+c.samples.length,0),source_channels:names.length}));
