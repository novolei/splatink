// Compare original Three character shaders at the exact native pose and camera.
// Root first runs verify_face_visual.gd; this tool only uses a local hidden browser.
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const fixture=JSON.parse(await fs.readFile(path.join(root,'splatink/shots/face_reference_pose.json'),'utf8'));
const server=http.createServer(async(req,res)=>{try{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/favicon.ico'){res.statusCode=204;res.end();return;}
  if(url.pathname==='/face-reference'){
    res.setHeader('Content-Type','text/html');
    res.end('<style>body{margin:0}canvas{display:block}</style><main id="app"></main><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;
  }
  const file=path.resolve(root,'.'+decodeURIComponent(url.pathname));
  if(!file.startsWith(root+path.sep))throw Error('outside workspace');
  res.setHeader('Content-Type',({'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.png':'image/png','.woff2':'font/woff2'})[path.extname(file)]||'application/octet-stream');
  res.end(await fs.readFile(file));
}catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(8496,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling']});
let errors=0;
try{
  for(const [pose,record]of Object.entries(fixture.poses)){
    const page=await browser.newPage({viewport:{width:fixture.size[0],height:fixture.size[1]}});
    page.on('pageerror',e=>{errors++;console.error(e.message);});
    page.on('console',m=>{if(m.type()==='error'){errors++;console.error(m.text());}});
    await page.goto('http://127.0.0.1:8496/face-reference?shadercheck');
    const stats=await page.evaluate(async({fixture,record})=>{
      const T=await import('/vendor/three/build/three.module.js');
      const {G}=await import('/src/core/ctx.js'),{Renderer}=await import('/src/core/renderer.js');
      const {Character}=await import('/src/game/character.js');
      G.settings={quality:'high',shadows:true,bloom:false,ao:false};
      G.teamColors=[new T.Color(fixture.team),new T.Color('#2f5bff')];
      const scene=G.scene=new T.Scene(),camera=G.camera=new T.PerspectiveCamera(record.fov,fixture.size[0]/fixture.size[1],record.near,record.far);
      const renderer=new Renderer(document.querySelector('#app'),G.settings);
      G.renderer=renderer.renderer;renderer.setScene(scene,camera);
      if(renderer.gtao)renderer.gtao.enabled=false;
      G.env={grade:{uSat:1.06,uVib:0,uContrast:1,uLift:0,uShadowTint:[1,1,1],uHighTint:[1,1,1],uExposure:1,uVignette:0}};
      const set=(object,value)=>{object.position.fromArray(value.p);object.quaternion.fromArray(value.q);object.scale.fromArray(value.s);};
      set(camera,record.camera);
      scene.background=new T.Color().setRGB(.17,.20,.26,T.SRGBColorSpace);
      const character=new Character({weapon:'shooter',style:fixture.style,color:new T.Color(fixture.team)});
      character.setLod('hero');character.update(0,{form:'kid',grounded:true,speed:0});
      scene.add(character.root);set(character.root,record.root);
      character.model.position.set(0,0,0);character.model.quaternion.identity();character.model.scale.setScalar(1);
      character.kid.position.set(0,0,0);character.kid.quaternion.identity();character.kid.scale.setScalar(1);
      character.squidRoot.visible=false;
      for(const [name,transform]of Object.entries(record.bones))if(character.bones[name])set(character.bones[name],transform);
      for(const [name,value]of Object.entries(record.uniforms)){
        const uniform=character.u[name];if(!uniform)continue;
        if(Array.isArray(value)&&uniform.value?.fromArray)uniform.value.fromArray(value);else uniform.value=value;
      }
      const hemi=record.hemi;
      scene.add(new T.HemisphereLight(new T.Color().fromArray(hemi.color),new T.Color().fromArray(hemi.ground),hemi.intensity));
      for(const source of record.lights){
        const light=new T.DirectionalLight(new T.Color().fromArray(source.color),source.intensity);
        set(light,source.transform);light.castShadow=source.shadows;
        const forward=new T.Vector3(0,0,-1).applyQuaternion(light.quaternion);
        light.target.position.copy(light.position).add(forward);
        if(source.shadows){const c=light.shadow.camera;c.left=-1.25;c.right=1.25;c.top=1.25;c.bottom=-1.25;c.near=.5;c.far=16;light.shadow.mapSize.set(2048,2048);light.shadow.bias=-.0003;light.shadow.normalBias=.012;light.shadow.radius=3;}
        scene.add(light,light.target);
      }
      character.root.updateMatrixWorld(true);character.skeleton.update();
      renderer.renderer.toneMappingExposure=1;
      for(let i=0;i<4;i++){renderer.render();await new Promise(requestAnimationFrame);}
      return {bones:character.boneList.length,triangles:renderer.renderer.info.render.triangles,draw_calls:renderer.renderer.info.render.calls,camera:camera.position.toArray()};
    },{fixture,record});
    await page.screenshot({path:path.join(root,`splatink/shots/reference/face_${pose}_web.png`)});
    console.log(JSON.stringify({pose,...stats}));
    await page.close();
  }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
if(errors)throw Error(`Original face capture had ${errors} browser/shader errors`);
