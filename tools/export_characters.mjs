/** Export the actual INKWAVE procedural geometry, shader data and sampled animation.
 * Run from the web checkout: node --experimental-loader ./splatink/tools/source_loader.mjs ./splatink/tools/export_characters.mjs
 * No Blender / browser / Godot process is needed. The source builders remain the authority.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {deflateSync, inflateSync} from 'node:zlib';
import * as THREE from 'three';
import {GLTFExporter} from 'three/addons/exporters/GLTFExporter.js';
import {createCanvas, GlobalFonts} from '@napi-rs/canvas';
import {Character} from '../../src/game/character.js';
import {G} from '../../src/core/ctx.js';
import {BONE_NAMES, BONE_INDEX, BONE_PARENT, getKidShared, getHairStyle, getRestPositions, getBoneInverses} from '../../src/game/character-geo.js';
import * as M from '../../src/game/character-mats.js';
import * as STYLE from '../../src/game/character-style.js';
import {FACE_SHADER} from '../../src/game/character-face.js';
import {WEAPON_KINDS, FIST_OFFSET, GRIP_HOLE_L, getWeaponDef, getSubDef, makeCoilMaterial} from '../../src/game/character-weapons.js';
import {buildRig as buildBossRig, buildParts as buildBossParts, buildCrablet, MC as BOSS_MC, CONT as BOSS_CONT} from '../../src/boss/bossModelGeo.js';
import {BossAnimator, C as BOSS_C} from '../../src/boss/bossAnim.js';
import {makeUniforms as makeBossUniforms, makeBossMaterials, makeCrabletMaterial, makeStencilTexture} from '../../src/boss/bossMats.js';
import {buildBossClipSpecs} from './boss_clip_specs.mjs';
import {sourceHeadParameters} from './source_character_layout.mjs';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(project, 'assets/characters');
const shaderOut = path.join(project, 'assets/shaders');
await fs.mkdir(out, {recursive:true});
await fs.mkdir(shaderOut, {recursive:true});
async function writeAsset(file, data) {
  const bytes=typeof data==='string'?Buffer.from(data):Buffer.from(data);
  const previous=await fs.readFile(file).catch(()=>null);
  if(previous?.equals(bytes))return;
  return fs.writeFile(file,bytes);
}
// Custom attributes are binary data, including transparent pixels. A Canvas would
// premultiply RGB by alpha and silently destroy zero-alpha attribute components.
const crcTable=Uint32Array.from({length:256},(_,i)=>{let c=i;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
function pngChunk(type,data){
  const name=Buffer.from(type),chunk=Buffer.alloc(data.length+12);chunk.writeUInt32BE(data.length);name.copy(chunk,4);data.copy(chunk,8);
  let crc=0xffffffff;for(const b of Buffer.concat([name,data]))crc=crcTable[(crc^b)&255]^(crc>>>8);
  chunk.writeUInt32BE((crc^0xffffffff)>>>0,data.length+8);return chunk;
}
function dataPNG(width,height,rgba){
  const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=6;
  const stride=width*4,rows=Buffer.alloc((stride+1)*height);
  for(let y=0;y<height;y++)Buffer.from(rgba.buffer,rgba.byteOffset+y*stride,stride).copy(rows,y*(stride+1)+1);
  const compressed=deflateSync(rows,{level:9});
  if(!inflateSync(compressed).equals(rows))throw new Error('Attribute PNG round-trip failed');
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),pngChunk('IHDR',ihdr),pngChunk('IDAT',compressed),pngChunk('IEND',Buffer.alloc(0))]);
}
async function configureExistingImports(){
  let changed=0;const locked=[];
  for(const filename of await fs.readdir(out)){
    if(!filename.endsWith('.import'))continue;
    const isData=filename.includes('__')&&filename.endsWith('.png.import'),isMesh=filename.endsWith('.glb.import');
    if(!isData&&!isMesh)continue;
    const file=path.join(out,filename),old=await fs.readFile(file,'utf8');let value=old;
    const flags=isMesh?{'meshes/force_disable_compression':'true','meshes/generate_lods':'true'}:{'compress/mode':'0','mipmaps/generate':'false','process/fix_alpha_border':'false','process/premult_alpha':'false','process/size_limit':'0','detect_3d/compress_to':'0'};
    for(const [key,setting]of Object.entries(flags))value=value.replace(new RegExp('^'+key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'=.*$','m'),`${key}=${setting}`);
    if(value!==old){
      try{await writeAsset(file,value);changed++;}
      catch(error){if(error.code!=='EBUSY')throw error;locked.push(filename);}
    }
  }
  return {changed,locked};
}
if(process.argv.includes('--configure-imports-only')){console.log(`Character import flags: ${JSON.stringify(await configureExistingImports())}; reimport changed files.`);process.exit(0);}
if(process.argv.includes('--usage-only')){
  const file=path.join(out,'manifest.json'),metadata=JSON.parse(await fs.readFile(file,'utf8'));
  for(const [name,asset]of Object.entries(metadata.assets)){
    if(name!=='body'&&!name.startsWith('hair_')&&!name.startsWith('brows_'))continue;
    const bytes=await fs.readFile(path.join(out,`${name}.glb`)),length=bytes.readUInt32LE(12),gltf=JSON.parse(bytes.subarray(20,20+length)),binary=bytes.subarray(28+length),view=new DataView(binary.buffer,binary.byteOffset,binary.byteLength);
    const parents=new Map();gltf.nodes.forEach((n,i)=>(n.children||[]).forEach(child=>parents.set(child,i)));
    const used=new Set(),skin=gltf.skins[0],joints=new Set(skin.joints);
    const read=(id,i,k)=>{const a=gltf.accessors[id],b=gltf.bufferViews[a.bufferView],size=a.componentType===5126?4:a.componentType===5123?2:1,offset=(b.byteOffset||0)+(a.byteOffset||0)+i*(b.byteStride||4*size)+k*size;
      const value=a.componentType===5126?view.getFloat32(offset,true):a.componentType===5123?view.getUint16(offset,true):view.getUint8(offset);return a.normalized?value/(a.componentType===5123?65535:255):value;};
    for(const [meshIndex,mesh]of gltf.meshes.entries()){const meshUsed=new Set();for(const p of mesh.primitives){if(p.attributes.JOINTS_0===undefined)continue;const count=gltf.accessors[p.attributes.JOINTS_0].count;
      for(let i=0;i<count;i++)for(let k=0;k<4;k++)if(read(p.attributes.WEIGHTS_0,i,k)>0){let node=skin.joints[read(p.attributes.JOINTS_0,i,k)];while(joints.has(node)){used.add(gltf.nodes[node].name);meshUsed.add(gltf.nodes[node].name);node=parents.get(node);}}
    }
      for(const node of gltf.nodes)if(node.mesh===meshIndex&&asset.meshes[node.name])asset.meshes[node.name].used_bones=skin.joints.map(i=>gltf.nodes[i].name).filter(name=>meshUsed.has(name));
    }
    asset.used_bones=skin.joints.map(i=>gltf.nodes[i].name).filter(name=>used.has(name));
  }
  await writeAsset(file,JSON.stringify(metadata,null,2));console.log('Updated exact body/module and individual mesh bone usage maps without replacing GLBs.');process.exit(0);
}
G.settings = {quality:'high'};
// Source full-aim grip frames are independent of the sampled animation state.
// Keep these data available to native pitch IK and first-shot virtual muzzles.
const aimMetadata={version:1,source:'Character HOLD + getAimMuzzle + weapon grip frames',pivot:[-0.03,0.93,0.05],weapons:{}};
for(const kind of WEAPON_KINDS){
  const c=new Character({weapon:kind,style:{hair:0}}),d=getWeaponDef(kind);
  aimMetadata.weapons[kind]={hold:c.hold,muzzle:d.muzzle.toArray(),handR:{pos:d.handR.pos.toArray(),quat:d.handR.quat.toArray()},handL:{pos:d.handL.pos.toArray(),quat:d.handL.quat.toArray()}};
  c.dispose();
}
await writeAsset(path.join(out,'aim_frames.json'),JSON.stringify(aimMetadata,null,2));
if(process.argv.includes('--aim-only')){console.log('Exported all seven source aiming and hand grip frames.');process.exit(0);}
// GLTFExporter's asynchronous FileReader protocol, implemented without a DOM.
globalThis.FileReader = class {
  async readAsArrayBuffer(blob) {this.result=await blob.arrayBuffer(); this.onloadend?.();}
  async readAsDataURL(blob) {this.result=`data:${blob.type};base64,${Buffer.from(await blob.arrayBuffer()).toString('base64')}`;this.onloadend?.();}
};

const manifest = (process.argv.includes('--boss-only')||process.argv.includes('--body-only'))?JSON.parse(await fs.readFile(path.join(out,'manifest.json'),'utf8')):{version:1, source:'INKWAVE src/game/character*.js', coordinates:'Original +Z forward, feet at Y=0, height 1.39 m', assets:{}, animations:{}, catalog:{}};
for (const key of ['SKIN_TONES','SKIN_NAMES','OUTFITS','OUTFIT_NAMES','IRIS','IRIS_NAMES','HAIR_STYLE_NAMES','HATS','HAT_NAMES','BROWS','BROW_NAMES','PRESETS']) manifest.catalog[key] = STYLE[key];
// Native secondary motion uses the style's own authored joint positions and spring constants.
// Export the same collision direction / twist axes as Character._buildRig.
const secondary={version:1,source:'Character._buildRig + _updateHair',head_center:[0,0.164,0.014],styles:{}};
for(let hair=0;hair<8;hair++)for(let hat=0;hat<4;hat++){
  const style={hair,hat,brows:0},h=getHairStyle(style),r=getRestPositions(style),hc=r.head.clone().add(new THREE.Vector3(...secondary.head_center));
  secondary.styles[`${hair}_${hat}`]=h.meta.map((m,si)=>{
    const into=hc.clone().sub(r[`hair${si}_0`]).normalize(),axes=[],coil=[],side=[];
    for(let k=0;k<=3;k++){
      const a=r[k<3?`hair${si}_${k}`:`hairTip${si}`],b=k<2?r[`hair${si}_${k+1}`]:k===2?r[`hairTip${si}`]:null;
      const axis=b?b.clone().sub(a):new THREE.Vector3(...axes[k-1]);
      if(axis.lengthSq()<1e-10)axis.set(0,-1,0);axis.normalize();
      const outward=a.clone().sub(hc).normalize(),a1=new THREE.Vector3().crossVectors(axis,outward);
      if(a1.lengthSq()<1e-8)a1.set(1,0,0);a1.normalize();
      const a2=new THREE.Vector3().crossVectors(axis,a1).normalize();
      axes.push(axis.toArray());coil.push(a1.toArray());side.push(a2.toArray());
    }
    return {dir:m.dir.toArray(),len:m.len,K:m.K,G:m.G,into:into.toArray(),axes,coil,side};
  });
}
await writeAsset(path.join(out,'secondary_motion.json'),JSON.stringify(secondary));
if(process.argv.includes('--secondary-only')){console.log(`Exported authored hair spring metadata: ${Object.keys(secondary.styles).length} styles.`);process.exit(0);}

// Store source attributes as a lossless 16-bit range-coded RGBA data atlas. UV2 indexes a vertex.
// Godot glTF only exposes COLOR/UV/UV2; this keeps every custom aFace/aCloth/aHair value intact.
const slots = [
  ['position','aEx'], ['color','aOcc'], ['uv','aTint','aMat'], ['aHead','aSeg'],
  ['aFace'], ['aCloth'], ['aHair'], ['aEyeS'], ['aSq'],
  ['aNativeFaceWeights'], ['normal'], ['aNativeFaceTorso'],
];
function slotValue(g, slot, i) {
  const names=slot===4 && g.hasAttribute('aM')?['aM']:slots[slot], vals=[];
  for (const name of names) {
    const attr=g.getAttribute(name);
    const size=attr?.itemSize ?? (['uv','aNativeFaceTorso'].includes(name)?2:['position','normal','color','aHead','aCloth','aHair','aEyeS','aSq'].includes(name)?3:['aFace','aM','aNativeFaceWeights'].includes(name)?4:1);
    for(let k=0;k<size;k++) vals.push(attr ? attr.array[i*size+k] : name==='aOcc'?0:name==='color'?1:0);
  }
  return [...vals,0,0,0,0].slice(0,4);
}
async function prepareMesh(mesh, id, kind, asset) {
  const originalMaterial=mesh.material;
  const g=mesh.geometry.clone(), n=g.attributes.position.count;
  if(kind==='skin'){
    const names=['head','jaw','cheekL','cheekR','neck','chest'],ids=names.map(name=>BONE_INDEX[name]),weights=new Float32Array(n*4),torso=new Float32Array(n*2);
    for(let i=0;i<n;i++)for(let k=0;k<4;k++){
      const id=g.attributes.skinIndex?.array[i*4+k],value=g.attributes.skinWeight?.array[i*4+k]||0,j=ids.indexOf(id);
      if(j>=0&&j<4)weights[i*4+j]+=value;else if(j>=4)torso[i*2+j-4]+=value;
    }
    g.setAttribute('aNativeFaceWeights',new THREE.Float32BufferAttribute(weights,4));g.setAttribute('aNativeFaceTorso',new THREE.Float32BufferAttribute(torso,2));
  }
  const width=Math.min(2048, 2**Math.ceil(Math.log2(Math.max(1,Math.min(n,2048))))), rows=Math.ceil(n/width), layers=slots.length*2;
  const rgba=new Uint8ClampedArray(width*rows*layers*4);
  const minima=[], maxima=[];
  for(let s=0;s<slots.length;s++) {
    const lo=[Infinity,Infinity,Infinity,Infinity], hi=[-Infinity,-Infinity,-Infinity,-Infinity];
    for(let i=0;i<n;i++){const v=slotValue(g,s,i);for(let k=0;k<4;k++){lo[k]=Math.min(lo[k],v[k]);hi[k]=Math.max(hi[k],v[k]);}}
    minima.push(lo);maxima.push(hi);
    for(let i=0;i<n;i++) {
      const v=slotValue(g,s,i), y=Math.floor(i/width), x=i%width;
      for(let k=0;k<4;k++) {
        const norm=hi[k]>lo[k]?(v[k]-lo[k])/(hi[k]-lo[k]):0;
        const q=Math.round(Math.max(0,Math.min(1,norm))*65535);
        rgba[((s*2*rows+y)*width+x)*4+k]=q>>8;
        rgba[(((s*2+1)*rows+y)*width+x)*4+k]=q&255;
      }
    }
  }
  const uv1=new Float32Array(n*2);
  for(let i=0;i<n;i++){uv1[i*2]=(i%width+0.5)/width;uv1[i*2+1]=(Math.floor(i/width)+0.5)/rows;}
  const dataName=`${asset}__${id}.png`;
  await writeAsset(path.join(out,dataName),dataPNG(width,rows*layers,rgba));
  for(const attr of Object.keys(g.attributes)) if(!['position','normal','uv','skinIndex','skinWeight'].includes(attr))g.deleteAttribute(attr);
  g.setAttribute('uv1',new THREE.Float32BufferAttribute(uv1,2));
  mesh.geometry=g; mesh.name=id;
  mesh.material=new THREE.MeshStandardMaterial({color:0xffffff,roughness:0.45,metalness:0,side:THREE.DoubleSide});
  mesh.userData={iw_kind:kind};
  manifest.assets[asset].meshes[id]={kind,data:`res://assets/characters/${dataName}`,minima,maxima,vertices:n,triangles:(g.index?g.index.count:n)/3,material:{color:originalMaterial?.color?.toArray(),roughness:originalMaterial?.roughness,metalness:originalMaterial?.metalness,emission:originalMaterial?.emissive?.toArray(),intensity:originalMaterial?.emissiveIntensity}};
  if(mesh.isSkinnedMesh){
    const used=new Set(),index=g.attributes.skinIndex,weights=g.attributes.skinWeight;
    for(let i=0;i<index.count;i++)for(let k=0;k<4;k++)if(weights.array[i*4+k]>0){let bone=mesh.skeleton.bones[index.array[i*4+k]];while(bone?.isBone){used.add(bone.name);bone=bone.parent;}}
    manifest.assets[asset].meshes[id].used_bones=BONE_NAMES.filter(name=>used.has(name));
  }
}
async function exportAsset(asset, group, meshKinds, animations=[]) {
  manifest.assets[asset]={path:`res://assets/characters/${asset}.glb`,meshes:{}};
  const pending=[];
  group.traverse(o=>{if(o.isMesh)pending.push(prepareMesh(o,o.name,meshKinds[o.name]||'plastic',asset));});
  await Promise.all(pending);
  group.updateMatrixWorld(true);
  if(asset==='body'||asset.startsWith('hair_')||asset.startsWith('brows_')){
    const used=new Set();
    group.traverse(mesh=>{if(!mesh.isSkinnedMesh)return;const index=mesh.geometry.attributes.skinIndex,weights=mesh.geometry.attributes.skinWeight;
      for(let i=0;i<index.count;i++)for(let k=0;k<4;k++)if(weights.array[i*4+k]>0){let bone=mesh.skeleton.bones[index.array[i*4+k]];while(bone?.isBone){used.add(bone.name);bone=bone.parent;}}
    });
    manifest.assets[asset].used_bones=BONE_NAMES.filter(name=>used.has(name));
  }
  const bytes=await new GLTFExporter().parseAsync(group,{binary:true,animations,onlyVisible:false,trs:true});
  await writeAsset(path.join(out,`${asset}.glb`),Buffer.from(bytes));
  manifest.assets[asset].bytes=bytes.byteLength;
  console.log(`${asset}: ${bytes.byteLength.toLocaleString()} bytes, ${pending.length} source meshes`);
}
function rigModule(style, geo, name) {
  const root=new THREE.Group();root.name='Module';
  const rest=getRestPositions(style), bones=BONE_NAMES.map(n=>{const b=new THREE.Bone();b.name=n;return b;}), by=Object.fromEntries(bones.map(b=>[b.name,b]));
  for(const name of BONE_NAMES){const p=BONE_PARENT[name];if(p){by[p].add(by[name]);by[name].position.copy(rest[name]).sub(rest[p]);}else{root.add(by[name]);by[name].position.copy(rest[name]);}}
  root.updateMatrixWorld(true);
  const skel=new THREE.Skeleton(bones,getBoneInverses(style));
  const mesh=new THREE.SkinnedMesh(geo,new THREE.MeshStandardMaterial());mesh.name=name;mesh.bind(skel,new THREE.Matrix4());root.add(mesh);
  return root;
}
function subsetGeometry(src, isBrow) {
  const idx=src.index?.array || Uint32Array.from({length:src.attributes.position.count},(_,i)=>i), skin=src.attributes.skinIndex;
  const use=[], oldToNew=new Map(), ids=[];
  for(let k=0;k<idx.length;k+=3){
    const bi=skin.array[idx[k]*4];const brow=bi===BONE_INDEX.browL||bi===BONE_INDEX.browR;
    if(brow!==isBrow)continue;
    for(let j=0;j<3;j++){const old=idx[k+j];if(!oldToNew.has(old)){oldToNew.set(old,ids.length);ids.push(old);}use.push(oldToNew.get(old));}
  }
  const geo=new THREE.BufferGeometry();
  for(const [name,attr] of Object.entries(src.attributes)){const arr=new attr.array.constructor(ids.length*attr.itemSize);for(let i=0;i<ids.length;i++)for(let j=0;j<attr.itemSize;j++)arr[i*attr.itemSize+j]=attr.array[ids[i]*attr.itemSize+j];geo.setAttribute(name,new THREE.BufferAttribute(arr,attr.itemSize,attr.normalized));}
  geo.setIndex(use);return geo;
}

const sampleFPS=30;
const faceNodeNames=['FaceMouth','FaceExpression','FaceMood','FaceLook','FaceGazeL','FaceGazeR','FaceLid'];
const headNodeNames=['SourceHeadFK','SourceHeadLook','SourceHeadTorso'];
function faceVectors(c){const u=c.u,m=u.uMouth.value,x=u.uMouth2.value,g=u.uGaze.value,l=u.uLid.value,v=u.uLook.value;return [[m.x,m.y,m.z],[m.w,x.y,x.z],[x.x,x.w,u.uPupil.value],[v.x,v.y,0],[g.x,g.y,g.z],[g.w,l.x,l.y],[l.z,l.w,0]];}
function sampleClip(weapon, action, length, loop, state, trigger, dance) {
  const c=new Character({name:'Native source capture',weapon,style:{hair:0,skin:0,outfit:0,eyes:0,hat:0,brows:0}});
  c.setLod('hero');
  const input={form:'kid',grounded:true,speed:0,localMove:{x:0,z:0},ink:1,...state};
  for(let i=0;i<60;i++) c.update(1/30,input);
  if(dance)c.setDance(dance);
  if(trigger)c.trigger(typeof trigger==='string'?trigger:trigger.name,typeof trigger==='string'?undefined:trigger.arg);
  const objects=Object.fromEntries(c.boneList.map(b=>[b.name,b]));
  Object.assign(objects,{Model:c.model,Kid:c.kid,Tank:c.tank.group,TankFill:c.tank.fill,WeaponR:c.weapon.pivot});
  for(const name of faceNodeNames)objects[name]=new THREE.Group();
  for(const name of headNodeNames)objects[name]=new THREE.Group();
  if(c.weapon.left)objects.WeaponL=c.weapon.left.pivot;
  const keys=Object.keys(objects), data=Object.fromEntries(keys.map(k=>[k,{position:[],quaternion:[],scale:[]}])) , times=[];
  let frames=Math.round(length*sampleFPS);
  if(loop&&input.speed>0) frames=Math.max(12,Math.round(sampleFPS*2/c.cad));
  for(let i=0;i<=frames;i++){
    const t=i/sampleFPS;
    if(action==='jump') {input.grounded=i===frames;input.vy=5.5-t*12;}
    if(action==='fire'&&i%Math.max(2,Math.round(0.105*sampleFPS))===0)c.trigger('shoot');
    c.update(i===0?0:1/sampleFPS,input);times.push(t);
    faceVectors(c).forEach((v,i)=>objects[faceNodeNames[i]].position.fromArray(v));
    sourceHeadParameters(c).forEach((v,i)=>objects[headNodeNames[i]].position.fromArray(v));
    for(const key of keys){const o=objects[key],d=data[key];d.position.push(...o.position.toArray());d.quaternion.push(...o.quaternion.toArray());d.scale.push(...o.scale.toArray());}
  }
  const tracks=[];
  for(const key of keys)for(const property of ['position','quaternion','scale']){
    if((faceNodeNames.includes(key)||headNodeNames.includes(key))&&property!=='position')continue;
    const arr=data[key][property],size=property==='quaternion'?4:3;
    if(loop&&['idle','walk','run','strafe_left','strafe_right','backpedal'].includes(action)){
      // A discrete gait period rarely lands on an exact 30 Hz boundary. Closing only
      // the last key caused a 79-degree ankle seam. Two circular binomial passes
      // preserve the source cycle while distributing that residual over ~67 ms.
      for(let pass=0;pass<2;pass++){
        const previous=arr.slice();
        for(let frame=0;frame<frames;frame++){
          const left=(frame+frames-1)%frames,right=(frame+1)%frames;
          if(property==='quaternion'){
            const q=new THREE.Quaternion().fromArray(previous,frame*4);
            const sides=new THREE.Quaternion().fromArray(previous,left*4).slerp(new THREE.Quaternion().fromArray(previous,right*4),0.5);
            q.slerp(sides,0.5).toArray(arr,frame*4);
          }else for(let k=0;k<size;k++)arr[frame*size+k]=(previous[left*size+k]+2*previous[frame*size+k]+previous[right*size+k])*0.25;
        }
      }
    }
    if(loop)for(let k=0;k<size;k++)arr[arr.length-size+k]=arr[k];
    const C=property==='quaternion'?THREE.QuaternionKeyframeTrack:THREE.VectorKeyframeTrack;
    tracks.push(new C(`${key}.${property}`,times,arr).optimize());
  }
  const name=`${weapon}_${action}`,duration=frames/sampleFPS;
  manifest.animations[name]={loop,duration,weapon,action,source:'Character.update + Character.trigger'};
  c.dispose();return new THREE.AnimationClip(name,duration,tracks);
}

const bossUniforms=makeBossUniforms();bossUniforms.uContInv.value.copy(BOSS_MC).invert();
const bossMaterials=makeBossMaterials(bossUniforms);
const clips=[];
if(!process.argv.includes('--shaders-only')){
if(!process.argv.includes('--boss-only')){
const base=new Character({name:'INKWAVE native body',weapon:'shooter',style:{hair:0,skin:0,outfit:0,eyes:0,hat:0,brows:0}});
base.setLod('hero');base.model.name='Model';base.kid.name='Kid';base.root.name='InkBody';
faceVectors(base).forEach((v,i)=>{const node=new THREE.Group();node.name=faceNodeNames[i];node.position.fromArray(v);base.kid.add(node);});
sourceHeadParameters(base).forEach((v,i)=>{const node=new THREE.Group();node.name=headNodeNames[i];node.position.fromArray(v);base.kid.add(node);});
// Keep the original rigid tank and its original bone parent, and two weapon pivot sockets.
base.tank.group.name='Tank';base.tank.fill.name='TankFill';base.tank.glass.name='TankGlass';
base.weapon.pivot.name='WeaponR';base.weapon.pivot.clear();
const left=new THREE.Group();left.name='WeaponL';left.position.copy(GRIP_HOLE_L);base.bones.handL.add(left);
base.bomb.group.removeFromParent();base.squidRoot.removeFromParent();
for(const set of base.lodSets)if(set)for(const mesh of set.list){if(set.t!==0||mesh.userData.iwMat==='hair')mesh.removeFromParent();else mesh.name=mesh.userData.iwMat==='eye'?'Eyes':mesh.userData.iwMat==='skin'?'Skin':'Cloth';}
const bodyKinds={Skin:'skin',Cloth:'cloth',Eyes:'eye',TankFill:'fill',TankGlass:'glass'};
for(const tier of ['game','far']){
  const shared=getKidShared(tier),suffix=tier==='game'?'Game':'Far';
  for(const [name,geometry,kind]of [['Skin',shared.skin,'skin'],['Cloth',shared.cloth,'cloth'],['Eyes',shared.eyes,'eye']]){
    const mesh=new THREE.SkinnedMesh(geometry);mesh.name=name+suffix;mesh.bind(base.skeleton,new THREE.Matrix4());base.kid.add(mesh);bodyKinds[mesh.name]=kind;
  }
}
for(const weapon of WEAPON_KINDS){
  console.log(`Sampling ${weapon} original animation...`);
  clips.push(sampleClip(weapon,'idle',4,true,{}));
  clips.push(sampleClip(weapon,'walk',1.5,true,{speed:1.6,localMove:{x:0,z:1}}));
  clips.push(sampleClip(weapon,'run',1,true,{speed:5.5,localMove:{x:0,z:1}}));
  clips.push(sampleClip(weapon,'strafe_left',1,true,{speed:4,localMove:{x:-1,z:0}}));
  clips.push(sampleClip(weapon,'strafe_right',1,true,{speed:4,localMove:{x:1,z:0}}));
  clips.push(sampleClip(weapon,'backpedal',1,true,{speed:3,localMove:{x:0,z:-1}}));
  clips.push(sampleClip(weapon,'fire',0.8,true,{firing:true,rolling:weapon==='roller',speed:weapon==='roller'?3:0,localMove:{x:0,z:1}}));
  clips.push(sampleClip(weapon,'jump',0.9,false,{grounded:false,vy:5},'jump'));
  clips.push(sampleClip(weapon,'fall',1,true,{grounded:false,vy:-4}));
  for(const [action,duration,event] of [['shoot',0.35,'shoot'],['flick',0.8,'flick'],['throw',0.85,'throw'],['hit',0.55,'hit'],['land',0.6,'land'],['spawn',1.2,'spawn'],['charge_release',0.5,'charge_release'],['dodge',0.65,'dodge'],['special_leap',1.4,'special_leap'],['special_slam',0.85,'special_slam']])clips.push(sampleClip(weapon,action,duration,false,{},event));
  clips.push(sampleClip(weapon,'charge',1,true,{firing:true,charge:1}));
  clips.push(sampleClip(weapon,'sub_aim',1,true,{subAim:true}));
  for(const action of ['admire','hairflip','wink'])clips.push(sampleClip(weapon,action,2,false,{},action));
  if(weapon==='roller')clips.push(sampleClip(weapon,'roll',1,true,{rolling:true,speed:3,localMove:{x:0,z:1}}));
  if(weapon==='dualies'){
    clips.push(sampleClip(weapon,'shoot_left',0.35,false,{}, {name:'shoot',arg:{hand:1}}));
    for(const [suffix,x,z]of [['left',1,0],['right',-1,0],['back',0,-1]])clips.push(sampleClip(weapon,`dodge_${suffix}`,0.65,false,{}, {name:'dodge',arg:{x,z,t:.3}}));
  }
  clips.push(sampleClip(weapon,'victory',4,true,{},null,'victory'));
  clips.push(sampleClip(weapon,'defeat',4,true,{},null,'defeat'));
  for(const action of ['menu_idle','locker_idle','lobby_pose'])clips.push(sampleClip(weapon,action,6,true,{},null,action));
}
await exportAsset('body',base.root,bodyKinds,clips);
manifest.head_parameters={source:'Character.P FK + stabilised-look inputs before quaternion mixing',nodes:headNodeNames};
if(process.argv.includes('--body-only')){
  await writeAsset(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));
  base.dispose();
  console.log(`Updated only body: ${clips.length} existing source clips, three original head parameter tracks; other assets retained.`);
  process.exit(0);
}
for(let hair=0;hair<8;hair++)for(let hat=0;hat<4;hat++){
  const st={hair,hat,brows:0};const geo=subsetGeometry(getHairStyle(st,'hero').geo,false);
  const module=rigModule(st,geo,'Hair'),mesh=module.children.find(x=>x.isSkinnedMesh),kinds={Hair:'hair'};
  for(const tier of ['game','far']){const lowGeo=subsetGeometry(getHairStyle(st,tier).geo,false);const lowMesh=new THREE.SkinnedMesh(lowGeo);lowMesh.name=tier==='game'?'HairGame':'HairFar';lowMesh.bind(mesh.skeleton,new THREE.Matrix4());module.add(lowMesh);kinds[lowMesh.name]='hair';}
  await exportAsset(`hair_${hair}_${hat}`,module,kinds);
}
for(let brows=0;brows<4;brows++){
  const st={hair:0,hat:0,brows};const geo=subsetGeometry(getHairStyle(st,'hero').geo,true);
  await exportAsset(`brows_${brows}`,rigModule(st,geo,'Brows'),{Brows:'hair'});
}
for(const kind of WEAPON_KINDS){
  const c=new Character({weapon:kind,style:{hair:0}}), w=c.weapon;
  const root=new THREE.Group();root.name='Weapon';root.add(w.off);
  w.off.name='WeaponOffset';w.body.name='WeaponBody';w.ink.name='WeaponInk';w.bodyFar.name='WeaponBodyFar';w.inkFar.name='WeaponInkFar';w.muzzle.name='Muzzle';
  const kinds={WeaponBody:'plastic',WeaponInk:'ink',WeaponBodyFar:'plastic',WeaponInkFar:'ink'};
  for(const [name,part] of Object.entries(w.parts)){part.name=`Part_${name}`;part.children[0].name=`Mesh_${name}`;kinds[`Mesh_${name}`]=part.userData.mat==='ink'?'ink':part.userData.mat==='lamp'?'glow':'plastic';}
  if(w.glow){w.glow.name='Coil';kinds.Coil='coil';}
  if(w.drum){w.drum.name='Drum';w.drum.children[0].name='DrumInk';w.drum.children[1].name='DrumCaps';Object.assign(kinds,{DrumInk:'ink',DrumCaps:'plastic'});}
  await exportAsset(`weapon_${kind}`,root,kinds);
  const d=getWeaponDef(kind);
  manifest.assets[`weapon_${kind}`].inHand={pos:d.inHand.pos.toArray(),quat:d.inHand.quat.toArray(),muzzle:d.muzzle.toArray(),dual:!!d.dual};
  if(d.inHandL)manifest.assets[`weapon_${kind}`].inHandL={pos:d.inHandL.pos.toArray(),quat:d.inHandL.quat.toArray()};
  c.dispose();
}
const squid=new THREE.Group();squid.name='Squid';const sq=getKidShared('hero').squid;
for(const [name,geo]of Object.entries(sq)){const mesh=new THREE.Mesh(geo);mesh.name=`Squid_${name}`;squid.add(mesh);}
await exportAsset('squid',squid,{Squid_body:'squid',Squid_dark:'dark',Squid_eyes:'eye'});
const bomb=new THREE.Group();bomb.name='Bomb';const bd=getSubDef('bomb');
for(const [name,geo]of [['BombBody',bd.body],['BombInk',bd.ink]]){const mesh=new THREE.Mesh(geo);mesh.name=name;bomb.add(mesh);}
await exportAsset('bomb',bomb,{BombBody:'plastic',BombInk:'ink'});
manifest.assets.bomb.inHandL={pos:bd.inHandL.pos.toArray(),quat:bd.inHandL.quat.toArray()};
}

// Boss source model: retain original shipping-container crab sculpt, skinning and original clocks.
const bossDur={slam:[1.15,1.2,1],barrage:[0.85,2,0.8],sweep:[1.15,2.1,0.9],charge:[1.15,1.5,0.9],crablets:[0.9,0.8,0.6],frenzy:[1.2,3,1.7]};
function bossCaptureModel(phase=1){
  const rig=buildBossRig(),root=new THREE.Group();root.name='Hullbreaker';root.add(rig.by.base);root.updateMatrixWorld(true);
  const model={root,physics:null,_emitImpact(){},_emitEvent(){},_emitFoot(){}};
  const anim=new BossAnimator(model,rig);anim.update(0,{phase});return {rig,root,anim};
}
function sampleBossClip(name,duration,state={},loop=false){
  const m=bossCaptureModel(state.phase||1), data=m.rig.bones.map(()=>({position:[],quaternion:[],scale:[]})),times=[];
  const channelValues=[[],[]];
  let st={phase:1,speed:0,move:null,grounded:true,...state};
  for(let i=0;i<30;i++)m.anim.update(1/30,{phase:st.phase});
  if(st.movePhase && st.movePhase!=='tele'){
    const until=st.movePhase==='act'?0:1;
    const durations=st._capture_durations||bossDur[st.move];
    for(let phase=0;phase<=until;phase++)for(let i=0;i<=Math.ceil(durations[phase]*30);i++){
      const t=Math.min(i/30,durations[phase]),previous=i===0?0:Math.min((i-1)/30,durations[phase]);
      m.anim.update(t-previous,{...st,movePhase:['tele','act','rec'][phase],moveT:t,phaseDur:durations[phase]});
    }
  }
  const frames=Math.ceil(duration*30);
  for(let i=0;i<=frames;i++){
    const t=Math.min(i/30,duration),previous=i===0?0:Math.min((i-1)/30,duration);
    if(st.speed>0)m.root.position.z=t*st.speed;
    if(st.move)st.moveT=t;
    m.anim.update(t-previous,st);times.push(t);
    for(let j=0;j<m.rig.bones.length;j++){const b=m.rig.bones[j],d=data[j];d.position.push(...b.position.toArray());d.quaternion.push(...b.quaternion.toArray());d.scale.push(...b.scale.toArray());}
    channelValues[0].push(m.anim.P[BOSS_C.glowL],m.anim.P[BOSS_C.cannon],m.anim.P[BOSS_C.belly]);
    channelValues[1].push(m.anim.sp.tear.x,m.anim.P[BOSS_C.by],m.anim.P[BOSS_C.steam]);
  }
  const tracks=[];
  for(let j=0;j<2;j++){
    const values=channelValues[j];
    if(loop)for(let k=0;k<3;k++)values[values.length-3+k]=values[k];
    tracks.push(new THREE.VectorKeyframeTrack(`BossChannels${j}.position`,times,values).optimize());
  }
  for(let j=0;j<data.length;j++)for(const property of ['position','quaternion','scale']){
    const values=data[j][property],size=property==='quaternion'?4:3;
    if(loop)for(let k=0;k<size;k++)values[values.length-size+k]=values[k];
    const C=property==='quaternion'?THREE.QuaternionKeyframeTrack:THREE.VectorKeyframeTrack;
    tracks.push(new C(`${m.rig.bones[j].name}.${property}`,times,values).optimize());
  }
  manifest.animations[`boss_${name}`]={loop,duration,boss:true,phase:st.phase,params:st.params||{},source:'BossAnimator.update + BossBrain._start clocks'};
  return new THREE.AnimationClip(`boss_${name}`,duration,tracks);
}
const boss=bossCaptureModel(), bossParts=buildBossParts(boss.rig,'high'), bossKinds={};
for(const bone of boss.rig.bones){const parent=bone.parent?.isBone?boss.rig.rest[bone.parent.name]:new THREE.Vector3();bone.position.copy(boss.rig.rest[bone.name]).sub(parent);bone.quaternion.identity();bone.scale.setScalar(1);}
boss.root.updateMatrixWorld(true);
const bossSkeleton=new THREE.Skeleton(boss.rig.bones);
for(const [kind,bucket]of Object.entries(bossParts.buckets)){if(!bucket.nv)continue;const mesh=new THREE.SkinnedMesh(bucket.geometry(),bossMaterials[kind]);mesh.name=`Boss_${kind}`;mesh.bind(bossSkeleton);boss.root.add(mesh);bossKinds[mesh.name]=`boss_${kind}`;}
manifest.bossSockets={};
const bossSockets={...bossParts.sockets,
  shellF:['shell',new THREE.Vector3(0,.05,1.5).applyMatrix4(new THREE.Matrix4().makeRotationX(BOSS_CONT.pitch)).add(BOSS_CONT.pos)],
  shellR:['shell',new THREE.Vector3(0,.1,-1.55).applyMatrix4(new THREE.Matrix4().makeRotationX(BOSS_CONT.pitch)).add(BOSS_CONT.pos)],
  body:['head',new THREE.Vector3(0,2.2,2.3)]};
for(const [name,[bone,p]]of Object.entries(bossSockets)){
  const socket=new THREE.Object3D();socket.name=`Socket_${name}`;socket.position.copy(p).sub(boss.rig.rest[bone]);boss.rig.by[bone].add(socket);
  manifest.bossSockets[name]={bone,position:socket.position.toArray()};
}
for(let i=0;i<2;i++){const node=new THREE.Group();node.name=`BossChannels${i}`;boss.root.add(node);}
manifest.bossChannels={BossChannels0:['glowL','cannon','belly'],BossChannels1:['tear','body_y','steam'],source:'BossAnimator.P + tear spring, sampled at the exact bone clip times'};
const bossClips=buildBossClipSpecs().map(spec=>sampleBossClip(spec.name,spec.duration,spec.state,spec.loop));
manifest.bossAnimationPhases={count:bossClips.length,phases:3,naming:'boss_{p2_|p3_}{action}',source:'Original BossAnimator sampled with BossBrain final clocks/params'};
await exportAsset('boss',boss.root,bossKinds,bossClips);
const crabRig=buildCrablet('high'),crabRoot=new THREE.Group();crabRoot.name='Crablet';crabRoot.add(crabRig.by.base);crabRoot.updateMatrixWorld(true);
const crabSkel=new THREE.Skeleton(crabRig.bones),crabMesh=new THREE.SkinnedMesh(crabRig.geo);crabMesh.name='CrabletBody';crabMesh.bind(crabSkel);crabRoot.add(crabMesh);
await exportAsset('crablet',crabRoot,{CrabletBody:'boss_crablet'});
// The source canvas stencil contains its fictional container brand/code, placard and hand-painted warning.
GlobalFonts.registerFromPath(path.resolve(project,'../assets/fonts/TitanOne-latin.woff2'),'HullbreakerDisplay');
GlobalFonts.registerFromPath(path.resolve(project,'../assets/fonts/Rubik-latin.woff2'),'HullbreakerText');
globalThis.document={createElement(type){if(type==='canvas')return createCanvas(1024,1024);throw new Error(type);}};
const stencil=makeStencilTexture();await stencil.ready;
await writeAsset(path.join(out,'boss_stencil.png'),stencil.tex.image.toBuffer('image/png'));
delete globalThis.document;
if(process.argv.includes('--boss-only')){
  await writeAsset(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));
  console.log(`Updated source Boss, ${bossClips.length} clips over three phases, ${Object.keys(manifest.bossSockets).length} sockets and six synchronized material/hit channels.`);
  process.exit(0);
}
}

// Capture the expanded source material snippets, then adapt the Three physical-pipeline hooks.
// Colour, patterns, stitching, cloth weave, mask, hair grooves, suckers remain the original GLSL.
function capture(material) {
  const inc=['common','color_fragment','roughnessmap_fragment','metalnessmap_fragment','normal_fragment_maps','emissivemap_fragment','lights_physical_fragment','aomap_fragment','opaque_fragment','lights_physical_pars_fragment'];
  const shader={uniforms:{},vertexShader:'#include <common>\n#include <begin_vertex>\n#include <skinning_pars_vertex>\n#include <beginnormal_vertex>\n#include <skinnormal_vertex>',fragmentShader:inc.map((n,i)=>`#include <${n}>\n/*BOUNDARY_${i}*/`).join('\n')};
  material.onBeforeCompile?.(shader,null);
  const at=(name)=>{const i=inc.indexOf(name),start=shader.fragmentShader.indexOf(`#include <${name}>`)+`#include <${name}>`.length,end=shader.fragmentShader.indexOf(`/*BOUNDARY_${i}*/`);return shader.fragmentShader.slice(start,end).trim();};
  return {shader,at};
}
const fmt=v=>Number(v.toFixed(8)).toString();
const glslFloat=v=>`${fmt(v)}${Number.isInteger(v)?'.0':''}`;
function defaultUniform(type, v) {
  if(v===undefined)return type==='float'?'0.0':type==='vec2'?'vec2(0.0)':type==='vec3'?'vec3(0.0)':type==='vec4'?'vec4(0.0)':'0';
  if(typeof v==='number')return `${fmt(v)}${Number.isInteger(v)?'.0':''}`;
  if(v.isMatrix4){const a=v.elements.map(x=>`${fmt(x)}${Number.isInteger(x)?'.0':''}`);return `mat4(${Array.from({length:4},(_,i)=>`vec4(${a.slice(i*4,i*4+4).join(',')})`).join(',')})`;}
  if(v.isMatrix3){const a=v.elements.map(glslFloat);return `mat3(${Array.from({length:3},(_,i)=>`vec3(${a.slice(i*3,i*3+3).join(',')})`).join(',')})`;}
  const a=v.isColor?[v.r,v.g,v.b]:v.toArray?.();
  return a?`${type}(${a.map(x=>`${fmt(x)}${Number.isInteger(x)?'.0':''}`).join(',')})`:type+'(0.0)';
}
const u=M.makeCharUniforms();
// Runtime palette updates must include tone-specific physical skin uniforms,
// not just albedo. Capture the authored material constructor as the fixture.
const skinShading={source:'makeSkinMaterial onBeforeCompile original uniforms',skins:[]};
for(const [id,color]of STYLE.SKIN_TONES.entries()){
  const uniforms=M.makeCharUniforms(),material=M.makeSkinMaterial(uniforms,color);
  const {shader}=capture(material);
  skinShading.skins.push({id,color,lum:shader.uniforms.uSkinLum.value,width:shader.uniforms.uSSSW.value.toArray(),tint:shader.uniforms.uSSSTint.value.toArray(),freckle:shader.uniforms.uFreckle.value});
  material.dispose();
}
await writeAsset(path.join(out,'skin_shading.json'),JSON.stringify(skinShading,null,2));
const sourceMats={skin:M.makeSkinMaterial(u,STYLE.SKIN_TONES[0]),cloth:M.makeClothMaterial(u),hair:M.makeHairMaterial(u),squid:M.makeSquidMaterial(u),plastic:M.getPlasticMaterial(),eye:M.makeEyeMaterial(u)};
sourceMats.coil=makeCoilMaterial();
for(const [kind,material]of Object.entries(bossMaterials))sourceMats[`boss_${kind}`]=material;
sourceMats.boss_crablet=makeCrabletMaterial(bossUniforms);
const assignments={
  skin:'vBindPos=d0.xyz; vEx=d0.w; vHead=d3.xyz; vFace=d4; vIwUv=d2.xy; COLOR=vec4(d1.rgb,1.0);',
  cloth:'vBindPos=d0.xyz; vEx=d0.w; vCloth=d5.xyz; vIwUv=d2.xy; vOcc=d1.w; COLOR=vec4(d1.rgb,1.0);',
  hair:'vBindPos=d0.xyz; vTint=d2.z; vStrand=vec4(d1.r,d1.g,d2.x,d2.y); vSinA=d1.b*2.0-1.0; vGearCol=d1.rgb; vHair=d6.xyz;',
  squid:'vTint=d1.r; vSqUv=d2.xy; vSqPart=d0.w; vSqP=d0.xyz; vSq=d8.xyz; vSqWig=d1.gb;',
  plastic:'vMat=d2.w; vWPos=d0.xyz;',
  eye:'vEyeUv=d2.xy; vSide=d0.w; vEyeS=d7.xyz; vEyeSock=d7.xyz; vLidC=vec2(0.0);',
  coil:'vSeg=d3.w;',
};
const needed={skin:[0,1,2,3,4],cloth:[0,1,2,5],hair:[0,1,2,6],squid:[0,1,2,8],plastic:[0,1,2],eye:[0,2,7]};
const hemiUniforms='uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);';
const hemiFragment='float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix)*AO;';
// Vendored Three's 16x16 RG16F DFG table is an authored physical-pipeline input,
// not an approximation. Preserve its half-float values and linear/clamp sampling.
const threeSource=await fs.readFile(path.resolve(project,'../vendor/three/build/three.module.js'),'utf8');
const dfgBlock=threeSource.slice(threeSource.indexOf('Precomputed DFG LUT'),threeSource.indexOf('function getDFGLUT'));
const dfgHalf=[...dfgBlock.matchAll(/0x([0-9a-f]+)/g)].map(x=>parseInt(x[1],16));
if(dfgHalf.length!==512)throw new Error(`Source DFG table has ${dfgHalf.length} components`);
const dfgValues=Array.from({length:256},(_,i)=>`vec2(${glslFloat(THREE.DataUtils.fromHalfFloat(dfgHalf[i*2]))},${glslFloat(THREE.DataUtils.fromHalfFloat(dfgHalf[i*2+1]))})`);
await writeAsset(path.join(shaderOut,'character_dfg.gdshaderinc'),`// Exact Three RG16F DFG LUT, 16x16, 4096 integration samples per texel.\nconst vec2 SOURCE_DFG[256]={${dfgValues.join(',\n')}};\nvec2 native_dfg(vec2 uv){vec2 p=clamp(uv*16.0-0.5,vec2(0.0),vec2(15.0));ivec2 a=ivec2(floor(p));ivec2 b=min(a+ivec2(1),ivec2(15));vec2 f=fract(p);return mix(mix(SOURCE_DFG[a.y*16+a.x],SOURCE_DFG[a.y*16+b.x],f.x),mix(SOURCE_DFG[b.y*16+a.x],SOURCE_DFG[b.y*16+b.x],f.x),f.y);}\n`);
function sourcePhysical(kind,mat,at){
  if(!['skin','cloth','hair','squid','plastic','eye'].includes(kind))return {pars:'',fragment:'',hemi:hemiFragment};
  const specIntensity=mat.specularIntensity??1;
  const fields={clearcoat:'native_clearcoat',clearcoatRoughness:'native_clearcoatRoughness',sheenColor:'native_sheenColor',sheenRoughness:'native_sheenRoughness',specularColor:'native_specularColor',specularColorBlended:'native_specularColorBlended'};
  let hooks=at('lights_physical_fragment').replace(/^\s*#(?:ifdef|ifndef|endif)[^\n]*$/gm,'');
  for(const [field,value]of Object.entries(fields))hooks=hooks.replaceAll(`material.${field}`,value);
  const fragment=`vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(${glslFloat(0.04*specIntensity)});native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(${glslFloat(specIntensity)},1.0,metalnessFactor);
native_clearcoat=${glslFloat(mat.clearcoat??0)};native_clearcoatRoughness=clamp(max(${glslFloat(mat.clearcoatRoughness??0.1)},0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=${defaultUniform('vec3',mat.sheenColor?.clone().multiplyScalar(mat.sheen??0)||new THREE.Color(0))};native_sheenRoughness=${glslFloat(mat.sheenRoughness??0.6)};
${hooks}
native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=${glslFloat(0.5*Math.sqrt(specIntensity))};CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=${kind==='skin'?'iwSSS':'0.0'};native_thin=${kind==='skin'?'iwThin':'0.0'};
native_gum_on=${['hair','squid'].includes(kind)?'iwGumOn':'0.0'};native_gum_thin=${['hair','squid'].includes(kind)?'iwGumThin':'0.0'};native_gum_trans=${['hair','squid'].includes(kind)?'iwGumTrans':'vec3(0.0)'};native_direct_ao=${kind==='cloth'?'mix(1.0,iwAO,0.35)':'1.0'};
`;
  const specAo={skin:'mix(1.0,AO,0.8)',cloth:'mix(1.0,AO,0.7)',hair:'mix(0.4,1.0,AO)',squid:'mix(0.45,1.0,AO)'}[kind]||'1.0';
  const hemi=`vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,${specAo},source_coat_world_normal);
${['hair','squid'].includes(kind)?'EMISSION+=native_gum_on*native_gum_trans*(source_hemi+source_ibl_irradiance(source_world_normal)/PI)*(0.015+0.14*native_gum_thin*native_gum_thin)*AO*native_coat_attenuation;':''}
`;
  return {pars:`${kind==='skin'?'#define SOURCE_SKIN\n':''}#include "res://assets/shaders/character_lighting.gdshaderinc"\n#include "res://assets/shaders/source_cube_uv.gdshaderinc"\n#include "res://assets/shaders/character_indirect.gdshaderinc"`,fragment,hemi};
}
needed.skin.push(9,10,11);needed.eye.push(10);
function nativeFaceVertex(kind){
  if(!['skin','eye'].includes(kind))return {pars:'',body:''};
  let pars=`uniform vec2 native_eye_close=vec2(0.0); uniform vec4 uLid=vec4(0.0); uniform mat3 native_face_head=mat3(1.0);
// Explicit column arithmetic avoids legacy Adreno SPIR-V matrix-size assertions.
vec3 native_mul3(mat3 m,vec3 v){return m[0]*v.x+m[1]*v.y+m[2]*v.z;}
vec3 native_mul3t(mat3 m,vec3 v){return vec3(dot(m[0],v),dot(m[1],v),dot(m[2],v));}
mat3 native_matrix3(mat3 a,mat3 b){return mat3(native_mul3(a,b[0]),native_mul3(a,b[1]),native_mul3(a,b[2]));}
mat3 native_inverse3(mat3 m){vec3 a=cross(m[1],m[2]),b=cross(m[2],m[0]),c=cross(m[0],m[1]);float det=dot(m[0],a);return mat3(vec3(a.x,b.x,c.x),vec3(a.y,b.y,c.y),vec3(a.z,b.z,c.z))/det;}
\n`;
  for(let i=0;i<2;i++)pars+=`const vec3 native_eye_c${i}=${defaultUniform('vec3',FACE_SHADER.eyeC[i])}; const mat3 native_eye_m${i}=${defaultUniform('mat3',FACE_SHADER.eyeM[i])}; const mat3 native_eye_mi${i}=${defaultUniform('mat3',FACE_SHADER.eyeMi[i])};\n`;
  pars+=`vec2 native_lid_close(int si){float close=si==0?native_eye_close.x:native_eye_close.y;return vec2(max(close,si==0?uLid.x:uLid.y),max(close,si==0?uLid.z:uLid.w));}\n`;
  if(kind==='skin'){
    pars+=`uniform mat3 native_face_jaw=mat3(1.0);uniform mat3 native_face_cheekL=mat3(1.0);uniform mat3 native_face_cheekR=mat3(1.0);uniform mat3 native_face_neck=mat3(1.0);uniform mat3 native_face_chest=mat3(1.0);\nuniform vec3 uMouthU=${defaultUniform('vec3',FACE_SHADER.mouthU)};uniform float uMouthHW=${glslFloat(FACE_SHADER.mouthHW)};\n`;
    return {pars,body:`
if(d4.x+d4.y>0.0001 || abs(d4.z)>0.0001){
  mat3 face_skin=native_face_head*d9.x+native_face_jaw*d9.y+native_face_cheekL*d9.z+native_face_cheekR*d9.w+native_face_neck*d11.x+native_face_chest*d11.y;
  vec3 iwPos=d0.xyz; vec3 iwNormal=d10.xyz;
  if(d4.x+d4.y>0.0001){
    int si=d0.x>=0.0?0:1;vec2 cl=native_lid_close(si);float angle=d4.x*cl.x-d4.y*cl.y;
    mat3 M=si==0?native_eye_m0:native_eye_m1;mat3 Mi=si==0?native_eye_mi0:native_eye_mi1;vec3 C=si==0?native_eye_c0:native_eye_c1;
    vec3 s=native_mul3(Mi,d0.xyz-C);float ca=cos(angle),sa=sin(angle);
    iwPos=C+native_mul3(M,vec3(s.x,ca*s.y-sa*s.z,sa*s.y+ca*s.z));
    vec3 nu=native_mul3t(M,iwNormal);iwNormal=normalize(native_mul3t(Mi,vec3(nu.x,ca*nu.y-sa*nu.z,sa*nu.y+ca*nu.z)));
  }
  if(abs(d4.z)>0.0001){
    float w=abs(d4.z),up=d4.z>0.0?1.0:0.0;vec3 d=iwPos-uMouthC;float mx=d.x,my=dot(d,uMouthU);
    float xn=clamp(mx/uMouthHW,-1.35,1.35),xw=min(xn*xn,1.3);float band=exp(-my*my/0.00016);
    float curve=clamp(uMouth.x,-1.3,1.3),width=clamp(uMouth.y,0.2,1.5),open=clamp(uMouth.z,0.0,1.0);
    float pucker=clamp(uMouth2.z,0.0,1.0)+clamp((0.8-width)*1.2,0.0,0.6)*step(curve,-0.6);
    vec3 dp=vec3(mx*((width-1.0)*0.75-0.3*pucker+0.2*open),0.0,0.0);
    dp+=uMouthU*(curve*0.0062*xw*mix(0.4,1.0,band)+uMouth.w*mx*0.45);
    dp-=uMouthF*max(curve,0.0)*0.0017*xw*band;
    dp+=uMouthU*up*open*0.0024*max(0.0,1.0-xw)*band;
    dp+=uMouthU*up*clamp(uMouth2.y,0.0,1.0)*0.003*smoothstep(0.1,0.8,xn)*band;
    dp+=uMouthF*pucker*0.005*max(0.0,1.0-xw)*band;iwPos+=dp*w;
  }
  // Godot executes custom vertex hooks after GPU skinning. Transform only the
  // authored rest-space deformation delta by the same six face-bone bases.
  VERTEX+=native_mul3(face_skin,iwPos-d0.xyz);NORMAL=normalize(native_mul3(face_skin,iwNormal));
}\n`};
  }
  pars+=`uniform vec4 uGaze=vec4(0.0);uniform float uEyeRest=${glslFloat(FACE_SHADER.rest)};\n`;
  return {pars,body:`
if(abs(d0.w)>1.5){
  int si=d0.w>0.0?0:1;float sd=d0.w>0.0?1.0:-1.0;
  mat3 M=si==0?native_eye_m0:native_eye_m1;mat3 Mi=si==0?native_eye_mi0:native_eye_mi1;vec3 C=si==0?native_eye_c0:native_eye_c1;
  float yaw=uEyeRest+sd*clamp(0.6*(uLook.x*1.25+(si==0?uGaze.x:uGaze.z)),-0.36,0.36);
  float pitch=clamp(0.6*(uLook.y*1.25+(si==0?uGaze.y:uGaze.w)),-0.3,0.3);
  float cy=cos(yaw),sy=sin(yaw),cp=cos(-pitch),sp=sin(-pitch);
  mat3 Ry=mat3(vec3(cy,0.0,-sy),vec3(0.0,1.0,0.0),vec3(sy,0.0,cy));
  mat3 Rx=mat3(vec3(1.0,0.0,0.0),vec3(0.0,cp,sp),vec3(0.0,-sp,cp));mat3 R=native_matrix3(Ry,Rx);
  vec3 s=native_mul3(R,d7.xyz);vec3 iwEP=C+native_mul3(M,s);VERTEX+=native_mul3(native_face_head,iwEP-d0.xyz);
  NORMAL=normalize(native_mul3(native_face_head,native_mul3t(Mi,native_mul3(R,native_mul3t(M,d10.xyz)))));
  vEyeS=d7.xyz;vEyeSock=s;vLidC=native_lid_close(si);
  mat3 view_basis=mat3(MODELVIEW_MATRIX[0].xyz,MODELVIEW_MATRIX[1].xyz,MODELVIEW_MATRIX[2].xyz);
  mat3 Ai=native_inverse3(native_matrix3(native_matrix3(native_matrix3(view_basis,native_face_head),M),R));vAi0=Ai[0];vAi1=Ai[1];vAi2=Ai[2];
}else{mat3 Ai=native_inverse3(mat3(MODELVIEW_MATRIX[0].xyz,MODELVIEW_MATRIX[1].xyz,MODELVIEW_MATRIX[2].xyz));vAi0=Ai[0];vAi1=Ai[1];vAi2=Ai[2];}\n`};
}
needed.coil=[3];
for(const kind of Object.keys(sourceMats).filter(k=>k.startsWith('boss_'))){assignments[kind]='vB=d0.xyz;vU=d2.xy;vM=d4;';needed[kind]=[0,2,4];}
for(const [kind,mat] of Object.entries(sourceMats)){
  const {shader,at}=capture(mat);
  const physical=sourcePhysical(kind,mat,at);
  let pars=at('common').replace(/varying\s+(\w+)\s+(\w+)\s*;/g,'varying $1 $2;');
  const globalLocals=[];
  pars=pars.replace(/(?:vec3 iwGumTrans = vec3\(0\.0\);|float iwGumThin = 0\.0;|float iwGumOn = 0\.0;|float iwSSS = 1\.0;|float iwThin = 0\.0;)/g,s=>{globalLocals.push(s);return '';});
  pars=pars.replace(/uniform float ([\w, ]+);/g,(full,names)=>names.split(',').map(name=>'uniform float '+name.trim()+';').join('\n'));
  pars=pars.replace(/uniform\s+(\w+)\s+(\w+)\s*;/g,(_,type,name)=>type==='sampler2D'?`uniform sampler2D ${name} : filter_linear_mipmap;`:`uniform ${type} ${name} = ${defaultUniform(type,shader.uniforms[name]?.value)};`);
  // Source constant array construction uses the GLSL constructor syntax; Godot uses braces.
  pars=pars.replace(/const int SEG\[10\] = int\[10\]\(([^;]+)\);/g,'const int SEG[10] = {$1};');
  const nativeFace=nativeFaceVertex(kind);pars+='\n'+nativeFace.pars+'\n'+hemiUniforms;
  const uniforms=Array.from({length:slots.length},(_,i)=>`uniform vec4 data_min_${i};\nuniform vec4 data_max_${i};`).join('\n');
  let color=at('color_fragment'),rough=at('roughnessmap_fragment'),metal=at('metalnessmap_fragment'),bump=at('normal_fragment_maps'),emissive=at('emissivemap_fragment');
  if(kind==='eye')color=color.replace('mat3(vAi0, vAi1, vAi2) * normalize(vViewPosition)','native_mul3(mat3(vAi0, vAi1, vAi2),normalize(vViewPosition))');
  if(kind==='coil'){pars+='\nuniform vec3 uTeam=vec3(1.0);';emissive=emissive.replace(/\bemissive\b/g,'uTeam');}
  if(kind.startsWith('boss_')){color=color.replace(/\bE\b/g,'sourceEyeEmission').replace(/\broughness\b/g,'roughnessFactor').replace(/\bmetalness\b/g,'metalnessFactor').replace(/gl_FrontFacing/g,'FRONT_FACING').replace(/texture2D/g,'texture');pars=pars.replace(/texture2D/g,'texture');}
  const reads=needed[kind].map(i=>`vec4 d${i}=source_read(UV2,float(${i}),data_min_${i},data_max_${i});`).join('\n');
  const allReads=[...new Set(needed[kind])];
  const dataDeclarations=reads;
  let extra='';
  extra+=nativeFace.body;
  if(kind==='squid')extra=`float wig=d1.g; float ph=d1.b*6.2831; float wave=sin(uTime*uWig.y+ph-wig*4.2); float co=cos(uTime*uWig.y*0.8+ph*1.3-wig*3.1); float k=wig*wig*uWig.x*2.0; vec2 rad=normalize(VERTEX.xz+vec2(0.00001)); VERTEX.xz+=rad*(wave*k*1.1)+vec2(-rad.y,rad.x)*(co*k*0.9); VERTEX.y+=(wave*0.5+0.5)*wig*uWig.x*0.8+wave*k*0.35;`;
  const baseColor=kind==='skin'?'skin_color*COLOR.rgb':['plastic','cloth'].includes(kind)?'COLOR.rgb':kind==='coil'?`vec3(${mat.color.toArray().map(fmt).join(',')})`:'vec3(1.0)';
  const shaderText=`// Generated from source material ${kind}; original authored color/detail equations.\nshader_type spatial;\nrender_mode diffuse_lambert,${mat.side===THREE.DoubleSide?'cull_disabled':mat.side===THREE.BackSide?'cull_front':'cull_back'};\nuniform sampler2D source_data : filter_nearest, repeat_disable;\n${uniforms}\nuniform vec3 skin_color=vec3(1.0,0.6939,0.5395);\nuniform float hit_flash=0.0;\nuniform float rim_strength=0.0;\n${pars}\n${physical.pars}\n${kind==='squid'?'varying vec2 vSqWig; uniform float uTime=0.0; uniform vec3 uWig=vec3(0.012,9.0,0.0);':''}\nvec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/${slots.length*2}.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/${slots.length*2}.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}\nvoid vertex(){\n${dataDeclarations}\n${assignments[kind]}\n${kind==='plastic'?'COLOR=vec4(d1.rgb,1.0);':''}\n${extra}\n}\nvoid fragment(){\nvec4 diffuseColor=vec4(${baseColor},1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=${glslFloat(mat.roughness||0.4)}; float metalnessFactor=${glslFloat(mat.metalness||0)}; vec3 totalEmissiveRadiance=vec3(0.0);\n${globalLocals.join('\n')}\n${color}\n${rough}\n${metal}\n${bump}\n${emissive}\nALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=${kind==='skin'?'0.32':'0.5'};\n${['hair','squid','eye'].includes(kind)?'CLEARCOAT=0.8; CLEARCOAT_ROUGHNESS=0.12;':''}\n${kind.startsWith('boss_')?'AO=clamp(bAO,0.0,1.0);CLEARCOAT=clamp(bCC,0.0,1.0);CLEARCOAT_ROUGHNESS=bCCR;':''}\n${['skin','cloth','hair','squid'].includes(kind)?'AO=clamp(iwAO,0.0,1.0);':''}\nEMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);\n${physical.fragment}\n${physical.hemi}\n}\n`;
  // Character wraps these three source materials after their own injections.
  // Preserve the final outgoing-light wrapper independently of PBR clearcoat.
  const rimScale={skin:1,cloth:.7,hair:1.2}[kind];
  let wrappedText=shaderText;
  if(rimScale!==undefined){
    wrappedText=wrappedText.replace('uniform float rim_strength=0.0;',`uniform float rim_strength=0.0;
uniform vec4 uIwRim=vec4(0.075,0.08125,0.09375,3.4);
uniform vec3 uIwRimL=vec3(0.2981424,0.5962848,-0.745356);
uniform vec3 uIwFill=vec3(0.0);
uniform bool native_rim_world=false;`);
    wrappedText=wrappedText.replace(/\n}\n$/,`
vec3 rim_view=normalize(VIEW);
vec3 rim_direction=native_rim_world?normalize((VIEW_MATRIX*vec4(uIwRimL,0.0)).xyz):uIwRimL;
float rim_fresnel=pow(1.0-clamp(dot(normal,rim_view),0.0,1.0),uIwRim.w);
float rim_side=clamp(dot(normal,rim_direction)*0.5+0.5,0.0,1.0);
EMISSION+=uIwRim.rgb*(${glslFloat(rimScale)}*rim_fresnel*(0.3+0.7*rim_side*rim_side));
float rim_fill=clamp(dot(normal,normalize(vec3(0.25,0.45,1.0)))*0.6+0.4,0.0,1.0);
EMISSION+=uIwFill*diffuseColor.rgb*rim_fill*rim_fill;
}
`);
  }
  const compiledText=physical.pars?wrappedText.replace(/(render_mode [^;]+);/,'$1,ambient_light_disabled;'):wrappedText;
  await writeAsset(path.join(shaderOut,`character_${kind}.gdshader`),compiledText);
}
await writeAsset(path.join(shaderOut,'character_ink.gdshader'),`shader_type spatial;
render_mode diffuse_lambert,cull_back;
uniform vec3 uTeam=vec3(1.0,0.254,0.007);
uniform float hit_flash=0.0;
uniform float charge=0.0;
uniform vec3 base_color=vec3(0.015);
uniform float use_base_color=0.0;
uniform float base_roughness=0.16;
uniform vec3 emission_color=vec3(0.0);
uniform float emission_intensity=0.0;
${hemiUniforms}
void fragment(){ALBEDO=mix(uTeam,base_color,use_base_color);ROUGHNESS=base_roughness;SPECULAR=0.5;CLEARCOAT=1.0-use_base_color;CLEARCOAT_ROUGHNESS=0.12;EMISSION=vec3(hit_flash)+emission_color*emission_intensity;vec3 normal=NORMAL;${hemiFragment}}
`);
if(process.argv.includes('--shaders-only')){console.log('Regenerated native character shaders only.');process.exit(0);}
manifest.face={mouthC:FACE_SHADER.mouthC.toArray(),mouthF:FACE_SHADER.mouthF.toArray()};
manifest.limitations=['Source geometry is retained; source GLSL color/detail hooks and vertex colors are adapted to Godot PBR. Original wrapped skin SSS, gummy transmission, per-class sheen/coat and direct GGX with the exact DFG table are ported. Original PMREM irradiance/radiance and dielectric/metallic multiple scattering are now ported. Shadow filtering and secondary materials still differ; lighting is not claimed pixel-identical.','Animation clips sample source procedural motion at 30 Hz. Six locomotion cycles use two circular binomial passes to repair loop seams. Native pose/trajectory matching, inertialization and original analytic leg IK add world foot contacts; full source swing targeting still differs. Source lid, mouth and eye vertex-deformation equations are ported, driven by sampled expression tracks and live native skinning bases.','Hair modules preserve their own rest skeletons and use source head-inertia springs, head-exclusion and twist limits at hero/game LOD. Far LOD retains sampled secondary motion.'];
await writeAsset(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));
await writeAsset(path.join(out,'README.md'),`# Source character assets\n\nGenerated by tools/export_characters.mjs from the checked-in INKWAVE builders. Geometry is original, not a substitute model. 32 hair/headgear combinations, four eyebrow shapes, ten shader-side outfits, nine skin tones, eight iris gradients and seven weapon models retain the source catalog order.\n\nBody carries ${clips.length} source-sampled clips at 30 Hz. Hair/brows contain matching source rigs and attach via pose copies. Data atlases preserve all custom geometry attributes at 16-bit range precision. The shader color/detail snippets come directly from character-mats.js; Hero materials use the original direct BRDF, DFG table and prefiltered PMREM lighting; Godot supplies light visibility and shadows.\n\n${manifest.limitations.map(x=>'- '+x).join('\n')}\n`);
console.log(`Done: ${Object.keys(manifest.assets).length} assets and ${clips.length} clips.`);
console.log(`Character import flags: ${JSON.stringify(await configureExistingImports())}; reimport changed files.`);
