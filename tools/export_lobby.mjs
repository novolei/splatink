/** Export the real source alley and studio pedestal/podium without running Godot. */
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),out=path.join(root,'splatink');
async function write(name,data){const file=path.join(out,name),bytes=Buffer.from(data),old=await fs.readFile(file).catch(()=>null);if(old?.equals(bytes))return;await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,bytes);}
const sourceShowcase=await fs.readFile(path.join(root,'src/game/showcase.js'),'utf8');
const moodBlock=sourceShowcase.match(/const MOODS = (\{[\s\S]*?\n\});/);
if(!moodBlock)throw Error('Original showcase MOODS missing');
const studioMoods=Function('"use strict";return ('+moodBlock[1]+');')();
if(process.argv.includes('--lighting-only')){const d=JSON.parse(await fs.readFile(path.join(out,'data/lobby.json'),'utf8'));d.studio_moods=studioMoods;await write('data/lobby.json',JSON.stringify(d));console.log('Exported source studio loadout/win/lose lighting moods.');process.exit(0);}
let data;
if(process.argv.includes('--shaders-only'))data=JSON.parse(await fs.readFile(path.join(out,'data/lobby.json'),'utf8'));
else{
const server=http.createServer(async(req,res)=>{try{const url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(url==='/lobby-export'){res.setHeader('Content-Type','text/html');res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}const p=path.resolve(root,'.'+url);if(!p.startsWith(root+path.sep))throw Error('path');res.setHeader('Content-Type',{'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.woff2':'font/woff2','.png':'image/png'}[path.extname(p)]||'application/octet-stream');res.end(await fs.readFile(p));}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(8493,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
const page=await browser.newPage({viewport:{width:1280,height:720}});
page.on('pageerror',error=>console.error(error.message));
await page.exposeFunction('saveNative',async(name,b64)=>write(name,Buffer.from(b64,'base64')));
await page.goto('http://127.0.0.1:8493/lobby-export');
try{
 data=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js'),{LobbySet,ALLEY}=await import('/src/game/lobbySet.js'),{Showcase}=await import('/src/game/showcase.js'),{Character}=await import('/src/game/character.js'),{G}=await import('/src/core/ctx.js'),{TEXLIB_GLSL}=await import('/src/world/texlib.js');
  const library=await (await fetch('/splatink/data/texture_library.json')).json();
  G.settings={quality:'high'};G.quality={particles:1};
  const b64=bytes=>{let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s);};
  const saveJSON=(name,value)=>saveNative(name,b64(new TextEncoder().encode(JSON.stringify(value))));
  const R=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});R.setSize(1280,720);R.outputColorSpace=T.SRGBColorSpace;R.toneMapping=T.NoToneMapping;
  const fakeTex=()=>new T.DataArrayTexture(new Uint8Array(4*library.names.length).fill(255),1,1,library.names.length);
  const lib={layers:Object.fromEntries(library.names.map((n,i)=>[n,i])),meta:library.meta,albedo:fakeTex(),normal:fakeTex(),orm:fakeTex()};
  const set=new LobbySet(R,{quality:'high',texlib:lib});await set.ready;set.update(0,0);set.root.updateMatrixWorld(true);
  const studio=new Showcase(R,Character);studio._aimLights(new T.Vector3(0,0.8,0),1,'loadout');studio.stageL=studio._buildLoadoutStage();studio.stageR=studio._buildResultsStage();studio.t=4;studio.mode='loadout';studio._cameraPedestal('loadout',1280,720);studio.scene.updateMatrixWorld(true);
  const camera=c=>({pos:c.position.toArray(),target:c.getWorldDirection(new T.Vector3()).add(c.position).toArray(),fov:c.fov,near:c.near,far:c.far,view:c.view});
  const vector=v=>v?.toArray?v.toArray():v;
  const texMap=new Map(),textures=[];
  async function texture(tex){
   if(!tex)return null;if(tex===lib.albedo)return {library:'albedo'};if(tex===lib.normal)return {library:'normal'};if(tex===lib.orm)return {library:'orm'};
   if(tex.isRenderTargetTexture)return null;
   if(texMap.has(tex))return texMap.get(tex);
   const image=tex.image;if(!image||(!image.width&&!image.videoWidth))return null;
   const id=textures.length,name=`assets/textures/lobby/lobby_${String(id).padStart(2,'0')}.png`;
   const cv=document.createElement('canvas');cv.width=image.width;cv.height=image.height;const cx=cv.getContext('2d');
   if(image.data)cx.putImageData(new ImageData(new Uint8ClampedArray(image.data),image.width,image.height),0,0);else cx.drawImage(image,0,0);
   await saveNative(name,cv.toDataURL('image/png').split(',')[1]);
   const record={path:'res://'+name,flip_y:tex.flipY,color_space:tex.colorSpace,mipmaps:tex.generateMipmaps,repeat:tex.wrapS===T.RepeatWrapping};textures.push(record);texMap.set(tex,record);return record;
  }
  async function uniforms(U){const result={};for(const [key,u]of Object.entries(U||{})){const v=u.value;if(v?.isTexture){const t=await texture(v);if(t)result[key]={kind:'texture',value:t};}else if(v!==null&&v!==undefined){const kind=typeof v==='number'?'float':v.isColor||v.isVector3?'vec3':v.isVector2?'vec2':v.isVector4?'vec4':v.isMatrix4?'mat4':Array.isArray(v)?'array_'+(v[0]?.isVector2?'vec2':'vec4'):null;if(kind)result[key]={kind,value:Array.isArray(v)?v.map(vector):vector(v)};}}return result;}
  const materialMap=new Map(),materials=[];
  const inc=['common','color_fragment','roughnessmap_fragment','metalnessmap_fragment','normal_fragment_maps','emissivemap_fragment','lights_fragment_end','opaque_fragment','tonemapping_fragment'];
  async function material(m){if(materialMap.has(m))return materialMap.get(m);const id=materials.length;materialMap.set(m,id);
   const result={id,unlit:!!m.isMeshBasicMaterial,shader:!!m.isShaderMaterial,additive:m.blending===T.CustomBlending||m.blending===T.AdditiveBlending,transparent:!!m.transparent,depth_test:m.depthTest,depth_write:m.depthWrite,side:m.side,color:m.color?.toArray()||[1,1,1],roughness:m.roughness??0.8,metalness:m.metalness??0,opacity:m.opacity??1,emission:m.emissive?.toArray()||[0,0,0],intensity:m.emissiveIntensity??0,map:await texture(m.map),emissive_map:await texture(m.emissiveMap),uniforms:{},snippets:{}};materials.push(result);
   if(m.isShaderMaterial){result.vertex=m.vertexShader;result.fragment=m.fragmentShader;result.uniforms=await uniforms(m.uniforms);}else{
    const s={uniforms:{},vertexShader:['common','begin_vertex','uv_vertex','uv_pars_vertex','project_vertex'].map(x=>`#include <${x}>\n/*V_${x}*/`).join('\n'),fragmentShader:inc.map(x=>`#include <${x}>\n/*F_${x}*/`).join('\n')};m.onBeforeCompile?.(s,R);
    for(const key of inc){const tag=`#include <${key}>`,start=s.fragmentShader.indexOf(tag)+tag.length,end=s.fragmentShader.indexOf(`/*F_${key}*/`);result.snippets[key]=s.fragmentShader.slice(start,end).replace(TEXLIB_GLSL,'#include "res://assets/shaders/source_texlib.gdshaderinc"').trim();}
    result.vertex_common=s.vertexShader.slice(s.vertexShader.indexOf('#include <common>')+17,s.vertexShader.indexOf('/*V_common*/')).trim();
    result.vertex_begin=s.vertexShader.slice(s.vertexShader.indexOf('#include <begin_vertex>')+23,s.vertexShader.indexOf('/*V_begin_vertex*/')).trim();
    result.uniforms=await uniforms(s.uniforms);result.defines=s.defines;
   }return id;
  }
  const chunks=[];let offset=0;
  const chunk=(array,type='f32')=>{const a=type==='u32'?new Uint32Array(array):new Float32Array(array),bytes=new Uint8Array(a.buffer),rec={offset,length:a.length,type};offset+=bytes.length;chunks.push(bytes);return rec;};
  const records=[];
  async function collect(root,scope){const objects=[];root.traverse(n=>{if(n.isMesh&&n.geometry.attributes.position?.count)objects.push(n);});for(const n of objects){const m=Array.isArray(n.material)?n.material[0]:n.material;const record={name:n.name||`${scope}_${records.length}`,scope,attributes:Object.fromEntries(Object.entries(n.geometry.attributes).map(([key,a])=>[key,{...chunk(a.array),size:a.itemSize,instanced:!!a.isInstancedBufferAttribute}])),index:n.geometry.index?chunk(n.geometry.index.array,'u32'):null,transform:n.matrixWorld.toArray(),visible:n.visible,material:await material(m),cast_shadow:!!n.castShadow};if(n.isInstancedMesh){const mat=new T.Matrix4(),col=new T.Color();record.instances=[];record.visible_count=n.count;for(let i=0;i<n.instanceMatrix.count;i++){n.getMatrixAt(i,mat);if(n.instanceColor)n.getColorAt(i,col);record.instances.push({transform:mat.toArray(),color:n.instanceColor?col.toArray():[1,1,1]});}}records.push(record);}}
  await collect(set.root,'alley');await collect(studio.stageL.group,'pedestal');await collect(studio.stageR.group,'podium');
  const bytes=new Uint8Array(offset);let cursor=0;for(const part of chunks){bytes.set(part,cursor);cursor+=part.length;}await saveNative('assets/world/lobby.bin',b64(bytes));
  const lights=sc=>{const rows=[];sc.traverse(n=>{if(n.isLight)rows.push({name:Object.keys(set.lights).find(k=>set.lights[k]===n)||Object.keys(studio).find(k=>studio[k]===n)||n.type,type:n.type,pos:n.position.toArray(),target:n.target?.position.toArray(),color:n.color.toArray(),srgb:'#'+n.color.getHexString(),ground:n.groundColor?.toArray(),intensity:n.intensity,distance:n.distance,decay:n.decay,angle:n.angle,penumbra:n.penumbra,cast_shadow:n.castShadow,shadow:n.castShadow?{bias:n.shadow.bias,normal_bias:n.shadow.normalBias,near:n.shadow.camera.near,far:n.shadow.camera.far,size:n.shadow.mapSize.toArray()}:null});});return rows;};
  const half=value=>{const f=new Float32Array([value]),u=new Uint32Array(f.buffer)[0],sg=(u>>>16)&32768,ma=u&8388607,ex=((u>>>23)&255)-112;if(ex<=0)return ex<-10?sg:sg|(((ma|8388608)>>(1-ex))+4096>>13);return ex>=31?sg|31744:sg|(ex<<10)|((ma+4096)>>13);};
  const cube=new T.WebGLCubeRenderTarget(256,{type:T.HalfFloatType}),cc=new T.CubeCamera(0.1,100,cube);cc.position.set(.8,1.4,-1.2);cc.update(R,set._envScene);const env=[];for(let face=0;face<6;face++){R.setRenderTarget(cube,face);const gl=R.getContext(),floats=new Float32Array(256*256*4);gl.readPixels(0,0,256,256,gl.RGBA,gl.FLOAT,floats);if(gl.getError()!==gl.NO_ERROR)throw Error('lobby HDR cube read');const bytes=new Uint8Array(Uint16Array.from(floats,half).buffer),name=`assets/textures/lobby/lobby_env_${face}.rgba16f.bin`;await saveNative(name,b64(bytes));env.push({path:'res://'+name,width:256,height:256,format:'rgba16f'});}R.setRenderTarget(null);
  const data={source:'src/game/lobbySet.js + showcase.js',meshes:records,materials,textures,environment:env,environment_intensity:set.environmentIntensity,uniforms:await uniforms(set.U),lights:{alley:lights(set.root),studio:lights(studio.scene)},alley:ALLEY,spots:set.spots.map(s=>({pos:s.pos.toArray(),yaw:s.yaw})),hub_spot:{pos:set.hubSpot.pos.toArray(),yaw:set.hubSpot.yaw},lanes:Array.from({length:8},(_,i)=>set.lanes(i).map(vector)),camera:set.camera,hub_camera:set.hubCamera,studio_camera:camera(studio.camera),dynamics:{glows:set._glowList.map(x=>({...x,pos:vector(x.pos),color:vector(x.color)})),headlight_glow:set._headlightGlow,bulbs:set._bulbList,drip_sources:set._dripSrc.map(vector),moth_center:set._mothC.toArray()},limitations:['Source geometry, material snippets and decal atlases are retained. Godot PBR/shadows differ from Three.','Floor reflection uses native scaled viewport without source oblique clipping.','Lighting cubemap preserves the original proxy alley; team-dependent source rebake is approximated by native neon light tint.']};
  await saveJSON('data/lobby.json',data);return data;
 });
 console.log(`Lobby source: ${data.meshes.length} meshes, ${data.materials.length} materials, ${data.textures.length} textures`);
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
}
function matrix(code){return code.replace(/mat([234])\(([^()]*)\)/g,(full,size,body)=>{const n=Number(size),a=body.split(',').map(x=>x.trim());if(a.length===n*n)return `mat${n}(${Array.from({length:n},(_,i)=>`vec${n}(${a.slice(i*n,i*n+n).join(',')})`).join(',')})`;if(a.length===1&&/^[-+\d.]+$/.test(body.trim()))return `mat${n}(${Array.from({length:n},(_,i)=>`vec${n}(${Array.from({length:n},(_,j)=>i===j?body.trim():'0.0').join(',')})`).join(',')})`;return full;});}
const float=v=>{const n=Number(Number(v).toFixed(8));return `${n}${Number.isInteger(n)?'.0':''}`;};
const native=code=>matrix(code.replace(/\btexture2D\b/g,'texture').replace(/\btextureCube\b/g,'texture').replace(/\bcameraPosition\b/g,'source_camera').replace(/\bmodelMatrix\b/g,'MODEL_MATRIX').replace(/\bviewMatrix\b/g,'VIEW_MATRIX').replace(/\bmodelViewMatrix\b/g,'MODELVIEW_MATRIX').replace(/\bprojectionMatrix\b/g,'PROJECTION_MATRIX').replace(/\bvColor\b/g,'COLOR').replace(/\bposition\b/g,'VERTEX').replace(/\bnormalMatrix\b/g,'mat3(MODELVIEW_MATRIX)').replace(/gl_FragCoord/g,'FRAGCOORD').replace(/precision highp sampler2DArray;/g,'').replace(/uniform (float|vec[234]) ([\w, ]+);/g,(full,type,names)=>names.split(',').map(n=>`uniform ${type} ${n.trim()};`).join('\n')).replace(/uniform sampler2D (\w+);/g,'uniform sampler2D $1:filter_linear_mipmap;').replace(/uniform sampler2DArray (\w+);/g,(_,n)=>`uniform sampler2DArray ${n}:${n==='tAlbedo'?'source_color,':''}filter_linear_mipmap_anisotropic,repeat_enable;`));
const declarations=code=>{const seen=new Set();return code.replace(/attribute \w+ \w+;\s*/g,'').replace(/(?:varying|uniform)\s+\w+\s+\w+(?:\[\d+\])?(?::[^;]+)?;/g,line=>{const key=line.split(/[\s:\[;]/)[2];if(seen.has(key))return '';seen.add(key);return line;});};
const separate=code=>{const i=code.indexOf('void main');return {pars:code.slice(0,i),body:code.slice(i).replace(/^void main\s*\(\s*\)\s*\{/,'').replace(/}\s*$/,'')};};
for(const m of data.materials){
 const name=`assets/shaders/lobby_${String(m.id).padStart(2,'0')}.gdshader`;
 let result;
 if(m.shader){
  const v=separate(native(m.vertex)),f=separate(native(m.fragment));
  let vertex=v.body.replace(/\buv\b/g,'sourceUv').replace(/\bnormal\b/g,'NORMAL').replace(/\binstanceColor\b/g,'COLOR.rgb').replace(/\baNeon\b/g,'CUSTOM0.xyz').replace(/\baSeed\b/g,'CUSTOM0.x').replace(/\baF\b/g,'CUSTOM0.x');
  vertex=vertex.replace(/MODEL_MATRIX \* instanceMatrix/g,'MODEL_MATRIX').replace(/length\(instanceMatrix\[0\]\.xyz\)/g,'length(MODEL_MATRIX[0].xyz)').replace(/\bgl_Position\b/g,'POSITION');
  if(m.vertex.includes('gl_Position.z = gl_Position.w * 0.99999'))vertex=vertex.replace(/POSITION.z = POSITION.w \* 0.99999/g,'POSITION.z = POSITION.w * 0.000001');
  let pars=declarations(v.pars+'\n'+f.pars);
  result=`// Original source ShaderMaterial ${m.id}.\nshader_type spatial;\nrender_mode unshaded,cull_disabled,fog_disabled${m.additive?',blend_add,depth_draw_never':m.transparent?',blend_mix,depth_draw_never':''};\nvarying vec3 source_camera;\n${pars}\nvoid vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y);${vertex}}\nvoid fragment(){vec4 sourceOutput=vec4(0.0);${f.body.replace(/gl_FragColor/g,'sourceOutput')}ALBEDO=sourceOutput.rgb;${m.transparent&&!m.additive?'ALPHA=sourceOutput.a;':''}}\n`;
 }else{
  const s=m.snippets;let pars=declarations(native((m.vertex_common||'')+'\n'+(s.common||'')));const locals=[];
  pars+='\nuniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);\n';
  pars=pars.replace(/(?:vec[234]|float) g\w+\s*=\s*[^;]+;/g,line=>{locals.push(line);return '';});
  let lighting=native(s.lights_fragment_end||'').replace(/reflectedLight.indirectSpecular/g,'nativeReflection').replace(/geometryViewDir/g,'VIEW');
  const hasHaze=pars.includes('lsHazeAmt');
  const vert=`${native(m.vertex_begin||'').replace(/\btransformed\b/g,'VERTEX').replace(/\baSway\b/g,'CUSTOM0.xy').replace(/\baGlow\b/g,'CUSTOM0.x')}${pars.includes('vLsW')?'vLsW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;':''}${pars.includes('vSurf')?'vSurf=CUSTOM0;vDec=CUSTOM1.xyz;vUvM=vec2(UV.x,1.0-UV.y);vWN=normalize(mat3(MODEL_MATRIX)*NORMAL);':''}${pars.includes('vLit')?'vLit=CUSTOM0.xyz;':''}${pars.includes('vGlow')?'vGlow=CUSTOM0.x;':''}`;
  result=`// Original built-in material colour/normal/weathering hooks ${m.id}.\nshader_type spatial;\nrender_mode cull_disabled,fog_disabled${m.unlit?',unshaded':''};\nuniform vec3 base_color=vec3(${m.color.map(float).join(',')});uniform vec3 emission_color=vec3(${m.emission.map(float).join(',')});uniform float emission_intensity=${float(m.intensity)};uniform sampler2D emissive_map:filter_linear_mipmap;uniform float has_emissive_map=0.0;varying vec3 source_camera;\n${m.defines?.LS_TEXLIB?'#define LS_TEXLIB\n':''}${pars}\nfloat saturate(float x){return clamp(x,0.0,1.0);}\nvoid vertex(){source_camera=CAMERA_POSITION_WORLD;${vert}}\nvoid fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);vec3 normal=NORMAL;vec3 vViewPosition=-VERTEX;float roughnessFactor=${float(m.roughness)};float metalnessFactor=${float(m.metalness)};vec3 totalEmissiveRadiance=emission_color*emission_intensity*mix(vec3(1.0),texture(emissive_map,vec2(UV.x,1.0-UV.y)).rgb,has_emissive_map);vec3 nativeReflection=vec3(0.0);${locals.join('\n')}\n${native(s.color_fragment||'')}\n${native(s.roughnessmap_fragment||'')}\n${native(s.metalnessmap_fragment||'')}\n${native(s.normal_fragment_maps||'')}\n${native(s.emissivemap_fragment||'')}\n${lighting}\nfloat haze=${hasHaze?'lsHazeAmt(vLsW)':'0.0'};ALBEDO=diffuseColor.rgb*(1.0-haze);ROUGHNESS=roughnessFactor;METALLIC=metalnessFactor;NORMAL=normal;EMISSION=(totalEmissiveRadiance+nativeReflection)*(1.0-haze)${hasHaze?'+lsHazeCol(vLsW)*haze':''};${m.unlit?'':'float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix);'}}\n`;
 }
 await write(name,result);
}
data.studio_moods=studioMoods;
await write('data/lobby.json',JSON.stringify(data));
