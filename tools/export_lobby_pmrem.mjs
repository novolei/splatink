/** Read the original LobbySet PMREM target verbatim, including the source blur. */
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const out=path.join(root,'splatink');
const server=http.createServer(async(req,res)=>{
  try{
    const url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(url==='/lobby-pmrem'){
      res.setHeader('Content-Type','text/html');
      res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;
    }
    if(url==='/favicon.ico'){res.statusCode=204;res.end();return;}
    const file=path.resolve(root,'.'+url);
    if(!file.startsWith(root+path.sep))throw Error('path outside source');
    res.setHeader('Content-Type',{'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.woff2':'font/woff2','.png':'image/png'}[path.extname(file)]||'application/octet-stream');
    res.end(await fs.readFile(file));
  }catch{res.statusCode=404;res.end('missing');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist']});
try{
  const page=await browser.newPage({viewport:{width:128,height:128}});
  page.on('pageerror',error=>{throw error;});
  await page.goto(`http://127.0.0.1:${server.address().port}/lobby-pmrem`);
  const result=await page.evaluate(async()=>{
    const T=await import('/vendor/three/build/three.module.js');
    const {LobbySet}=await import('/src/game/lobbySet.js');
    const {G}=await import('/src/core/ctx.js');
    const library=await (await fetch('/splatink/data/texture_library.json')).json();
    G.settings={quality:'high'};G.quality={particles:1};
    const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});
    renderer.setSize(128,128);renderer.toneMapping=T.NoToneMapping;
    const fakeTex=()=>new T.DataArrayTexture(new Uint8Array(4*library.names.length).fill(255),1,1,library.names.length);
    const texlib={layers:Object.fromEntries(library.names.map((name,i)=>[name,i])),meta:library.meta,albedo:fakeTex(),normal:fakeTex(),orm:fakeTex()};
    const set=new LobbySet(renderer,{quality:'high',texlib});await set.ready;
    const target=set._envRT;
    renderer.setRenderTarget(target);
    const gl=renderer.getContext(),pixels=new Float32Array(target.width*target.height*4);
    gl.readPixels(0,0,target.width,target.height,gl.RGBA,gl.FLOAT,pixels);
    const error=gl.getError();if(error!==gl.NO_ERROR)throw Error('Original Lobby PMREM readPixels: '+error);
    // Match the GL HALF_FLOAT conversion, including all source HDR values.
    const halves=Uint16Array.from(pixels,T.DataUtils.toHalfFloat);
    const bytes=new Uint8Array(halves.buffer);
    let raw='';for(let i=0;i<bytes.length;i+=32768)raw+=String.fromCharCode(...bytes.subarray(i,i+32768));
    const metadata={source:'LobbySet._envRT / PMREMGenerator.fromScene size128 blur0.04',path:'res://assets/textures/lobby/lobby_pmrem.rgba16f.bin',width:target.width,height:target.height,format:'rgba16f',max_mip:Math.log2(target.height/4),intensity:set.environmentIntensity,flip_y:false,team_dependent:true};
    renderer.setRenderTarget(null);set.dispose();renderer.dispose();
    return {metadata,base64:btoa(raw)};
  });
  if(result.metadata.width!==384||result.metadata.height!==512)throw Error('Unexpected source atlas shape: '+JSON.stringify(result.metadata));
  await fs.writeFile(path.join(out,'assets/textures/lobby/lobby_pmrem.rgba16f.bin'),Buffer.from(result.base64,'base64'));
  await fs.writeFile(path.join(out,'data/lobby_pmrem.json'),JSON.stringify(result.metadata,null,2));
  console.log(JSON.stringify(result.metadata));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
