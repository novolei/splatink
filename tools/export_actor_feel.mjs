// Executable source-value probes for Actor handling and WeaponRunner state.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {Actor} from '../../src/game/actor.js';
import {WeaponRunner} from '../../src/game/weapons.js';
import {WEAPONS} from '../../src/config.js';
import {G} from '../../src/core/ctx.js';
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const records={source:'src/game/actor.js _integrate/_face/_onLand/_spawnBarrier and weapons.js moveSpeed/busy/firingPose',gravity:[],facing:[],weapons:[],landings:[],barriers:[]};
for(const vertical of [2,0,-2.99,-3,-3.01,-7,-11.5,-11.51,-13,-14.5,-18]){
 const triggers=[];
 const a=Object.create(Actor.prototype);Object.assign(a,{pos:new THREE.Vector3(),vel:new THREE.Vector3(0,vertical,0),landSpeed:0,landT:99,hardLand:0,specialActive:null,isLocal:false,groundTeam:0,character:{trigger:(...args)=>triggers.push(args)},_surface(){},_nearCamera(){return false;}});
 a._onLand(false);records.landings.push({vertical,speed:a.landSpeed,hard_land:a.hardLand,triggers});
}
G.level={spawnPads:[new THREE.Vector3(0,0,-10),new THREE.Vector3(0,0,10)],spawnBarrier:4.2};
for(const pos of [[1,0,10],[0,-1.1,10],[4.3,0,10],[-2,0,9]])for(const vel of [[-2,0,0],[2,0,0],[0,3,2]]){
 const a=Object.create(Actor.prototype);Object.assign(a,{team:0,pos:new THREE.Vector3(...pos),vel:new THREE.Vector3(...vel)});
 a._spawnBarrier();records.barriers.push({pos,vel,wanted_pos:a.pos.toArray(),wanted_vel:a.vel.toArray()});
}
for(const vertical of [-45,-3,-1.6,-1.59,-.5,0,.5,1.59,1.6,3,8.4])for(const dt of [1/120,1/60,1/30,.1]){
 const a=Object.create(Actor.prototype);Object.assign(a,{climbing:false,grounded:false,vel:new THREE.Vector3(0,vertical,0),pos:new THREE.Vector3(),_resolve(){}});
 a._integrate(dt,false,false);records.gravity.push({vertical,dt,wanted:a.vel.y});
}
for(const mode of ['run','coast','idle','aim','sub','squid','swim','climb','special']){
 const a=Object.create(Actor.prototype);Object.assign(a,{yaw:.3,yawVel:mode==='idle'?2:0,fireFacing:0,anim:{},aimYaw:0,climbing:mode==='climb',wallN:new THREE.Vector3(-1,0,0),submerged:mode==='swim',specialActive:mode==='special'?{}:null,superJumpState:null,_faceTarget:null,weaponRunner:{firingPose(){return mode==='aim';}},intent:{move:new THREE.Vector3(),sub:mode==='sub'},vel:new THREE.Vector3()});
 const frames=[];
 for(let i=0;i<48;i++){
  const movement=mode==='idle'||mode==='coast'?new THREE.Vector3():new THREE.Vector3(i<24?0:1,0,i<24?1:0);
  const velocity=mode==='idle'?new THREE.Vector3():new THREE.Vector3(0,0,3);
  a.intent.move.copy(movement);a.vel.copy(velocity);a.aimYaw=i*.04+(i>=24?.7:0);
  a._face(1/60,mode==='squid'||mode==='swim'||mode==='climb');
  frames.push({move:movement.toArray(),velocity:velocity.toArray(),aim_yaw:a.aimYaw,yaw:a.yaw,turn:a.yawVel});
 }
 records.facing.push({mode,initial_yaw:.3,initial_velocity:mode==='idle'?2:0,frames});
}
for(const weapon of Object.keys(WEAPONS)){
 const a={weapon:WEAPONS[weapon]},runner=new WeaponRunner(a);
 const states=[{}, {firingT:.35}, {lockT:.5}, {charging:true,charge:.2}, {charging:true,charge:.5}, {charging:true,charge:1}];
 if(weapon==='roller')states.push({rolling:true,rollT:0},{rolling:true,rollT:.225},{rolling:true,rollT:.45},{flick:0},{flick:.11},{flick:.22},{flickRecover:.09});
 if(weapon==='slosher')states.push({slosh:.06});
 if(weapon==='splatling')states.push({streaming:true,charge:.6,burstT:1});
 if(weapon==='dualies')states.push({dodge:{t:.1,dur:.3}});
 for(const state of states){runner.reset();Object.assign(runner,state);records.weapons.push({weapon,state,speed:runner.moveSpeed(),busy:runner.busy(),pose:runner.firingPose()});}
}
await fs.writeFile(path.join(out,'data/actor_feel.json'),JSON.stringify(records,null,2));
console.log(JSON.stringify({gravity:records.gravity.length,facing:records.facing.reduce((n,p)=>n+p.frames.length,0),weapons:records.weapons.length}));
