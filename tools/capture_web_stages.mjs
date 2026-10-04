// Render the original web modules at the native verification camera for comparison.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const component=process.argv.find(arg=>arg.startsWith('--component='))?.split('=')[1]||'full';
const server=http.createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/native-reference'){res.setHeader('Content-Type','text/html');res.end('<style>body{margin:0}canvas{display:block}</style><main id="app"></main><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}
 const file=path.resolve(root,'.'+decodeURIComponent(url.pathname));if(!file.startsWith(root+path.sep))throw Error('outside workspace');
 res.setHeader('Content-Type',({'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.png':'image/png','.woff2':'font/woff2'})[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file));
}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(8493,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
try{
 const maps=process.argv.slice(2).filter(arg=>!arg.startsWith('--'));
 for(const id of (maps.length?maps:['tidewater','kelpline','halyard','cargo']))for(const time of ['day','dusk']){
 const page=await browser.newPage({viewport:{width:1280,height:720}});page.on('pageerror',e=>console.error(e.message));
 await page.goto('http://127.0.0.1:8493/native-reference?shadercheck');
 const stats=await page.evaluate(async({id,time,component})=>{
  const T=await import('/vendor/three/build/three.module.js');
  const {G}=await import('/src/core/ctx.js'),{Renderer}=await import('/src/core/renderer.js');
  const {MAP_LAYOUTS}=await import('/src/world/maps.js'),{Level}=await import('/src/world/level.js');
  const {dressingFor}=await import('/src/world/dressing.js'),{PropKit}=await import('/src/world/props.js');
  const {PaintSystem}=await import('/src/world/paint.js'),{Decor}=await import('/src/world/decor.js');
  const {createMuralTexture}=await import('/src/world/murals.js'),{createTextureLibrary}=await import('/src/world/texlib.js');
  const {createLevelMaterial,setLevelLamps}=await import('/src/world/levelMaterial.js'),{Environment}=await import('/src/world/environment.js');
  G.settings={quality:'high',shadows:true,bloom:true};G.teamColors=[new T.Color('#ff3f9e'),new T.Color('#18d48c')];
  const scene=G.scene=new T.Scene(),camera=G.camera=new T.PerspectiveCamera(62,1280/720,.1,6500);
  const R=new Renderer(document.querySelector('#app'),G.settings);G.renderer=R.renderer;R.setScene(scene,camera);R.renderer.toneMappingExposure=.94;
  const kit=new PropKit(scene,{quality:'high',castShadow:true}),colliders=[];
  for(const p of dressingFor(id))colliders.push(...kit.add(p.type,p).colliders);kit.build();
  const level=G.level=new Level(MAP_LAYOUTS[id],colliders);
  const meta=await(await fetch('/assets/lightmaps/'+id+'.json')).json();level.layoutLightmap(meta.ppm,meta.size);
  const ao=await new T.TextureLoader().loadAsync('/assets/lightmaps/'+id+'.png');ao.colorSpace=T.NoColorSpace;
  const lib=await createTextureLibrary(R.renderer,{size:512}),murals=await createMuralTexture(id);
  const paint=G.paint=new PaintSystem(R.renderer,level,{atlasSize:2048,maxDensity:18});
  const mat=createLevelMaterial(paint.texture,2048,murals,{lightmap:ao,texlib:lib,paint});
  const terrain=new T.Mesh(level.buildGeometry(2048,b=>!b.grate),mat);terrain.castShadow=true;terrain.receiveShadow=true;scene.add(terrain);
  const gm=createLevelMaterial(paint.texture,2048,murals,{grate:true,lightmap:ao,texlib:lib,paint});
  const grate=new T.Mesh(level.buildGeometry(2048,b=>b.grate),gm);grate.receiveShadow=true;scene.add(grate);
  const decor=new Decor(scene,level);decor.setTeamColors(G.teamColors);
  const footprint=level.blocks.filter(b=>(b.aligned||b.axes[1].y>.9999)&&b.aabbMax.y<.01&&b.aabbMax.y> -2.5&&b.aabbMin.y< -1).map(b=>b.aligned?{minX:b.aabbMin.x,maxX:b.aabbMax.x,minZ:b.aabbMin.z,maxZ:b.aabbMax.z}:{cx:b.center.x,cz:b.center.z,hx:b.half.x,hz:b.half.z,ax:b.axes[0].x,az:b.axes[0].z});
  const env=G.env=new Environment(R.renderer,scene,{bounds:level.bounds,theme:time==='dusk'?'sunset':id==='halyard'?'golden':'day',footprint,shadowSize:2048});scene.environment=env.envMap;
  const pos=new T.Vector3(...MAP_LAYOUTS[id].spawnPads[0]);pos.y=level.groundHeight(pos.x,pos.z)+.02;
  const direction=pos.clone().multiply(new T.Vector3(-1,0,-1)).normalize();camera.position.copy(pos).addScaledVector(direction,-4.5).add(new T.Vector3(0,2.1,0));camera.lookAt(pos.clone().addScaledVector(direction,10).add(new T.Vector3(0,.8,0)));
  setLevelLamps(mat,level,time==='dusk'?1:0);setLevelLamps(gm,level,time==='dusk'?1:0);
  if(component!=='full'){
   setLevelLamps(mat,level,0);setLevelLamps(gm,level,0);
   if(component==='sun'){env.hemi.intensity=0;scene.environmentIntensity=0;}
   if(component==='indirect')env.sun.intensity=0;
   if(component==='albedo')for(const material of [mat,gm]){
    const original=material.onBeforeCompile;material.onBeforeCompile=shader=>{original(shader);shader.fragmentShader=shader.fragmentShader.replace('vec3 outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;','vec3 outgoingLight = diffuseColor.rgb;');};
   }
  }
  for(let i=0;i<60;i++){env.update(1/60,camera);decor.update?.(1/60);mat.userData.uniforms.uTime.value=i/60;gm.userData.uniforms.uTime.value=i/60;R.renderer.info.reset();R.render();await new Promise(requestAnimationFrame);}
  return {id,time,camera:camera.position.toArray(),triangles:R.renderer.info.render.triangles,draw_calls:R.renderer.info.render.calls};
 },{id,time,component});
 const out=path.join(root,'splatink/shots/reference');await fs.mkdir(out,{recursive:true});await page.screenshot({path:path.join(out,id+'_'+time+'_web'+(component==='full'?'':'_'+component)+'.png')});console.log(JSON.stringify(stats));await page.close();
 }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
