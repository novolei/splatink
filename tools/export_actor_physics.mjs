// Executable original OBB/body/foot/controller probes; never starts a renderer.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import * as THREE from 'three';
import {MAP_LAYOUTS} from '../../src/world/maps.js';
import {Level} from '../../src/world/level.js';
import {dressingFor} from '../../src/world/dressing.js';
import {PropKit} from '../../src/world/props.js';
import {Physics,Hit,GroundHit,makeContacts} from '../../src/game/physics.js';
import {Actor} from '../../src/game/actor.js';
import {PLAYER} from '../../src/config.js';
import {G} from '../../src/core/ctx.js';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {createCanvas}=require('@napi-rs/canvas');
globalThis.document={createElement:()=>createCanvas(1,1),fonts:{add(){}}};
globalThis.requestIdleCallback=()=>0;
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','data','actor_physics');
await fs.mkdir(out,{recursive:true});
const assets=path.resolve(out,'..','..','assets','actor_physics');await fs.mkdir(assets,{recursive:true});
const vector=a=>new THREE.Vector3(...a.map(Math.fround));
const hitRecord=h=>({hit:h.hit,distance:h.dist,position:h.point.toArray(),normal:h.normal.toArray(),block:h.block,face:h.face,u:h.u,v:h.v});
const groundRecord=h=>({hit:h.hit,y:h.y,normal:h.normal.toArray(),block:h.block,face:h.face,u:h.u,v:h.v,center:h.center,grate:h.grate});
const contactRecord=(p,c)=>({position:p.toArray(),ground:c.ground,wall:c.wall,ceiling:c.ceiling,ground_normal:c.groundNormal.toArray(),wall_normal:c.wallNormal.toArray(),ground_block:c.groundBlock,wall_block:c.wallBlock});
const synthetic={bounds:{minX:-15,maxX:15,minZ:-15,maxZ:15},spawnPads:[[0,0,-14],[0,0,14]],spawnBarrier:4.2,half:[],single:[
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
const sources=[['fixtures',new Level(synthetic),true]];
for(const[id,layout]of Object.entries(MAP_LAYOUTS)){
 const kit=new PropKit(new THREE.Scene(),{quality:'high'}),colliders=[];
 for(const prop of dressingFor(id))colliders.push(...kit.add(prop.type,prop).colliders);kit.build();
 sources.push([id,new Level(layout,colliders),false]);
}
for(const[id,level,fixture]of sources){
 const physics=new Physics(level);G.physics=physics;G.level=level;
 const record={source:'original Physics.raycast/groundProbe/collideBody/bodyFits + Actor._integrate/_resolve/_roofSlide/_railFeet/_railCentre',stage:id,raycasts:[],ground:[],body:[],motion:[],traces:[]};
 const header=Buffer.alloc(8);header.writeUInt32LE(level.blocks.length,0);header.writeUInt32LE(level.faces.length,4);
 const boxFields=Float64Array.from(level.blocks.flatMap(b=>[...b.center.toArray(),...b.half.toArray(),...b.axes.flatMap(a=>a.toArray()),b.aabbMin.y,b.aabbMax.y]));
 const faceFields=Float64Array.from(level.faces.flatMap(f=>[...f.origin.toArray(),...f.u.toArray(),...f.v.toArray()]));
 await fs.writeFile(path.join(assets,id+'.bin'),Buffer.concat([header,Buffer.from(boxFields.buffer),Buffer.from(faceFields.buffer)]));
 record.fields='res://assets/actor_physics/'+id+'.bin';
 if(fixture)record.geometry={bounds:level.bounds,blocks:level.blocks.map(b=>({id:b.id,center:b.center.toArray(),half:b.half.toArray(),axes:b.axes.map(a=>a.toArray()),solid:b.solid,grate:b.grate,rail:b.rail,roof:b.roof})),faces:level.faces.map(f=>({id:f.id,block:f.block,n:f.n.toArray(),u:f.u.toArray(),v:f.v.toArray(),origin:f.origin.toArray()}))};
 const selected=fixture?level.blocks:level.blocks.filter((b,i)=>i%Math.max(1,Math.floor(level.blocks.length/22))===0||b.rail||b.roof).slice(0,42);
 const positions=[];
 for(const b of selected){
  const top=b.center.clone().addScaledVector(b.axes[1],b.half.y);
  if(b.axes[1].y>=.68){
   for(const[offsetX,offsetZ]of [[0,0],[.95,0],[1.03,0],[0,.95],[0,1.03]]){
    const p=top.clone().addScaledVector(b.axes[0],b.half.x*offsetX).addScaledVector(b.axes[2],b.half.z*offsetZ);
    positions.push(vector(p.toArray()));
   }
  }
  for(const axis of [0,2])for(const sign of [-1,1]){
   const normal=b.axes[axis].clone().multiplyScalar(sign);
   const origin=vector(b.center.clone().addScaledVector(normal,(axis===0?b.half.x:b.half.z)+.31).toArray());
   const direction=vector(normal.clone().negate().toArray()).normalize();
   for(const skip of [false,true]){
    const h=physics.raycast(origin,direction,3.2,new Hit(),skip);
    record.raycasts.push({origin:origin.toArray(),direction:direction.toArray(),distance:3.2,skip,wanted:hitRecord(h)});
   }
   const feet=origin.clone();feet.y=Math.fround(b.center.y-.37);
   for(const squid of [false,true])for(const horizontal of [false,true]){
    const p=feet.clone(),lift=squid?PLAYER.squidBodyLift:PLAYER.stepUp,height=squid?PLAYER.squidHeight:PLAYER.height;
    const fits=physics.bodyFits(p,PLAYER.radius,lift,height,squid);
    const c=physics.collideBody(p,PLAYER.radius,lift,height,makeContacts(),horizontal,squid);
    record.body.push({pos:feet.toArray(),radius:PLAYER.radius,lift,height,squid,horizontal,fits,wanted:contactRecord(p,c)});
   }
  }
 }
 if(fixture)positions.push(...[[-.12,0,-4],[-.12,0,4],[.12,.2,-4],[.23,0,0],[.25,0,0],[2.24,1.8,0],[2.31,1.8,0],[-1,1.6,0],[-9,1,0]].map(vector));
 for(const original of positions){
  for(const squid of [false,true])for(const elevation of [0,.18]){
   const pos=original.clone();pos.y=Math.fround(pos.y+elevation);
   const up=squid?PLAYER.squidStepUp:PLAYER.stepUp;
   const h=physics.groundProbe(pos.x,pos.y,pos.z,up,PLAYER.stepDown,PLAYER.footRadius,new GroundHit(),squid);
   record.ground.push({pos:pos.toArray(),up,down:PLAYER.stepDown,foot:PLAYER.footRadius,squid,wanted:groundRecord(h)});
   for(const stick of [false,true]){
    const velocity=vector(stick?[3,0,-1]:[2,-12,1]);
    const previousY=Math.fround(pos.y+(stick?0:.2));
    const a=Object.create(Actor.prototype);
    Object.assign(a,{pos:pos.clone(),vel:velocity.clone(),contacts:makeContacts(),ground:new GroundHit(),groundN:new THREE.Vector3(0,1,0),grounded:stick,smoothY:0,airTime:0,_onLand(){this.landed=true;this.landSpeed=Math.max(0,-this.vel.y);}});
    a._resolve(squid,previousY,stick);
    record.motion.push({pos:pos.toArray(),velocity:velocity.toArray(),squid,previous_y:previousY,stick,was_grounded:stick,wanted:{position:a.pos.toArray(),velocity:a.vel.toArray(),grounded:a.grounded,smooth_y:a.smoothY,landed:!!a.landed,land_speed:a.landSpeed||0,ground:groundRecord(a.ground)}});
   }
  }
 }
 const starts=fixture?[['curb',[-.5,0,-4],[3,0,0],false],['squidCurb',[-.5,0,-4],[3,0,0],true],['railBalance',[2.2,1.8,0],[0,0,1],false],['railLeave',[2.2,1.8,0],[1,0,1],false],['roof',[9,1.2,8],[0,0,0],false],['ramp',[-9,1,0],[0,0,3],false],['jump',[-3,0,4],[3,0,0],false]]:positions.slice(0,3).map((p,i)=>['walk'+i,p.toArray(),[3,0,-1],i%2===1]);
 for(const[name,start,heading,squid]of starts){
  const p=vector(start),ground=physics.groundProbe(p.x,p.y,p.z,.3,.3,PLAYER.footRadius,new GroundHit(),squid);
  const grounded=ground.hit&&Math.abs(ground.y-p.y)<.3;
  if(grounded)p.y=ground.y;
  const a=Object.create(Actor.prototype);
  Object.assign(a,{pos:p,vel:new THREE.Vector3(),contacts:makeContacts(),ground,groundN:ground.normal.clone(),grounded,smoothY:0,airTime:0,climbing:false,intent:{move:vector(heading).normalize()},roofT:0,roofDir:null,roofStall:0,_onLand(){this.landed=true;this.landSpeed=Math.max(0,-this.vel.y);}});
  const trace={name,squid,initial:{position:a.pos.toArray(),grounded,ground:groundRecord(ground)},frames:[]};
  for(let frame=0;frame<72;frame++){
   const jumped=name==='jump'&&frame===12;
   a.vel.x=heading[0];a.vel.z=heading[2];if(jumped)a.vel.y=PLAYER.jumpVel;
   a.landed=false;a.landSpeed=0;
   const before=a.vel.toArray();a._integrate(1/60,squid,jumped);
   trace.frames.push({velocity:before,move:a.intent.move.toArray(),jumped,wanted:{position:a.pos.toArray(),velocity:a.vel.toArray(),grounded:a.grounded,smooth_y:a.smoothY,air_time:a.airTime,landed:a.landed,land_speed:a.landSpeed,roof_time:a.roofT||0,roof_direction:a.roofDir?.toArray()||[0,0,0],roof_stall:a.roofStall||0}});
  }
  record.traces.push(trace);
 }
 await fs.writeFile(path.join(out,id+'.json'),JSON.stringify(record,null,2));
 console.log(JSON.stringify({stage:id,rays:record.raycasts.length,ground:record.ground.length,body:record.body.length,motion:record.motion.length}));
}
