/** Supplementary source environment export. No Godot process; original builders are authoritative. */
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),out=path.join(root,'splatink');
const source=await fs.readFile(path.join(root,'src/world/environment.js'),'utf8');
const shaders={};
for(const match of source.matchAll(/const (\w+) = \/\* glsl \*\/`([\s\S]*?)`;/g)){
  const context={WATER_Y:-1.6,MAX_RECTS:32,MAX_WET:12,...shaders};
  shaders[match[1]]=Function(...Object.keys(context),'return `'+match[2]+'`;')(...Object.values(context));
}
async function write(file,data){const bytes=Buffer.from(data),old=await fs.readFile(file).catch(()=>null);if(!old?.equals(bytes)){await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,bytes);}}
function matrixSyntax(code){return code.replace(/mat([234])\(([^()]*)\)/g,(whole,size,body)=>{const n=Number(size),args=body.split(',').map(x=>x.trim());if(args.length===n*n)return `mat${n}(${Array.from({length:n},(_,i)=>`vec${n}(${args.slice(i*n,i*n+n).join(',')})`).join(',')})`;if(args.length===1&&/^[-+\d.]+$/.test(body.trim()))return `mat${n}(${Array.from({length:n},(_,i)=>`vec${n}(${Array.from({length:n},(_,j)=>i===j?body.trim():'0.0').join(',')})`).join(',')})`;return whole;});}
function native(code){return matrixSyntax(code.replace(/#include <[^>]+>\s*/g,'').replace(/\btexture2D\b/g,'texture').replace(/\bcameraPosition\b/g,'source_camera').replace(/\bvColor\.rgb\b/g,'COLOR.rgb').replace(/uniform sampler2D (\w+);/g,(_,name)=>`uniform sampler2D ${name} : ${name==='uWaveTex'?'filter_linear_mipmap_anisotropic, repeat_enable':name==='uFoamTex'||name==='uReflTex'?'filter_linear, repeat_disable':'filter_linear, repeat_enable'};`).replace(/uniform samplerCube (\w+);/g,'uniform samplerCube $1 : filter_linear_mipmap;'));}
function separate(code){const mark=code.indexOf('void main()');return {declarations:code.slice(0,mark),body:code.slice(mark).replace(/^void main\(\)\s*\{/,'').replace(/}\s*$/,'')};}
function preprocess(code,defines){const stack=[];let active=true;const result=[];for(const line of code.split('\n')){let m;if((m=line.match(/^\s*#(ifdef|ifndef)\s+(\w+)/))){const test=defines.has(m[2])===(m[1]==='ifdef');stack.push({parent:active,test});active=active&&test;}else if(/^\s*#else/.test(line)){const state=stack.at(-1);active=state.parent&&!state.test;}else if(/^\s*#endif/.test(line)){active=stack.pop().parent;}else if(active)result.push(line);}return result.join('\n');}
const common=native(shaders.GLSL_SKY_COMMON+shaders.GLSL_NOISE);
for(const marina of [false,true]){
  const fragment=separate(native(preprocess(shaders.SEA_FRAG,new Set(marina?['MARINA']:[]))));
  // Godot can't expose the Three shadow sampler. Retain the original analytic deck shadow fallback.
  fragment.body=fragment.body.replace(/getShadowMask\(\)/g,'source_shadow(P)');
  fragment.body=fragment.body.replace(/gl_FragColor\s*=\s*vec4\(col,\s*1\.0\);/g,'ALBEDO=max(col,vec3(0.0));');
  const code=`// Original INKWAVE sea equations, geometry and lookup fields.\nshader_type spatial;\nrender_mode unshaded,cull_disabled,fog_disabled;\n${marina?'#define MARINA\n':''}varying vec3 source_camera;\n${fragment.declarations}\n${native(shaders.GLSL_SWELL)}\nfloat source_shadow(vec3 P){vec2 p=P.xz+uSunDir.xz*((-0.6-P.y)/max(uSunDir.y,0.06));return smoothstep(-0.2,0.45,sdDeck(p));}\nvoid vertex(){source_camera=CAMERA_POSITION_WORLD;vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;float dd=sdDeck(wp.xz);\n${marina?'dd=min(dd,sdWet(wp.xz));':''}\nfloat amp=swellAmp(dd);${marina?'amp*=mix(0.45,1.0,basinK(wp.xz));':''}vec2 g;float h=swell(wp.xz,uTime,g);VERTEX.y+=h*amp;wp.y+=h*amp;vWorld=wp;vSwellGrad=g*amp;vDeckD=dd;}\nvoid fragment(){${fragment.body}}\n`;
  await write(path.join(out,'assets/shaders',`environment_sea_${marina?'marina':'open'}.gdshader`),code);
}
const sky=separate(native(shaders.SKY_FRAG));
sky.declarations=sky.declarations.replace('varying vec3 vDir;','');
sky.body=sky.body.replace(/gl_FragColor\s*=\s*vec4\(col,\s*1\.0\);/,'COLOR=max(col,vec3(0.0));').replace(/gl_FragColor\.rgb/g,'COLOR').replace(/gl_FragCoord\.xy/g,'SCREEN_UV*vec2(1920.0,1080.0)');
sky.body=sky.body.replace('#if defined(SKY_SHAFTS) && !defined(ENV_PASS)','if(uShafts>0.5&&!AT_CUBEMAP_PASS){').replace(/#ifndef ENV_PASS/g,'if(!AT_CUBEMAP_PASS){').replace(/#else/g,'}else{').replace(/#endif/g,'}');
await write(path.join(out,'assets/shaders/environment_sky.gdshader'),`// Source ENV_PASS radiance is baked once; the separate visible dome stays animated.\nshader_type sky;\nuniform samplerCube source_radiance:filter_linear_mipmap;uniform bool source_radiance_enabled=false;\nuniform vec3 source_camera;uniform float uShafts=0.0;\n${sky.declarations}\nvoid sky(){if(AT_CUBEMAP_PASS&&source_radiance_enabled){COLOR=textureLod(source_radiance,EYEDIR,0.0).rgb;}else{vec3 vDir=EYEDIR;${sky.body}}}\n`);
const visibleSky=sky.body.replace(/AT_CUBEMAP_PASS/g,'false').replace(/\bCOLOR\b/g,'ALBEDO').replace(/SCREEN_UV\*vec2\(1920\.0,1080\.0\)/g,'FRAGCOORD.xy');
await write(path.join(out,'assets/shaders/environment_sky_dome.gdshader'),`// Source visible sky, independent of cached t=0 ENV_PASS radiance.\nshader_type spatial;\nrender_mode unshaded,cull_front,fog_disabled,depth_draw_never;\nuniform vec3 source_camera;uniform float uShafts=0.0;varying vec3 vDir;\n${sky.declarations}\nvoid vertex(){vDir=VERTEX;vec4 view=VIEW_MATRIX*vec4(CAMERA_POSITION_WORLD+VERTEX,1.0);POSITION=PROJECTION_MATRIX*view;POSITION.z=POSITION.w*0.000001;}\nvoid fragment(){${visibleSky}}\n`);
for(const defs of [[],['HZ_TERRAIN','HZ_SHORE'],['HZ_CITY'],['HZ_WATERLINE'],['HZ_GULL'],['HZ_SHORE']]){
  const key=defs.length?defs.map(x=>x.slice(3).toLowerCase()).join('_'):'scenery';
  const decl=native(shaders.HZ_FRAG_DECL).replace(/(?:vec3 hzLitCol = vec3\(0\.0\);|float hzWin = 0\.0;|float hzLit = 0\.0;|vec3 hzEmit = vec3\(0\.0\);)/g,'');
  const body=native(shaders.HZ_FRAG_COLOR+shaders.HZ_FRAG_ROUGH+shaders.HZ_FRAG_EMISSIVE);
  const flap=native(shaders.HZ_VERT_BEGIN_GULL).replace(/transformed/g,'VERTEX').replace(/aPhase/g,'INSTANCE_CUSTOM.x');
  await write(path.join(out,'assets/shaders',`environment_${key}.gdshader`),`// Source scenery material hooks; native Godot PBR supplies direct lighting.\nshader_type spatial;\nrender_mode cull_disabled,fog_disabled;\n${defs.map(d=>'#define '+d).join('\n')}\nuniform vec3 base_color=vec3(1.0);uniform float base_roughness=0.8;uniform float base_metallic=0.0;\nvarying vec3 source_camera;\n${decl}\nvoid vertex(){source_camera=CAMERA_POSITION_WORLD;${flap}vHzWorld=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vHzNormal=normalize(mat3(MODEL_MATRIX)*NORMAL);vHzSeed=fract(sin(dot(MODEL_MATRIX[3].xz,vec2(12.9898,78.233)))*43758.5453);vGlow=CUSTOM0.x;\n#ifdef HZ_CITY\nvBld=CUSTOM1.xyz;\n#endif\n}\nvoid fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);float roughnessFactor=base_roughness;vec3 totalEmissiveRadiance=vec3(0.0);float hzWin=0.0;float hzLit=0.0;vec3 hzEmit=vec3(0.0);\n#ifdef HZ_CITY\nvec3 hzLitCol=vec3(0.0);\n#endif\n${body}\nvec3 dv=vHzWorld-source_camera;float dist=length(dv);vec3 dir=dv/max(dist,0.001);float hf=exp(-max(vHzWorld.y,0.0)/uHaze.z);float f=min(1.0-exp(-dist*uHaze.x*mix(0.45,1.0,hf)),uHaze.y);\n#ifdef HZ_CITY\nvec3 wn2=normalize(vHzNormal);vec3 refl=min(skyGradient(normalize(reflect(dir,wn2)+vec3(0.0,0.02,0.0))),vec3(1.1));float fres=0.05+0.95*pow(1.0-clamp(dot(-dir,wn2),0.0,1.0),5.0);totalEmissiveRadiance+=refl*mix(0.92,0.55,uNight)*hzWin*clamp(0.18+fres*0.75,0.0,0.85)*(1.0-uNight*0.75);diffuseColor.rgb*=1.0-0.38*uNight;\n#endif\nALBEDO=max(diffuseColor.rgb,vec3(0.0))*(1.0-f);ROUGHNESS=roughnessFactor;METALLIC=base_metallic;EMISSION=hazeColor(dir)*f+(totalEmissiveRadiance+hzEmit*exp(-dist*uHaze.x*0.35))*(1.0-f);}\n`);
}
const strip=separate(native(shaders.STRIP_FRAG));
strip.body=strip.body.replace(/getShadowMask\(\)/g,'1.0').replace(/gl_FragColor\s*=\s*vec4\(add, mul\);/,'ALBEDO=vec3(0.0);EMISSION=add;ALPHA=clamp(1.0-mul,0.0,1.0);');
await write(path.join(out,'assets/shaders/environment_marina_strip.gdshader'),`// Original caustic filaments/wet band, adapted to Godot premultiplied blending.\nshader_type spatial;\nrender_mode unshaded,cull_disabled,fog_disabled,blend_premul_alpha,depth_draw_never;\n${strip.declarations}\nvoid vertex(){vP=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=normalize(mat3(MODEL_MATRIX)*NORMAL);vInfo=CUSTOM0;float h=max(vP.y+1.6,0.0);vec2 k=uSunDir.xz/max(uSunDir.y,0.08);vPw=vec3(vP.x+k.x*h,-1.6,vP.z+k.y*h);}\nvoid fragment(){${strip.body}PREMUL_ALPHA_FACTOR=1.0;}\n`);
await write(path.join(out,'assets/shaders/environment_beam.gdshader'),`shader_type spatial;\nrender_mode unshaded,cull_disabled,fog_disabled,blend_add,depth_draw_never;\nuniform float uNight=0.0;uniform vec3 uCol=vec3(1.0,0.76,0.39);varying float vA;varying vec3 vN;varying vec3 vV;\nvoid vertex(){vA=clamp(VERTEX.x/150.0,0.0,1.0);vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=normalize(mat3(MODEL_MATRIX)*NORMAL);vV=normalize(CAMERA_POSITION_WORLD-wp);}\nvoid fragment(){float e=pow(clamp(abs(dot(normalize(vN),normalize(vV))),0.0,1.0),2.0);float a=e*pow(max(1.0-vA,0.0),1.6)*smoothstep(0.0,0.03,vA)*0.5*uNight;ALBEDO=uCol*a;ALPHA=1.0;}\n`);
await write(path.join(out,'assets/shaders/environment_prop_cloth.gdshader'),`// Original PropKit cloth waves: flex / wave source attributes and source atlas.\nshader_type spatial;render_mode cull_disabled;\nuniform float uTime=0.0;uniform sampler2D atlas:source_color,filter_linear_mipmap;\nvoid vertex(){vec3 ipos=MODEL_MATRIX[3].xyz;float flex=CUSTOM0.x;vec3 wave=CUSTOM1.xyz;float cph=ipos.x*0.83+ipos.z*0.61+ipos.y*0.37;float ca=uTime*wave.x+cph+VERTEX.x*wave.y;float cb=uTime*wave.x*2.3+cph*1.7+VERTEX.y*3.0;float cw=sin(ca)+0.35*sin(cb);NORMAL=normalize(NORMAL+vec3(-flex*wave.z*wave.y*cos(ca),-flex*wave.z*1.05*cos(cb),0.0));VERTEX.z+=flex*wave.z*cw;}\nvoid fragment(){vec4 tx=texture(atlas,UV);ALBEDO=mix(COLOR.rgb,tx.rgb,tx.a);ROUGHNESS=0.82;}\n`);
// Neutral output curve kept as a reference include for the root's HDR post pipeline.
const threeModule=await fs.readFile(path.join(root,'vendor/three/build/three.module.js'),'utf8');
const tonemap=JSON.parse(threeModule.match(/var tonemapping_pars_fragment = ("(?:[^"\\]|\\.)*");/)[1]);
const neutral=tonemap.match(/vec3 NeutralToneMapping\( vec3 color \) \{([\s\S]*?)\n\}/)?.[1];
if(neutral)await write(path.join(out,'assets/shaders/environment_neutral.gdshaderinc'),`// Three original NeutralToneMapping, applied after source linear HDR grade.\nvec3 source_neutral(vec3 color){${neutral.replace(/toneMappingExposure/g,'1.0')}\n}\n`);

for(const id of ['tidewater','kelpline','halyard','cargo']){const file=path.join(out,'data',id+'_environment_details.json');const old=await fs.readFile(file,'utf8').catch(()=>null);if(old){const value=JSON.parse(old);let changed=false;for(const mesh of value.meshes)if(mesh.attributes.aPhase&&!mesh.attributes.aPhase.instanced){mesh.attributes.aPhase.instanced=true;mesh.attributes.aPhase.meshPerAttribute=1;changed=true;}for(const mesh of value.meshes)if(mesh.name==='WaterlineStrips'&&mesh.shader!=='marina_strip'){mesh.shader='marina_strip';changed=true;}if(changed)await write(file,JSON.stringify(value));}}
if(process.argv.includes('--shaders-only')){console.log('Environment shaders generated');process.exit(0);}
const mime={'.js':'text/javascript','.mjs':'text/javascript','.woff2':'font/woff2','.json':'application/json','.png':'image/png'};
const server=http.createServer(async(req,res)=>{try{const u=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(u==='/environment-details'){res.setHeader('Content-Type','text/html');res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}const p=path.resolve(root,'.'+u);if(!p.startsWith(root+path.sep))throw Error('path');res.setHeader('Content-Type',mime[path.extname(p)]||'application/octet-stream');res.end(await fs.readFile(p));}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(8492,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
const page=await browser.newPage({viewport:{width:512,height:512}});
page.on('pageerror',error=>console.error(error.message));
await page.exposeFunction('saveNative',async(name,b64)=>{const dest=path.resolve(out,name);if(!dest.startsWith(out+path.sep))throw Error(name);await write(dest,Buffer.from(b64,'base64'));});
await page.goto('http://127.0.0.1:8492/environment-details');
try{
 const summary=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js'),{Environment}=await import('/src/world/environment.js'),{Level}=await import('/src/world/level.js'),{MAP_LAYOUTS}=await import('/src/world/maps.js'),{G}=await import('/src/core/ctx.js'),{PropKit}=await import('/src/world/props.js'),{dressingFor}=await import('/src/world/dressing.js');
  const b64=data=>{let s='';for(let i=0;i<data.length;i+=32768)s+=String.fromCharCode(...data.subarray(i,i+32768));return btoa(s);};
  const json=value=>b64(new TextEncoder().encode(JSON.stringify(value)));
  const vector=value=>value?.toArray?value.toArray():value;
  const uniforms=U=>Object.fromEntries(Object.entries(U).flatMap(([key,u])=>{const v=u.value;if(v?.isTexture||v===null)return[];const kind=typeof v==='number'?'float':v.isColor||v.isVector3?'vec3':v.isVector2?'vec2':v.isVector4?'vec4':v.isMatrix4?'mat4':Array.isArray(v)?'array_'+(v[0]?.isVector2?'vec2':'vec4'):'other';return kind==='other'?[]:[[key,{kind,value:Array.isArray(v)?v.map(vector):vector(v)}]];}));
  const floatHalf=(value)=>{const f=new Float32Array([value]),u=new Uint32Array(f.buffer)[0],sign=(u>>>16)&32768,mantissa=u&8388607,exponent=((u>>>23)&255)-127+15;if(exponent<=0){if(exponent<-10)return sign;return sign|(((mantissa|8388608)>>(1-exponent))+4096>>13);}if(exponent>=31)return sign|31744;return sign|(exponent<<10)|((mantissa+4096)>>13);};
  const output=[];
  for(const [id,layout]of Object.entries(MAP_LAYOUTS)){
   const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});renderer.setSize(512,512);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.NoToneMapping;
   const scene=new T.Scene(),kit=new PropKit(scene,{quality:'high'}),colliders=[];
   for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
   G.level=new Level(layout,colliders);G.scene=scene;G.settings={quality:'high'};G.teamColors=[new T.Color('#ff3f9e'),new T.Color('#18d48c')];
   const footprint=G.level.blocks.filter(b=>(b.aligned||b.axes[1].y>.9999)&&b.aabbMax.y<.01&&b.aabbMax.y>-2.5&&b.aabbMin.y<-1).map(b=>b.aligned?{minX:b.aabbMin.x,maxX:b.aabbMax.x,minZ:b.aabbMin.z,maxZ:b.aabbMax.z}:{cx:b.center.x,cz:b.center.z,hx:b.half.x,hz:b.half.z,ax:b.axes[0].x,az:b.axes[0].z});
   const env=new Environment(renderer,scene,{bounds:layout.bounds,theme:id==='halyard'?'golden':'day',footprint});
   let chunks=[],offset=0;
   const chunk=(data,type='f32')=>{const a=type==='u32'?new Uint32Array(data):new Float32Array(data),bytes=new Uint8Array(a.buffer),r={offset,length:a.length,type};chunks.push(bytes);offset+=bytes.length;return r;};
   const records=[];scene.updateMatrixWorld(true);
   const collect=(n,scope)=>{if(!n.isMesh||n===env.sky||!n.geometry.attributes.position)return;const attributes=Object.fromEntries(Object.entries(n.geometry.attributes).map(([key,a])=>[key,{...chunk(a.array),size:a.itemSize,instanced:!!a.isInstancedBufferAttribute,meshPerAttribute:a.meshPerAttribute||1}]));const m=Array.isArray(n.material)?n.material[0]:n.material;const defs=Object.keys(m.defines||{}).filter(x=>x.startsWith('HZ_'));
    const shader=n===env.sea?'sea':n===env.lhBeam?'beam':n.name==='WaterlineStrips'?'marina_strip':scope==='props'?(n.userData.cloth?'prop_cloth':'native'):defs.length?defs.map(x=>x.slice(3).toLowerCase()).join('_'):'scenery';
    const r={name:n.name,scope,attributes,index:n.geometry.index?chunk(n.geometry.index.array,'u32'):null,transform:n.matrixWorld.toArray(),visible:n.visible,shader,cast_shadow:!!n.castShadow,material:{color:m.color?.toArray()||[1,1,1],roughness:m.roughness??.7,metalness:m.metalness??0,unlit:!!m.isMeshBasicMaterial,opacity:m.opacity??1,transparent:!!m.transparent,double_side:m.side===T.DoubleSide,emission:m.emissive?.toArray()}};
    Object.assign(r.material,{alpha_test:m.alphaTest??0,clearcoat:m.clearcoat??0,clearcoat_roughness:m.clearcoatRoughness??.1,env_map_intensity:m.envMapIntensity??1,specular_intensity:m.specularIntensity??1,emissive_intensity:m.emissiveIntensity??1});
    if(n.isInstancedMesh){r.instances=[];const mi=new T.Matrix4(),ci=new T.Color();for(let i=0;i<n.count;i++){n.getMatrixAt(i,mi);if(n.instanceColor)n.getColorAt(i,ci);r.instances.push({transform:mi.toArray(),color:n.instanceColor?ci.toArray():[1,1,1]});}}
    if(n.userData.axis)r.motion={kind:'spin',axis:n.userData.axis,recs:n.userData.recs.map(x=>({speed:x.speed,phase:x.phase,base:x.base.toArray()}))};
    if(n.userData.blink)r.motion={kind:'blink',recs:n.userData.recs.map(x=>({rate:x.rate,phase:x.phase,lo:x.lo,hi:x.hi,color:x.color.toArray()}))};
    if(n.userData.cloth)r.team_tints=n.userData.recs.map(x=>({team:x.team??-1,tint:x.tint||0,color:x.color.toArray()}));
    records.push(r);
   };
   env.root.traverse(n=>collect(n,'environment'));
   kit.group.traverse(n=>{if(n.isMesh&&(n.userData.cloth||n.userData.axis||n.userData.blink))collect(n,'props');});
   const bytes=new Uint8Array(offset);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}
   await saveNative(`assets/world/${id}_environment_details.bin`,b64(bytes));
   const textures={};
   for(const [key,format]of [['uWaveTex','rgba8'],['uFoamTex','l8']]){const image=env.U[key].value.image,name=`assets/textures/environment/${id}_${key}.${format}.bin`;await saveNative(name,b64(new Uint8Array(image.data.buffer,image.data.byteOffset,image.data.byteLength)));textures[key]={path:'res://'+name,width:image.width,height:image.height,format};}
   const readHDR=async(rt,filename,face=0)=>{const gl=renderer.getContext(),data=new Float32Array(rt.width*rt.height*4);renderer.setRenderTarget(rt,face);gl.readPixels(0,0,rt.width,rt.height,gl.RGBA,gl.FLOAT,data);const error=gl.getError();if(error!==gl.NO_ERROR)throw Error('HDR read '+error);const half=Uint16Array.from(data,floatHalf);await saveNative(filename,b64(new Uint8Array(half.buffer)));return {path:'res://'+filename,width:rt.width,height:rt.height,format:'rgba16f'};};
   const themes={};
   for(const time of ['day','dusk']){
    env.setTheme(time==='dusk'?'sunset':id==='halyard'?'golden':'day');
    const cloud=await readHDR(env._cloudRT,`assets/textures/environment/${id}_${time}_cloud.rgba16f.bin`);
    const far=[];if(env._farRT)for(let face=0;face<6;face++)far.push(await readHDR(env._farRT,`assets/textures/environment/${id}_${time}_far_${face}.rgba16f.bin`,face));
    themes[time]={uniforms:uniforms(env.U),cloud,far};
   }
   renderer.setRenderTarget(null);
   const data={id,bounds:layout.bounds,marina:env._marina,footprint:env.footprint,marina_sets:env._marinaData,textures,themes,meshes:records,motion:{sails:env.sailboats,buoys:env.buoys,gulls:env.gulls,moored:env.moored.map(x=>({name:x.mesh.name,spec:x.spec,phase:x.phase,roll:x.roll})),ferris:env._ferrisPose},source:'src/world/environment.js + src/world/props.js',limitations:['Godot PBR differs from Three physical lighting; per-object source haze is preserved in native fragment mixing.','Water uses original analytic deck shadow fallback; Three shadow-map and oblique reflection clipping cannot be copied through Godot public shader API.','Waterline blend is adapted to native premultiplied alpha. Planar camera reflection is quality-scaled; near-plane oblique clipping is not identical.']};
   await saveNative(`data/${id}_environment_details.json`,json(data));
   output.push({id,meshes:records.length,bytes:offset,foam:[textures.uFoamTex.width,textures.uFoamTex.height],marina:env._marina});
   env.dispose();kit.dispose();renderer.dispose();
  }
  return output;
 });
 console.log(JSON.stringify(summary,null,2));
 await write(path.join(out,'data/environment_details_manifest.json'),JSON.stringify({source:'INKWAVE original environment',maps:summary},null,2));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
