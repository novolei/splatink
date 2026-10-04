// Capture the actual source water guard and shared navigation tail independently
// of its renderer/Actor physics. The inputs are reused by the native contract.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {G} from '../../src/core/ctx.js';
import {BotBrain} from '../../src/game/bots.js';
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const records={source:'src/game/bots.js _edgeGuard/_nearWater/_tail/_bossTick',edges:[],water:[],tail:[],aim:[]};
let bounds=[-4,-4,4,4];
G.level={groundHeight(x,z){return x>=bounds[0]&&z>=bounds[1]&&x<=bounds[2]&&z<=bounds[3]?0:-Infinity;}};
function actor(pos=[0,0,0],speed=0,weapon='shooter',charging=false){
 return {pos:new THREE.Vector3(...pos),vel:new THREE.Vector3(0,0,speed),yaw:0,aimPoint:new THREE.Vector3(),grounded:true,weapon:{kind:weapon},weaponRunner:{charging},intent:{move:new THREE.Vector3(),jump:false}};
}
G.paint={regionStats(_x,_y,_z,_r,_team,out){return Object.assign(out,{n:1,own:0,enemy:0,empty:1});}};
G.boss={pos:new THREE.Vector3(),yaw:0,phase:1,stunned:false,hz:{threat(){return {level:0,ringIn:-1,beam:false,cover:false};}}};
for(const time of [0,.4,1.2,3.5])for(const acquired of [0,.2,2]){
 const a=actor();Object.assign(a,{alive:true,ink:100,hp:100,team:0,groundTeam:0,specialReady(){return false;}});a.weapon={kind:'charger',rangeMax:27};
 const brain=new BotBrain(a);Object.assign(brain,{mode:'boss',path:[0],pi:0,goalTimer:99,repath:99,think:99,react:99,t:time,ph1:1.7,ph2:-2.3,acqT:acquired,acqSignY:.8,acqSignP:-.4,bTgt:{pos:new THREE.Vector3(10,2,0),rad:1,dist:10,los:false}});
 brain._steer=()=>new THREE.Vector3();let wanted;
 brain._tail=(_dt,_mv,yaw,pitch)=>{wanted=[yaw,pitch];};brain._bossTick(1/60);
 records.aim.push({time,acquired,ph1:1.7,ph2:-2.3,sign_y:.8,sign_p:-.4,ideal:[Math.PI/2,Math.atan2(.9,10)],wanted});
}
for(const pos of [[0,0,0],[0,0,3.6],[3.5,0,3.5],[0,0,4.3]])for(const speed of [0,5.5,9.7])for(const angle of [0,.8,Math.PI/2,Math.PI]){
 const a=actor(pos,speed),brain=new BotBrain(a),move=new THREE.Vector3(Math.sin(angle),0,Math.cos(angle));
 brain._edgeGuard(a,move);records.edges.push({pos,speed,angle,bounds:[...bounds],move:move.toArray()});
}
for(const pos of [[0,0,0],[0,0,3.6],[3.5,0,3.5],[0,0,4.3]])for(const radius of [.6,1.2,3.2]){
 const a=actor(pos),brain=new BotBrain(a);records.water.push({pos,radius,bounds:[...bounds],wet:brain._nearWater(a,radius)});
}
for(const progress of [.69,.7,.7001,1.5,1.5001,2.4,2.4001])for(const charging of [false,true]){
 const a=actor([0,0,0],0,charging?'charger':'shooter',charging),brain=new BotBrain(a);
 Object.assign(brain,{path:[1,2,3],pi:0,noProg:progress,jumpCd:0,bestD:3,goalTimer:4,repath:1,mvYaw:0,mvMag:1,_needJump:false});
 brain._tail(1/60,new THREE.Vector3(0,0,1),0,-.1,6,true);
 records.tail.push({pos:[0,0,0],bounds:[...bounds],weapon:charging?'charger':'shooter',charging,progress,jump_cd:0,need_jump:false,want_move:true,result:{jump:a.intent.jump,jump_cd:brain.jumpCd,pi:brain.pi,no_progress:brain.noProg,skipped:!!brain._skipped,path:!!brain.path,goal_timer:brain.goalTimer,repath:brain.repath,need_jump:!!brain._needJump,best_distance:Number.isFinite(brain.bestD)?brain.bestD:null,move:a.intent.move.toArray()}});
}
for(const pos of [[0,0,0],[0,0,3.6]])for(const progress of [0,.71,1.6])for(const cooldown of [0,.2]){
 const a=actor(pos),brain=new BotBrain(a);
 Object.assign(brain,{path:[1,2,3],pi:0,noProg:progress,jumpCd:cooldown,bestD:3,goalTimer:4,repath:1,mvYaw:0,mvMag:1,_needJump:true});
 brain._tail(1/60,new THREE.Vector3(0,0,1),0,-.1,6,true);
 records.tail.push({pos,bounds:[...bounds],weapon:'shooter',charging:false,progress,jump_cd:cooldown,need_jump:true,want_move:true,result:{jump:a.intent.jump,jump_cd:brain.jumpCd,pi:brain.pi,no_progress:brain.noProg,skipped:!!brain._skipped,path:!!brain.path,goal_timer:brain.goalTimer,repath:brain.repath,need_jump:!!brain._needJump,best_distance:Number.isFinite(brain.bestD)?brain.bestD:null,move:a.intent.move.toArray()}});
}
await fs.writeFile(path.join(out,'data/bot_navigation.json'),JSON.stringify(records,null,2));
console.log(JSON.stringify({edges:records.edges.length,water:records.water.length,tail:records.tail.length,aim:records.aim.length}));
