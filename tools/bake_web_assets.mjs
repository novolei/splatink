// Runs only our local web source to bake original GPU textures and Web Audio into native assets.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {deflateSync} from 'node:zlib';
const req=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=req('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),out=path.join(root,'splatink');
// Canvas serialization premultiplies RGB by alpha. Texlib alpha is an independent
// tint mask, so even alpha-zero RGB must survive unchanged.
const crcTable=Array.from({length:256},(_,n)=>{for(let k=0;k<8;k++)n=(n&1)?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
const crc32=b=>{let c=0xffffffff;for(const x of b)c=crcTable[(c^x)&255]^(c>>>8);return (c^0xffffffff)>>>0;};
function rawPng(rgba,width,height){
 const chunk=(type,data)=>{const tag=Buffer.from(type),length=Buffer.alloc(4),crc=Buffer.alloc(4);length.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([tag,data])));return Buffer.concat([length,tag,data,crc]);};
 const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width,0);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=6;
 const rows=Buffer.alloc(height*(width*4+1));for(let y=0;y<height;y++)rgba.copy(rows,y*(width*4+1)+1,y*width*4,(y+1)*width*4);
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);
}
const mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.png':'image/png','.webp':'image/webp','.woff2':'font/woff2'};
const server=http.createServer(async(r,s)=>{try{const pathname=decodeURIComponent(new URL(r.url,'http://localhost').pathname);if(pathname==='/native-bake'){s.setHeader('Content-Type','text/html');s.end(`<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>`);return;}const p=path.resolve(root,'.'+pathname);if(!p.startsWith(root+path.sep))throw Error('path');const b=await fs.readFile(p);s.setHeader('Content-Type',mime[path.extname(p)]||'application/octet-stream');s.end(b);}catch(e){s.statusCode=404;s.end('missing');}});
const port=process.env.SPLATINK_BAKE_PORT?Number(process.env.SPLATINK_BAKE_PORT):8491;
await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
const page=await browser.newPage({viewport:{width:1280,height:720}});page.on('pageerror',e=>console.error(e));
await page.exposeFunction('saveNative',async(name,b64)=>{const p=path.resolve(out,name);if(!p.startsWith(out+path.sep))throw Error(name);await fs.mkdir(path.dirname(p),{recursive:true});await fs.writeFile(p,Buffer.from(b64,'base64'));});
await page.exposeFunction('saveRawTexture',async(name,b64,width,height)=>{const p=path.resolve(out,name);if(!p.startsWith(out+path.sep))throw Error(name);await fs.mkdir(path.dirname(p),{recursive:true});await fs.writeFile(p,rawPng(Buffer.from(b64,'base64'),width,height));let config=await fs.readFile(p+'.import','utf8').catch(()=>null);if(config){config=config.replace('process/fix_alpha_border=true','process/fix_alpha_border=false');await fs.writeFile(p+'.import',config);}});
await page.goto(`http://127.0.0.1:${port}/native-bake`);
const modes=process.argv.slice(2);const run=(x)=>!modes.length||modes.includes(x);
try {
if(run('textures')){
 const result=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js'),{createTextureLibrary,TEXLIB_GLSL}=await import('/src/world/texlib.js'),{createLevelMaterial}=await import('/src/world/levelMaterial.js');
  const R=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});R.setSize(512,512);const lib=await createTextureLibrary(R,{size:512});
  const material=createLevelMaterial(new T.Texture(),2048,null,{texlib:lib}),u=material.userData.uniforms;
  const b64=(u8)=>{let s='';for(let i=0;i<u8.length;i+=32768)s+=String.fromCharCode(...u8.subarray(i,i+32768));return btoa(s);};
  const json={names:lib.names,meta:lib.meta,slots:u.uTL.value.map(v=>v.toArray()),tints:u.uTLt.value.map(v=>v.toArray()),stairs:u.uTLs.value.map(v=>v.toArray())};
  await saveNative('data/texture_library.json',b64(new TextEncoder().encode(JSON.stringify(json))));
  const nativeGLSL=TEXLIB_GLSL.replace(/mat2\(([^()]+)\)/g,(all,body)=>{const a=body.split(',').map(x=>x.trim());if(a.length===4)return `mat2(vec2(${a[0]}, ${a[1]}), vec2(${a[2]}, ${a[3]}))`;if(a.length===1)return `mat2(vec2(${a[0]}, 0.0), vec2(0.0, ${a[0]}))`;return all;})
   .replace(/uint texlib_pcg\([^\n]+/,original=>{
    const portable=original.replace('v * 747796405u','ink_mul32(v,747796405u)').replace('((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u','ink_mul32((s >> ((s >> 28u) + 4u)) ^ s,277803737u)');
    return '#ifdef INK_PORTABLE_UINT\n#include "res://assets/shaders/portable_uint.gdshaderinc"\n'+portable+'\n#else\n'+original+'\n#endif';
   });
  await saveNative('assets/shaders/source_texlib.gdshaderinc',b64(new TextEncoder().encode(nativeGLSL)));
  const gl=R.getContext(),fb=gl.createFramebuffer();
  for(const [kind,tex]of [['albedo',lib.albedo],['normal',lib.normal],['orm',lib.orm]]){
   const handle=R.properties.get(tex).__webglTexture;
   for(let layer=0;layer<lib.names.length;layer++){
    gl.bindFramebuffer(gl.FRAMEBUFFER,fb);gl.framebufferTextureLayer(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,handle,0,layer);gl.readBuffer(gl.COLOR_ATTACHMENT0);
    const data=new Uint8Array(lib.size*lib.size*4);gl.readPixels(0,0,lib.size,lib.size,gl.RGBA,gl.UNSIGNED_BYTE,data);
    // Keep GPU-origin row order. Original sampler UVs refer to these rows.
    await saveRawTexture(`assets/textures/library/${kind}_${String(layer).padStart(2,'0')}.png`,b64(data),lib.size,lib.size);
   }
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.deleteFramebuffer(fb);R.dispose();return {layers:lib.names.length,size:lib.size};
 });console.log('textures '+JSON.stringify(result));
}
if(run('environment')){
 const result=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js'),{Environment}=await import('/src/world/environment.js'),{Level}=await import('/src/world/level.js'),{MAP_LAYOUTS}=await import('/src/world/maps.js'),{G}=await import('/src/core/ctx.js');
  const b64=u=>{let s='';for(let i=0;i<u.length;i+=32768)s+=String.fromCharCode(...u.subarray(i,i+32768));return btoa(s);};
  const output=[];for(const [id,layout]of Object.entries(MAP_LAYOUTS)){
   const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false,preserveDrawingBuffer:true});renderer.setSize(512,512);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.NoToneMapping;
   G.level=new Level(layout);G.settings={quality:'high'};G.teamColors=[new T.Color('#ff3f9e'),new T.Color('#18d48c')];G.quality={particles:1};const scene=new T.Scene();G.scene=scene;
   const env=new Environment(renderer,scene,{bounds:layout.bounds,theme:id==='halyard'?'golden':'day'});let chunks=[],offset=0;
   const chunk=(a,type='f32')=>{const x=type==='u32'?new Uint32Array(a):new Float32Array(a);const u=new Uint8Array(x.buffer),r={offset,length:x.length,type};chunks.push(u);offset+=u.length;return r;};
   const meshes=[];scene.updateMatrixWorld(true);env.root.traverse(n=>{if(!n.isMesh||n===env.sky||n===env.sea||/sea|waterline|horizon/i.test(n.name))return;const a={};for(const[k,v]of Object.entries(n.geometry.attributes))a[k]={...chunk(v.array),size:v.itemSize};let m=n.material;if(Array.isArray(m))m=m[0];const rec={name:n.name,attributes:a,index:n.geometry.index?chunk(n.geometry.index.array,'u32'):null,transform:n.matrixWorld.toArray(),material:{type:m.type,color:m.color?.toArray()||[1,1,1],roughness:m.roughness??.6,metalness:m.metalness??0,transparent:!!m.transparent,opacity:m.opacity??1,alpha_test:m.alphaTest||0,unlit:!!m.isMeshBasicMaterial,double_side:m.side===T.DoubleSide,emission:m.emissive?.toArray()},cast_shadow:!!n.castShadow};if(n.isInstancedMesh){rec.instances=[];const mi=new T.Matrix4(),ci=new T.Color();for(let i=0;i<n.count;i++){n.getMatrixAt(i,mi);if(n.instanceColor)n.getColorAt(i,ci);rec.instances.push({transform:mi.toArray(),color:n.instanceColor?ci.toArray():[1,1,1]});}}meshes.push(rec);});
   const bin=new Uint8Array(offset);let at=0;for(const c of chunks){bin.set(c,at);at+=c.length;}
   await saveNative(`assets/world/${id}_env.bin`,b64(bin));await saveNative(`data/${id}_env.json`,b64(new TextEncoder().encode(JSON.stringify({meshes,themes:Environment.THEMES}))));
   // Original sky/cloud shader, sampled as a cube for native sky + IBL.
   scene.children.forEach(n=>n.visible=false);env.root.visible=true;env.root.children.forEach(n=>n.visible=n===env.sky);env.sky.visible=true;scene.fog=null;
   const cam=new T.PerspectiveCamera(90,1,.1,6500);cam.position.set(0,0,0);const dirs=[[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
   for(const time of ['day','dusk']){env.setTheme(time==='dusk'?'sunset':id==='halyard'?'golden':'day');for(let i=0;i<6;i++){cam.up.set(0,-1,0);if(i===2)cam.up.set(0,0,1);if(i===3)cam.up.set(0,0,-1);cam.lookAt(new T.Vector3(...dirs[i]));renderer.render(scene,cam);await saveNative(`assets/textures/sky/${id}_${time}_${i}.png`,renderer.domElement.toDataURL('image/png').split(',')[1]);}}
   output.push({id,meshes:meshes.length,bytes:offset});env.dispose?.();renderer.dispose();
  }return output;
 });console.log('environment '+JSON.stringify(result));
}
if(run('audio')){
 const names=await page.evaluate(async()=>{window.A=await import('/src/audio/audio.js');window.M=await import('/src/audio/music.js');return A.SFX_NAMES;});
 for(const name of names){
  const meta=await page.evaluate(async(name)=>{
   const ctx=new OfflineAudioContext(2,48000*(A.SFX[name].loop?2.2:4),48000),e=new A.AudioEngine({context:ctx,seed:1234,music:false});e.init();e.setVolumes({master:1,music:1,sfx:1});e.master.gain.value=e.sfxBus.gain.value=1;
   if(A.SFX[name].build)e.play(name,{at:0});else e.loop(name,{volume:1});
   const b=await ctx.startRendering();let end=b.length,start=0;const ch=[b.getChannelData(0),b.getChannelData(1)];
   if(!A.SFX[name].loop){while(end>2400&&Math.max(Math.abs(ch[0][end-1]),Math.abs(ch[1][end-1]))<.00015)end--;end=Math.min(b.length,end+2400);}else{start=24000;end=b.length-9600;}
   const v=new DataView(new ArrayBuffer(44+(end-start)*4));const str=(o,s)=>{for(let i=0;i<s.length;i++)v.setUint8(o+i,s.charCodeAt(i));};str(0,'RIFF');v.setUint32(4,v.byteLength-8,true);str(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,2,true);v.setUint32(24,48000,true);v.setUint32(28,192000,true);v.setUint16(32,4,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,v.byteLength-44,true);
   let peak=0;for(let i=start;i<end;i++)for(let c=0;c<2;c++){const x=ch[c][i];peak=Math.max(peak,Math.abs(x));v.setInt16(44+(i-start)*4+c*2,Math.max(-1,Math.min(1,x))*32767,true);}
   let s='',u=new Uint8Array(v.buffer);for(let i=0;i<u.length;i+=32768)s+=String.fromCharCode(...u.subarray(i,i+32768));await saveNative('assets/audio/sfx/'+name+'.wav',btoa(s));return {name,seconds:(end-start)/48000,peak,loop:!!A.SFX[name].loop};
  },name);console.log('sfx '+JSON.stringify(meta));
 }
 const tracks=await page.evaluate(()=>Object.keys(M.SONGS));const musicMetadata={sample_rate:48000,tracks:{}};
 for(const id of tracks){const result=await page.evaluate(async(id)=>{
  const song=M.getSong(id),bar=240/song.bpm,bars=song.bars.length,secs=bar*bars;
  const ctx=new OfflineAudioContext(2,Math.floor(48000*secs),48000),e=new A.AudioEngine({context:ctx,seed:99,music:false});e.init();e.master.gain.value=e.musicBus.gain.value=1;
  const m=new M.MusicEngine();m._init(ctx,e.musicBus,{offline:true});m.play(id,{fade:0,seed:7});for(let t=0;t<secs;t+=.05)m.advance(t);const b=await ctx.startRendering();
  const v=new DataView(new ArrayBuffer(44+b.length*4)),str=(o,s)=>{for(let i=0;i<s.length;i++)v.setUint8(o+i,s.charCodeAt(i));};str(0,'RIFF');v.setUint32(4,v.byteLength-8,true);str(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,2,true);v.setUint32(24,48000,true);v.setUint32(28,192000,true);v.setUint16(32,4,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,v.byteLength-44,true);
  const L=b.getChannelData(0),R=b.getChannelData(1);for(let i=0;i<b.length;i++){v.setInt16(44+i*4,Math.max(-1,Math.min(1,L[i]))*32767,true);v.setInt16(46+i*4,Math.max(-1,Math.min(1,R[i]))*32767,true);}let s='',u=new Uint8Array(v.buffer);for(let i=0;i<u.length;i+=32768)s+=String.fromCharCode(...u.subarray(i,i+32768));await saveNative('assets/audio/music/'+id+'.wav',btoa(s));return {id,seconds:secs,loop_from:bar*song.loopFrom,bpm:song.bpm};
 },id);musicMetadata.tracks[id]={...result,loop_start:result.loop_from,loop_end:result.seconds};console.log('music '+JSON.stringify(result));}
 await fs.writeFile(path.join(out,'assets/audio/music/manifest.json'),JSON.stringify(musicMetadata,null,2));
}
}finally{await browser.close();server.close();}
