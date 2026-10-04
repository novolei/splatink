// Portable pose database from the actual original 87-bone native character animations.
// Source clips are in-place. Their trajectory features are explicit virtual gameplay speed tags.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {Matrix4,Vector3,Quaternion} from '../../vendor/three/build/three.module.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const body=await fs.readFile(path.join(root,'assets/characters/body.glb'));
const jsonLength=body.readUInt32LE(12),g=JSON.parse(body.subarray(20,20+jsonLength)),bin=body.subarray(28+jsonLength);
const accessor=id=>{const a=g.accessors[id],v=g.bufferViews[a.bufferView],n={SCALAR:1,VEC2:2,VEC3:3,VEC4:4,MAT4:16}[a.type];if(a.componentType!==5126)throw Error('motion accessor not f32');return new Float32Array(bin.buffer,bin.byteOffset+(v.byteOffset||0)+(a.byteOffset||0),a.count*n);};
const joints=g.skins[0].joints,parents=new Map();for(let i=0;i<g.nodes.length;i++)for(const c of g.nodes[i].children||[])parents.set(c,i);
const jointIndex=new Map(joints.map((id,i)=>[id,i])),names=joints.map(i=>g.nodes[i].name),bp=joints.map(i=>jointIndex.get(parents.get(i))??-1);
const selected=['hips','spine','head','handL','handR','footL','footR'],selectedIds=selected.map(n=>names.indexOf(n));
const times=[0,0.1,0.2,0.3,0.4,0.6,0.8],dims=42+times.length*3,rate=30;
const speeds={idle:[0,0],walk:[0,1.6],run:[0,5.5],strafe_left:[-4,0],strafe_right:[4,0],backpedal:[0,-3]};
const weapons=['shooter','roller','charger','blaster','dualies','slosher','splatling'];
const clips=[],poses=[],features=[];
const p=new Vector3(),q=new Quaternion(),s=new Vector3(),mat=new Matrix4();
function sampleTrack(track,t,size,isRotation){const ts=track.times,data=track.values;let k=0;while(k+1<ts.length&&ts[k+1]<=t)k++;let end=Math.min(k+1,ts.length-1),f=end===k?0:(t-ts[k])/(ts[end]-ts[k]);if(isRotation){const a=new Quaternion().fromArray(data,k*4),b=new Quaternion().fromArray(data,end*4);return a.slerp(b,f).toArray();}return Array.from({length:size},(_,i)=>data[k*size+i]*(1-f)+data[end*size+i]*f);}
function sample(tracks,t){const locals=joints.map(i=>{const n=g.nodes[i];return [...(n.translation||[0,0,0]),...(n.rotation||[0,0,0,1]),...(n.scale||[1,1,1])];});for(const tr of tracks){const b=jointIndex.get(tr.node);if(b===undefined)continue;const size=tr.kind==='rotation'?4:3,off=tr.kind==='translation'?0:tr.kind==='rotation'?3:7;locals[b].splice(off,size,...sampleTrack(tr,t,size,size===4));}const globals=[];for(let i=0;i<locals.length;i++){const row=locals[i],m=mat.clone().compose(p.fromArray(row),q.fromArray(row,3),s.fromArray(row,7));globals[i]=bp[i]<0?m:globals[bp[i]].clone().multiply(m);}return {locals,positions:selectedIds.map(i=>new Vector3().setFromMatrixPosition(globals[i]))};}
for(const weapon of weapons)for(const [action,speed]of Object.entries(speeds)){
 const a=g.animations.find(a=>a.name===`${weapon}_${action}`);if(!a)throw Error(`missing ${weapon}_${action}`);
 const tracks=a.channels.map(c=>{const sm=a.samplers[c.sampler];return {node:c.target.node,kind:c.target.path,times:accessor(sm.input),values:accessor(sm.output)};});
 const duration=Math.max(...tracks.map(t=>t.times.at(-1))),count=Math.max(2,Math.round(duration*rate)),start=features.length;
 const clip={name:a.name,weapon,action,start,count,duration,velocity:speed};clips.push(clip);
 for(let f=0;f<count;f++){
  const t=f/rate,current=sample(tracks,t),prev=sample(tracks,(t-1/rate+duration)%duration),next=sample(tracks,(t+1/rate)%duration),feature=[];
  for(let i=0;i<selected.length;i++){const v=next.positions[i].clone().sub(prev.positions[i]).multiplyScalar(rate*.5);feature.push(...current.positions[i].toArray(),...v.toArray());}
  for(const future of times)feature.push(speed[0]*future,speed[1]*future,0);
  features.push(feature);poses.push(current.locals.flat());
 }
}
const mean=Array(dims).fill(0),std=Array(dims).fill(0),weights=[];
for(const f of features)for(let d=0;d<dims;d++)mean[d]+=f[d]/features.length;
for(const f of features)for(let d=0;d<dims;d++)std[d]+=(f[d]-mean[d])**2/features.length;
for(let d=0;d<dims;d++){std[d]=Math.max(Math.sqrt(std[d]),d>=42?.3:.02);if(d>=42)weights.push(d%3===2?0.4:2.8);else{const bone=Math.floor(d/6),velocity=d%6>=3;weights.push((bone>=5?1.2:bone===3||bone===4?.22:.55)*(velocity?.35:1));}}
const normalized=features.flatMap(f=>f.map((v,d)=>(v-mean[d])/std[d]));
const metadata={version:1,source:'assets/characters/body.glb: original Character.update samples',source_sha256:crypto.createHash('sha256').update(body).digest('hex'),reference_plugin:'D:/Godot resource/rooftop-bird-team: trajectory + pose query, continuation hysteresis, inertialization design',fps:rate,dimensions:dims,bones:names,parents:bp,selected_bones:selected,trajectory_times:times,pose_stride:names.length*10,count:features.length,clips,mean,std,weights,feature_path:'res://assets/animation/locomotion.features.bin',pose_path:'res://assets/animation/locomotion.poses.bin',limitations:['Authored clips are in-place; trajectory is generated from explicit speed/direction tags, not measured root motion.','Database preserves the INKWAVE 87-bone rig and holds. Rooftop 24-bone or Mixamo clips are not directly compatible.','Six source locomotion cycles per weapon; no new authored stop/pivot clips are claimed.']};
await fs.mkdir(path.join(root,'assets/animation'),{recursive:true});
await fs.writeFile(path.join(root,'assets/animation/locomotion.features.bin'),Buffer.from(Float32Array.from(normalized).buffer));
await fs.writeFile(path.join(root,'assets/animation/locomotion.poses.bin'),Buffer.from(Float32Array.from(poses.flat()).buffer));
await fs.writeFile(path.join(root,'data/motion_matching.json'),JSON.stringify(metadata));
console.log(`Motion database: ${clips.length} weapon clips, ${features.length} poses, ${dims}D, ${names.length} bones; ${Math.round((normalized.length+poses.flat().length)*4/1024)} KiB.`);
