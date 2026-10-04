// Bake the original HDR ENV_PASS independently from the visible sky dome.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
function hdr(floatBytes,w,h){
 const src=new Float32Array(floatBytes.buffer,floatBytes.byteOffset,floatBytes.byteLength/4);
 const chunks=[Buffer.from(`#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y ${h} +X ${w}\n`)];
 for(let y=0;y<h;y++){
  const row=Buffer.alloc(w*4);
  for(let x=0;x<w;x++){
   const i=(y*w+x)*4, r=Math.max(0,src[i]),g=Math.max(0,src[i+1]),b=Math.max(0,src[i+2]),m=Math.max(r,g,b);
   if(m<1e-32)continue;
   const e=Math.floor(Math.log2(m))+1,s=256/Math.pow(2,e);
   row[x*4]=Math.min(255,Math.floor(r*s));row[x*4+1]=Math.min(255,Math.floor(g*s));row[x*4+2]=Math.min(255,Math.floor(b*s));row[x*4+3]=e+128;
  }
  chunks.push(Buffer.from([2,2,w>>8,w&255]));
  for(let c=0;c<4;c++)for(let x=0;x<w;){
   const n=Math.min(128,w-x),literal=Buffer.alloc(n+1);literal[0]=n;
   for(let j=0;j<n;j++)literal[j+1]=row[(x+j)*4+c];
   chunks.push(literal);x+=n;
  }
 }
 return Buffer.concat(chunks);
}
const server=http.createServer(async(req,res)=>{try{
 const pathname=new URL(req.url,'http://localhost').pathname;
 if(pathname==='/radiance'){res.setHeader('Content-Type','text/html');res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}
 const file=path.resolve(root,'.'+decodeURIComponent(pathname));if(!file.startsWith(root+path.sep))throw Error('path');
 res.setHeader('Content-Type',({'.js':'text/javascript','.json':'application/json','.png':'image/png'})[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file));
}catch{res.statusCode=404;res.end('missing');}});
await new Promise(r=>server.listen(8496,'127.0.0.1',r));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist']});
try{
 const page=await browser.newPage();let browserErrors=0;page.on('pageerror',e=>{browserErrors++;console.error(e.message);});page.on('console',message=>{if(message.type()==='error'&&message.text().includes('THREE.')){browserErrors++;console.error(message.text());}});
 await page.exposeFunction('saveRadiance',async(theme,face,data)=>{
  const out=path.join(root,'splatink/assets/textures/radiance');await fs.mkdir(out,{recursive:true});
  const bytes=Buffer.from(data,'base64');await fs.writeFile(path.join(out,`${theme}_${face}.hdr`),hdr(bytes,256,256));
 });
 await page.exposeFunction('savePmrem',async(theme,w,h,data,half)=>{
  const out=path.join(root,'splatink/assets/textures/radiance');await fs.mkdir(out,{recursive:true});
  await fs.writeFile(path.join(out,`${theme}_pmrem.hdr`),hdr(Buffer.from(data,'base64'),w,h));
  await fs.writeFile(path.join(out,`${theme}_pmrem.bin`),Buffer.from(half,'base64'));
 });
 await page.goto('http://127.0.0.1:8496/radiance');
 const stats=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js'),{Environment}=await import('/src/world/environment.js'),{G}=await import('/src/core/ctx.js'),{Level}=await import('/src/world/level.js'),{MAP_LAYOUTS}=await import('/src/world/maps.js');
  const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});renderer.toneMapping=T.NoToneMapping;renderer.outputColorSpace=T.LinearSRGBColorSpace;
  G.settings={quality:'high'};G.level=new Level(MAP_LAYOUTS.tidewater);G.scene=new T.Scene();
  const env=new Environment(renderer,G.scene,{bounds:G.level.bounds,theme:'day'});
  const rt=new T.WebGLRenderTarget(256,256,{type:T.FloatType,format:T.RGBAFormat,colorSpace:T.LinearSRGBColorSpace,depthBuffer:false});
  const cam=new T.PerspectiveCamera(90,1,.1,100),dirs=[[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]],result=[];
  const sampleDirections=[...dirs,[1,.5,1],[-1,.25,.7],[.3,-1,-.5],[-.7,.9,-.25]];
  const samples=sampleDirections.flatMap(direction=>[0,.08,.21,.305,.4,.6,.8,1].map(rough=>[...new T.Vector3(...direction).normalize().toArray(),rough]));
  const sampleTarget=new T.WebGLRenderTarget(samples.length,1,{type:T.FloatType,format:T.RGBAFormat,colorSpace:T.LinearSRGBColorSpace,depthBuffer:false});
  const sampleMaterial=new T.RawShaderMaterial({glslVersion:T.GLSL3,uniforms:{envMap:{value:null},samples:{value:samples.map(s=>new T.Vector4(...s))}},
   vertexShader:'precision highp float;in vec3 position;void main(){gl_Position=vec4(position.xy,0.0,1.0);}',
   fragmentShader:`precision highp float;out vec4 sampled_color;uniform sampler2D envMap;uniform vec4 samples[${samples.length}];\n#define texture2D texture\n#define ENVMAP_TYPE_CUBE_UV\n#define CUBEUV_MAX_MIP 8.0\n#define CUBEUV_TEXEL_WIDTH (1.0/768.0)\n#define CUBEUV_TEXEL_HEIGHT (1.0/1024.0)\n${T.ShaderChunk.cube_uv_reflection_fragment}\nvoid main(){int i=int(gl_FragCoord.x);sampled_color=textureCubeUV(envMap,samples[i].xyz,samples[i].w);}`});
  const sampleScene=new T.Scene();sampleScene.add(new T.Mesh(new T.PlaneGeometry(2,2),sampleMaterial));
  for(const theme of ['day','sunset','golden']){
   env.setTheme(theme);let peak=0,mean=[0,0,0];
   for(let f=0;f<6;f++){
    cam.up.set(0,-1,0);if(f===2)cam.up.set(0,0,1);if(f===3)cam.up.set(0,0,-1);cam.lookAt(new T.Vector3(...dirs[f]));
    renderer.setRenderTarget(rt);renderer.render(env._envScene,cam);
    const pixels=new Float32Array(256*256*4);renderer.readRenderTargetPixels(rt,0,0,256,256,pixels);
    for(let i=0;i<pixels.length;i+=4)for(let c=0;c<3;c++){if(!Number.isFinite(pixels[i+c]))throw Error('nonfinite radiance');mean[c]+=pixels[i+c]/(6*256*256);peak=Math.max(peak,pixels[i+c]);}
    const bytes=new Uint8Array(pixels.buffer);let text='';for(let i=0;i<bytes.length;i+=32768)text+=String.fromCharCode(...bytes.subarray(i,i+32768));
    await window.saveRadiance(theme,f,btoa(text));
   }
   const pmrem=env._envRT,w=pmrem.width,h=pmrem.height;
   const packed=pmrem.texture.type===T.HalfFloatType?new Uint16Array(w*h*4):new Float32Array(w*h*4);
   renderer.readRenderTargetPixels(pmrem,0,0,w,h,packed);
   const filtered=packed instanceof Uint16Array?Float32Array.from(packed,T.DataUtils.fromHalfFloat):packed;
   if(!filtered.some(value=>value>0.01)||filtered.some(value=>!Number.isFinite(value)))throw Error('Invalid PMREM pixels');
   const bytes=new Uint8Array(filtered.buffer);let text='';for(let i=0;i<bytes.length;i+=32768)text+=String.fromCharCode(...bytes.subarray(i,i+32768));
   const half=packed instanceof Uint16Array?packed:Uint16Array.from(packed,T.DataUtils.toHalfFloat);
   const halfBytes=new Uint8Array(half.buffer);let halfText='';for(let i=0;i<halfBytes.length;i+=32768)halfText+=String.fromCharCode(...halfBytes.subarray(i,i+32768));
   await window.savePmrem(theme,w,h,btoa(text),btoa(halfText));
   sampleMaterial.uniforms.envMap.value=pmrem.texture;renderer.setScissorTest(false);renderer.setRenderTarget(sampleTarget);renderer.render(sampleScene,new T.Camera());
   const sampled=new Float32Array(samples.length*4);renderer.readRenderTargetPixels(sampleTarget,0,0,samples.length,1,sampled);
   if(!sampled.some((value,index)=>index%4!==3&&value>.01))throw Error('Source CubeUV shader produced no samples');
   result.push({theme,peak,mean,sample_specs:samples,sample_rgb:samples.map((_,i)=>Array.from(sampled.subarray(i*4,i*4+3))),pmrem:{width:w,height:h,maxMip:Math.log2(w/3),format:'rgba16f',path:`res://assets/textures/radiance/${theme}_pmrem.bin`}});
  }
  rt.dispose();sampleTarget.dispose();sampleMaterial.dispose();env.dispose();renderer.dispose();return result;
 });
 if(browserErrors)throw Error(`${browserErrors} source radiance shader errors`);
 await fs.writeFile(path.join(root,'splatink/data/source_radiance.json'),JSON.stringify({size:256,format:'linear RGBE',stats},null,2));
 console.log(JSON.stringify(stats.map(({sample_specs,sample_rgb,...meta})=>meta)));
}finally{await browser.close();await new Promise(r=>server.close(r));}
