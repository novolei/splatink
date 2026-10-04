// Execute original color conversion, FX recipes, projectile GPU submission and
// ScreenFX uniforms. No browser renderer is needed; record raw linear uploads.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
import {FX} from '../../src/fx/fx.js';
import {ScreenFX} from '../../src/fx/screenfx.js';
import {Projectiles} from '../../src/game/weapons.js';
import {TEAM_PALETTES,COLORBLIND_PALETTE} from '../../src/config.js';
import {G} from '../../src/core/ctx.js';
import {Environment} from '../../src/world/environment.js';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let seed=923413;
Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
const rgb=c=>[c.r,c.g,c.b].map(Math.fround);
const palettes=[...TEAM_PALETTES,COLORBLIND_PALETTE];
const cases=[];
const pos=new THREE.Vector3(0,1,0),dir=new THREE.Vector3(0,0,1);
function recipe(name,color){
 const records=[];const fx=Object.create(FX.prototype);
 Object.assign(fx,{q:1,_time:0,_dt:.04,_recycle:0,waterY:-1.6,paintEffects:true,_col:new THREE.Color(),_colB:new THREE.Color(),_colCache:new Map(),_camPos:new THREE.Vector3(0,5,-8),puffs:{name:'puffs'},glows:{name:'glows'}});
 const add=(path,c)=>records.push({path,color:rgb(c)});
 fx._sprite=(pool,px,py,pz,vx,vy,vz,c)=>add(pool.name,c);
 fx._spawnDrop=(px,py,pz,vx,vy,vz,c)=>{add('drops',c);return 0;};
 fx._shell=(p,c)=>add('sheets',c);
 fx._ringRaw=(p,n,c)=>add('rings',c);
 fx._beam=(p,c)=>add('beams',c);
 fx._ripple=(p,a,w,s,l,n,c)=>{if(c)add('rings',c);};fx._after=()=>{};fx._near=()=>true;
 const ops={mist:()=>fx.mist(pos,dir,color),form:()=>fx.formPop(pos,color,true,false),explosion:()=>fx.explosion(pos,color,3),spawn:()=>fx.spawnFlash(pos,color),storm:()=>fx.stormStart(pos,color,3.4),shooter:()=>fx.muzzle(pos,dir,color,'shooter'),blaster:()=>fx.muzzle(pos,dir,color,'blaster'),charger:()=>fx.muzzle(pos,dir,color,'charger'),bubbles:()=>fx.bubbles(pos,color,3),charge:()=>fx.chargeGlow(pos,color,.7),water:()=>fx.waterSplash(pos,1),dust:()=>fx.footstep(pos,color,0,dir,5),ghost:()=>fx.ghost(pos,color),trail:()=>fx.shotTrail(pos,dir,color,false),trailBig:()=>fx.shotTrail(pos,dir,color,true),sizzle:()=>fx.enemyInkSizzle(pos,color)};
 ops[name]();
 // Exercise both original stochastic satellite outcomes, so the accepted GPU
 // colors come from actual source emissions rather than a synthetic fallback.
 if(['trail','trailBig','sizzle'].includes(name))for(let i=0;i<15;i++)ops[name]();
 return records;
}
const renderer={getDrawingBufferSize:v=>v.set(1600,900)};
for(const palette of palettes)for(let team=0;team<2;team++){
 const colors=[new THREE.Color(palette.a),new THREE.Color(palette.b)],own=colors[team];
 const recipes=Object.fromEntries(['mist','form','explosion','spawn','storm','shooter','blaster','charger','bubbles','charge','water','dust','ghost','trail','trailBig','sizzle'].map(name=>[name,recipe(name,own)]));
 const sc=new ScreenFX({renderer,setExtraPass:()=>{}},{mode:'match',settings:{quality:'high',cameraShake:1},teamColors:colors,match:{paused:true,attract:false,local:{team,enemyTeam:1-team,alive:true}}});
 sc._startReveal({team});sc._land({team});sc.update(0,{_skipRender:true});
 const names=['uBlastColor','uHoleRim','uFlood','uLensColA','uLensColB','uEdgeInk','uHeart','uAura','uSwim','uSpeedTint','uKill','uShimmer','uCharge','uUrgency'];
 const screen=Object.fromEntries(names.map(name=>{const c=sc.U[name].value;return [name,[c.r??c.x,c.g??c.y,c.b??c.z].map(Math.fround)];}));
 const projectiles=new Projectiles(new THREE.Scene());
 // Native _charge_effects also draws the weapon's charger sight. Capture that
 // color from original Projectiles._updateBeams, not an invented RGB expectation.
 const sniper={alive:true,weaponRunner:{charging:true,charge:.7},weapon:{kind:'charger',rangeMin:11,rangeMax:27},color:own};
 G.actors=[sniper];G.physics={raycast:()=>({hit:false})};G.time=0;
 projectiles._muzzle=()=>pos;projectiles._aimFrom=()=>dir;
 projectiles._updateBeams(0);
 recipes.charge.push({path:'beams',color:rgb(projectiles.sights.get(sniper).material.uniforms.uColor.value)});
 const native=[];
 for(const type of ['shot','blast']){
  const age=type==='blast'?.93:.2,life=1;
  projectiles.list=[{type,delay:0,vel:new THREE.Vector3(0,0,20),age,life,vis:.12,size:.15,tail0:.8,tailK:1.3,wob:.04,seed:.5,wobF:20,pos:new THREE.Vector3(0,1,5),start:new THREE.Vector3(0,1,0),sats:3,owner:{color:own}}];
  projectiles._draw();
  const uploads=[];for(let i=0;i<projectiles.blobs.count;i++){const c=new THREE.Color();projectiles.blobs.getColorAt(i,c);uploads.push(rgb(c));}
  native.push({kind:type==='blast'?'blaster':'shooter',age,remaining:life-age,colors:uploads});
 }
 cases.push({palette:palette.id,hex:[palette.a,palette.b],team,linear:rgb(own),recipes,screen,projectiles:native});
 sc.dispose();
}
// Extract the actual source _teamOfColor body, including first-match behavior.
const main=await fs.readFile(path.resolve(base,'../src/main.js'),'utf8');
const body=main.match(/_teamOfColor\(color\) \{([\s\S]*?)\n  \}/)[1];
const teamOf=new Function('color','G',body);
const identity=[];
for(const palette of palettes){
 const colors=[new THREE.Color(palette.a),new THREE.Color(palette.b)];
 for(const [name,c] of [['team0',colors[0]],['team1',colors[1]],['whiteMix',colors[0].clone().lerp(new THREE.Color(1,1,1),.35)],['foam',new THREE.Color('#eef9ff')],['water',new THREE.Color('#bfe9ff')],['hdr',colors[0].clone().multiplyScalar(4)]])identity.push({hex:[palette.a,palette.b],name,color:rgb(c),team:teamOf(c,{teamColors:colors})});
}
const same=[new THREE.Color('#ff8a14'),new THREE.Color('#ff8a14')];identity.push({hex:['#ff8a14','#ff8a14'],name:'firstIdenticalTeam',color:rgb(same[0]),team:teamOf(same[0],{teamColors:same})});
const constants=Object.fromEntries(Object.entries({DUST:'#b8a98f',GRAIN:'#b9ae9c',FOAM:'#eef9ff',WATER:'#bfe9ff',FEATHER:'#f3f0e8'}).map(([key,hex])=>[key,{hex,linear:rgb(new THREE.Color(hex))}]));
const lighting=[];
const lights=fx=>({sun_direction:fx._light.sunDir.toArray().map(Math.fround),sun_color:rgb(fx._light.sunCol),sky_color:rgb(fx._light.sky),ground_color:rgb(fx._light.ground)});
const basefx=new FX(new THREE.Scene(),{quality:.25});lighting.push({name:'defaults',theme:{},expected:lights(basefx)});basefx.dispose();
for(const [name,T] of Object.entries(Environment.THEMES)){
 const env=Object.create(Environment.prototype),el=T.sunEl*Math.PI/180,az=T.sunAz*Math.PI/180;
 env.U={uZenith:{value:new THREE.Color(T.zenith)},uSkyMid:{value:new THREE.Color(T.skyMid)},uHorizon:{value:new THREE.Color(T.horizon)},uSunDir:{value:new THREE.Vector3(Math.cos(el)*Math.cos(az),Math.sin(el),Math.cos(el)*Math.sin(az)).normalize()},uCloudLit:{value:new THREE.Color(T.cloudLit)},uNight:{value:T.night}};
 env.sun={color:new THREE.Color(T.sunColor),intensity:T.sunIntensity};env.hemi={groundColor:new THREE.Color(T.hemiGround).multiplyScalar(T.hemiGroundK??1)};
 const fx=new FX(new THREE.Scene(),{quality:.25});fx.setLighting(env.getSkyColors());lighting.push({name,theme:T,expected:lights(fx)});fx.dispose();
}
await fs.writeFile(path.join(base,'data/fx_colors.json'),JSON.stringify({source:'Unmodified FX recipes/setLighting, Environment.getSkyColors, Projectiles._draw/_updateBeams, ScreenFX.update and main._teamOfColor; raw Float32 linear RGB uploads',constants,cases,identity,lighting}));
console.log(JSON.stringify({palettes:palettes.length,cases:cases.length,recipes:cases.length*16,identities:identity.length,lighting:lighting.length}));
