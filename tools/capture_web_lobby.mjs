// Actual Showcase/LobbySet render. The UI lab's flat background is not a
// lighting reference for the live 3D alley; this calls the original renderer.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const server=http.createServer(async(req,res)=>{try{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/favicon.ico'){res.statusCode=204;res.end();return;}
  if(url.pathname==='/lobby-reference'){
    res.setHeader('Content-Type','text/html');
    res.end('<style>body{margin:0}canvas{display:block}</style><main id="app"></main><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;
  }
  const file=path.resolve(root,'.'+decodeURIComponent(url.pathname));
  if(!file.startsWith(root+path.sep))throw Error('outside workspace');
  res.setHeader('Content-Type',({'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.png':'image/png','.woff2':'font/woff2'})[path.extname(file)]||'application/octet-stream');
  res.end(await fs.readFile(file));
}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
const errors=[];
try{
  const page=await browser.newPage({viewport:{width:1280,height:720}});
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.goto(`http://127.0.0.1:${server.address().port}/lobby-reference?shadercheck`);
  const stats=await page.evaluate(async()=>{
    const T=await import('/vendor/three/build/three.module.js');
    const {G}=await import('/src/core/ctx.js');
    const {Showcase}=await import('/src/game/showcase.js');
    const {Character}=await import('/src/game/character.js');
    const {createTextureLibrary}=await import('/src/world/texlib.js');
    G.settings={quality:'high',shadows:true,bloom:false,ao:false};
    G.teamColors=[new T.Color('#ff8a14'),new T.Color('#2f5bff')];
    const renderer=new T.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});
    renderer.setSize(1280,720);renderer.setPixelRatio(1);renderer.toneMapping=T.NeutralToneMapping;renderer.toneMappingExposure=1;
    renderer.shadowMap.enabled=true;renderer.shadowMap.type=T.PCFSoftShadowMap;
    document.querySelector('#app').append(renderer.domElement);
    G.renderer=renderer;G.scene=new T.Scene();G.camera=new T.PerspectiveCamera();
    G.game={profile:{style:{hair:1,skin:0,eyes:0,outfit:0},weapon:'shooter'},texlib:await createTextureLibrary(renderer,{size:512})};
    const showcase=new Showcase(renderer,Character);
    const players=Array.from({length:8},(_,i)=>({id:'source'+i,name:'Source '+i,team:i<4?0:1,you:i===0,weapon:['shooter','roller','charger','slosher','shooter','dualies','blaster','splatling'][i],style:{hair:i%8,skin:i%9,outfit:i%10,eyes:i%8},ready:true}));
    showcase.showLobby(players,G.teamColors,{reduced:true});
    const start=performance.now();
    while(!showcase.lob.ready){if(showcase.lob.failed||performance.now()-start>45000)throw Error('Source Showcase alley failed to become ready');await new Promise(resolve=>setTimeout(resolve,30));}
    for(let i=0;i<360;i++)showcase.update(1/30);
    for(let i=0;i<4;i++){showcase.update(1/60);showcase.render();await new Promise(requestAnimationFrame);}
    const c=showcase.lob.cam;
    return {source:'Showcase.render / LobbySet original fullFrame scene',camera:c.position.toArray(),camera_quaternion:c.quaternion.toArray(),fov:c.fov,view_offset:c.view,players:[...showcase.lob.members.values()].map(m=>({id:m.id,phase:m.phase,mark:m.mark,pos:m.c?.root.position.toArray()})),triangles:renderer.info.render.triangles,draw_calls:renderer.info.render.calls,neutral_exposure:renderer.toneMappingExposure};
  });
  if(errors.length)throw Error(errors.join('\n'));
  const directory=path.join(root,'splatink/shots/reference');await fs.mkdir(directory,{recursive:true});
  await page.screenshot({path:path.join(directory,'lobby_scene_web.png')});
  await fs.writeFile(path.join(directory,'lobby_scene_web.json'),JSON.stringify(stats,null,2));
  console.log(JSON.stringify({...stats,browser_errors:errors.length}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
