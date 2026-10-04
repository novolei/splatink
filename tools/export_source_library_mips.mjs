// Freeze the original GPU mip chain, preserving its linear-space sRGB filter.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),out=path.join(root,'splatink');
const server=http.createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/mip-export'){res.setHeader('Content-Type','text/html');res.end('<canvas></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}
 const file=path.resolve(root,'.'+decodeURIComponent(url.pathname));if(!file.startsWith(root+path.sep))throw Error('path');
 res.setHeader('Content-Type',({'.js':'text/javascript','.json':'application/json'})[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file));
}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(8498,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist']});
const errors=[];
try{
 const page=await browser.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.exposeFunction('saveMip',async(name,data)=>fs.writeFile(path.join(out,'assets/textures/library',name),Buffer.from(data,'base64')));
 await page.goto('http://127.0.0.1:8498/mip-export');
 const result=await page.evaluate(async()=>{
  const T=await import('/vendor/three/build/three.module.js');
  const {createTextureLibrary}=await import('/src/world/texlib.js');
  const renderer=new T.WebGLRenderer({canvas:document.querySelector('canvas')});renderer.setSize(512,512);
  const lib=await createTextureLibrary(renderer,{size:512}),gl=renderer.getContext(),framebuffer=gl.createFramebuffer();
  const b64=data=>{let text='';for(let i=0;i<data.length;i+=32768)text+=String.fromCharCode(...data.subarray(i,i+32768));return btoa(text);};
  const records=[];
  for(const [kind,texture] of [['albedo',lib.albedo],['normal',lib.normal],['orm',lib.orm]]){
   const handle=renderer.properties.get(texture).__webglTexture;
   for(let layer=0;layer<lib.names.length;layer++){
    const chunks=[];let bytes=0;
    for(let level=1,size=lib.size>>1;size>=1;level++,size>>=1){
     gl.bindFramebuffer(gl.FRAMEBUFFER,framebuffer);gl.framebufferTextureLayer(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,handle,level,layer);gl.readBuffer(gl.COLOR_ATTACHMENT0);
     if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw Error('Incomplete mip '+kind+'/'+layer+'/'+level);
     const pixels=new Uint8Array(size*size*4);gl.readPixels(0,0,size,size,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
     if(gl.getError()!==gl.NO_ERROR)throw Error('GPU mip read failed');
     chunks.push(pixels);bytes+=pixels.length;
    }
    const data=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){data.set(chunk,offset);offset+=chunk.length;}
    await saveMip(`${kind}_${String(layer).padStart(2,'0')}.mips.bin`,b64(data));records.push({kind,layer,bytes});
   }
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.deleteFramebuffer(framebuffer);renderer.dispose();
  return {size:lib.size,layers:lib.names.length,levels:Math.log2(lib.size),records};
 });
 if(errors.length)throw Error(errors.join('\n'));
 await fs.writeFile(path.join(out,'data/source_library_mips.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify({size:result.size,layers:result.layers,levels:result.levels,files:result.records.length,bytes:result.records.reduce((n,r)=>n+r.bytes,0),browser_errors:errors.length}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
