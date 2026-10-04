// Execute production Player.js and Physics.js, rather than copying their math
// into the expected side of the native contract.
import fs from 'node:fs/promises';
import * as THREE from 'three';
import {PlayerController} from '../../src/game/Player.js';
import {Physics} from '../../src/game/physics.js';
import {Input} from '../../src/core/input.js';
import {G} from '../../src/core/ctx.js';
import {WEAPONS} from '../../src/config.js';
let seed=9123487;
const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
const v=a=>new THREE.Vector3(...a);
const makeActor=(p,team=1,extra={})=>({pos:v(p),smoothY:0,team,alive:true,form:'kid',anim:{form:'kid'},invuln:0,weaponId:'shooter',weapon:WEAPONS.shooter,aimPoint:new THREE.Vector3(),aimYaw:0,aimPitch:0,intent:{move:new THREE.Vector3(),fire:false},canSuperJump:()=>false,...extra});
const camera=new THREE.PerspectiveCamera(82,16/9,.15,6500);
const input=Object.create(Input.prototype);
input.mouse={dx:0,dy:0,left:false,right:false};input.lastDevice='kbm';input.pad=null;input.padPressed=new Set();
let held=new Set();input.down=k=>held.has(k);input.wasPressed=()=>false;
G.camera=camera;G.settings={};
let worldDistance=70,blocked=false,bossDistance=-1;
G.physics={raycast:(start,dir,max,out)=>Object.assign(out,{hit:worldDistance<max,dist:worldDistance}),los:()=>!blocked};
const boss={rayDist:(_start,_dir,max)=>bossDistance>0&&bossDistance<max?bossDistance:-1};
const aimCases=[];
for(let i=0;i<180;i++){
 const angle=(rand()-.5)*1.1,pitch=(rand()-.5)*.55;
 const direction=[Math.sin(angle)*Math.cos(pitch),Math.sin(pitch),Math.cos(angle)*Math.cos(pitch)];
 const local=makeActor([.2,0,-2],0);local.weaponId=['shooter','roller','charger'][i%3];local.weapon=WEAPONS[local.weaponId];
 const rig={yaw:angle,pitch,gameCam:camera,mapK:0};G.rig=rig;
 camera.position.set(1,1.7,-5);camera.lookAt(camera.position.clone().add(v(direction)));camera.updateMatrixWorld(true);
 worldDistance=i%6===0?5+rand()*8:70;
 bossDistance=i%11===0?6+rand()*8:-1;G.boss=bossDistance>0?boss:null;
 const enemies=[];
 for(let j=0;j<5;j++){
  const p=camera.position.clone().addScaledVector(v(direction),4+rand()*22);p.x+=(rand()-.5)*1.5;p.y-=.8+rand()*.4;
  const e=makeActor(p.toArray(),j===4?0:1,{smoothY:(rand()-.5)*.2,alive:j!==2||i%4!==0,form:j===3?'squid':'kid',anim:{form:j===1&&i%3===0?'swim':'kid'}});enemies.push(e);
 }
 G.actors=[local,...enemies];const controller=new PlayerController(local,rig,input);controller.computeAim();
 aimCases.push({camera:camera.position.toArray(),direction,local:local.pos.toArray(),weapon:local.weaponId,worldDistance,bossDistance,enemies:enemies.map(e=>({position:e.pos.toArray(),team:e.team,smoothY:e.smoothY,alive:e.alive,form:e.form,submerged:e.anim.form==='swim'})),point:local.aimPoint.toArray(),target:G.actors.indexOf(controller.onTarget),bossTarget:controller.onTarget===boss,inRange:controller.inRange});
}
const capsules=[];
for(let i=0;i<800;i++){
 const a=[(rand()-.5)*10,rand()*5,(rand()-.5)*10],b=[(rand()-.5)*10,rand()*5,(rand()-.5)*10],base=[(rand()-.5)*6,rand()*2,(rand()-.5)*6],height=i%2?.55:1.45;
 const out={};Physics.segmentCapsuleDist(v(a),v(b),v(base),.38,height,out);capsules.push({a,b,base,height,t:out.t,distance:out.dist});
}
const lookCases=[];
for(const scenario of ['mouse','pad','assist','assist_mouse','map']){
 const local=makeActor([0,0,0],0),enemy=makeActor([0,0,9]);G.actors=[local,enemy];G.boss=null;worldDistance=70;blocked=false;
 const rig={yaw:0,pitch:0,gameCam:camera,mapK:0};G.rig=rig;
 const controller=new PlayerController(local,rig,input);const frames=[];
 for(let i=0;i<180;i++){
  const dt=[1/60,1/120,1/90][i%3];const map=scenario==='map'&&i>30&&i<105;
  G.settings={sensitivity:1.1,padSensitivity:.9,invertY:i>130,aimAssist:1,aimAssistMouse:scenario==='assist'||scenario==='assist_mouse'};
  input.mouse.dx=scenario==='mouse'||scenario==='assist'||scenario==='assist_mouse'?(rand()-.5)*10:0;input.mouse.dy=scenario==='mouse'?(rand()-.5)*6:0;
  const axes=scenario==='pad'||scenario==='assist'||scenario==='map'?[.24*Math.sin(i*.03),-.3,.96*(i<70?1:Math.sin(i*.02)),.08*Math.sin(i*.05)]:[0,0,0,0];
  input.pad=scenario==='mouse'||scenario==='assist_mouse'?null:{axes,buttons:[]};input.lastDevice=input.pad?'pad':'kbm';
  held=new Set(map?['Tab']:i%40<25?['KeyW']:['KeyD']);rig.mapK=map?1:0;
  enemy.pos.set(Math.sin(i*.018)*.3,0,9);enemy.smoothY=.01*Math.sin(i*.02);blocked=i%53>48;
  camera.position.set(0,1,-4);camera.lookAt(camera.position.clone().add(new THREE.Vector3(Math.sin(rig.yaw)*Math.cos(rig.pitch),Math.sin(rig.pitch),Math.cos(rig.yaw)*Math.cos(rig.pitch))));camera.updateMatrixWorld(true);
  const pre={dt,settings:{...G.settings},mouse:[input.mouse.dx,input.mouse.dy],left:axes.slice(0,2),right:axes.slice(2,4),hasPad:!!input.pad,lastDevice:input.lastDevice,mapUp:map,move:held.has('KeyW')?[0,-1]:held.has('KeyD')?[1,0]:[0,0],enemy:enemy.pos.toArray(),smoothY:enemy.smoothY,blocked,camera:camera.position.toArray(),direction:camera.getWorldDirection(new THREE.Vector3()).toArray()};
  controller.update(dt);
  frames.push({...pre,yaw:rig.yaw,pitch:rig.pitch,padLook:[controller.padLook.x,controller.padLook.y],edgeTime:controller.edgeT,movement:local.intent.move.toArray(),point:local.aimPoint.toArray(),target:controller.onTarget===enemy,inRange:controller.inRange});
 }
 lookCases.push({scenario,frames});
}
await fs.writeFile(new URL('../data/player_controller.json',import.meta.url),JSON.stringify({aimCases,capsules,lookCases}));
console.log(JSON.stringify({aim:aimCases.length,capsules:capsules.length,lookFrames:lookCases.reduce((n,c)=>n+c.frames.length,0)}));
