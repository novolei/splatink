/** Original smooth geometry-normal camera fixture, isolated from production.
 * node --experimental-loader ./splatink/tools/source_loader.mjs ./splatink/tools/export_ao_normal_reference.mjs
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const directory=path.join(root,'splatink/tests/ao/transport_reference');
await fs.mkdir(directory,{recursive:true});
const server=http.createServer(async(req,res)=>{
  try{
    const url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(url==='/normal-reference'){res.setHeader('Content-Type','text/html');res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;}
    if(url==='/favicon.ico'){res.statusCode=204;res.end();return;}
    const file=path.resolve(root,'.'+url);if(!file.startsWith(root+path.sep))throw Error('outside source');
    res.setHeader('Content-Type',{'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json'}[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file));
  }catch{res.statusCode=404;res.end('missing');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist']});
const errors=[];
try{
  const page=await browser.newPage({viewport:{width:80,height:64}});
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.goto(`http://127.0.0.1:${server.address().port}/normal-reference`);
  const results=await page.evaluate(async()=>{
    const T=await import('/vendor/three/build/three.module.js');
    const {GTAOPass}=await import('/vendor/three/jsm/postprocessing/GTAOPass.js');
    const {FullScreenQuad}=await import('/vendor/three/jsm/postprocessing/Pass.js');
    const {Character}=await import('/src/game/character.js');
    const {G}=await import('/src/core/ctx.js');
    G.settings={quality:'high',shadows:false,bloom:false};
    const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});
    renderer.debug.checkShaderErrors=true;renderer.toneMapping=T.NoToneMapping;renderer.outputColorSpace=T.LinearSRGBColorSpace;
    const gl=renderer.getContext(),debug=gl.getExtension('WEBGL_debug_renderer_info');
    const gpu=debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER);
    const copy=new T.ShaderMaterial({depthTest:false,depthWrite:false,toneMapped:false,uniforms:{inputTexture:{value:null}},vertexShader:'varying vec2 uv0;void main(){uv0=uv;gl_Position=vec4(position.xy,0.,1.);}',fragmentShader:'varying vec2 uv0;uniform sampler2D inputTexture;void main(){gl_FragColor=vec4(texture2D(inputTexture,uv0).r,0.,0.,1.);}'});
    const quad=new FullScreenQuad(copy);
    const encode=typed=>{const bytes=new Uint8Array(typed.buffer,typed.byteOffset,typed.byteLength);let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s);};
    const read=(target,half=true)=>{renderer.setRenderTarget(target);const pixels=new Float32Array(target.width*target.height*4);gl.readPixels(0,0,target.width,target.height,gl.RGBA,gl.FLOAT,pixels);if(gl.getError()!==gl.NO_ERROR)throw Error('Original normal GPU readback failed');if(pixels.some(x=>!Number.isFinite(x)))throw Error('Nonfinite original normal/depth');return{size:[target.width,target.height],format:half?'rgba16f':'rgba32f',base64:encode(half?Uint16Array.from(pixels,T.DataUtils.toHalfFloat):pixels)};};
    const attribute=(attr,integer=false)=>{const values=integer?Int32Array.from(attr.array):Float32Array.from(attr.array);return{count:attr.count,item_size:attr.itemSize,format:integer?'int32':'float32',base64:encode(values)};};
    const captureGeometry=scene=>{
      const meshes=[],rigs=[],rigKeys=new Map();let skipped=0;
      scene.traverseVisible(object=>{
        if(!object.isMesh)return;
        const geometry=object.geometry;
        if(geometry.drawRange.count===0){skipped++;return;}
        const record={name:object.name||`mesh_${meshes.length}`,world:object.matrixWorld.toArray(),attributes:{position:attribute(geometry.attributes.position),normal:attribute(geometry.attributes.normal)},index:attribute(geometry.index||new T.BufferAttribute(Uint32Array.from({length:geometry.attributes.position.count},(_,i)=>i),1),true),rig:-1};
        if(object.isSkinnedMesh){
          record.attributes.bones=attribute(geometry.attributes.skinIndex,true);record.attributes.weights=attribute(geometry.attributes.skinWeight);
          // Snapshot the actual source GPU bone matrices. Roots below are
          // independent affine pose probes, not a replacement production rig.
          const matrices=object.skeleton.bones.map((_,i)=>new T.Matrix4().multiplyMatrices(object.bindMatrixInverse,new T.Matrix4().fromArray(object.skeleton.boneMatrices,i*16)).multiply(object.bindMatrix).toArray());
          const key=object.skeleton.uuid+'|'+object.bindMatrixInverse.elements.join(',')+'|'+object.bindMatrix.elements.join(',');
          if(!rigKeys.has(key)){rigKeys.set(key,rigs.length);rigs.push({world:object.matrixWorld.toArray(),bone_names:object.skeleton.bones.map(b=>b.name),deformation_matrices:matrices});}
          record.rig=rigKeys.get(key);
        }
        meshes.push(record);
      });return{meshes,rigs,skipped_override_parts:skipped};
    };
    const cases=[];
    for(const [width,height]of[[64,48],[65,49]])for(const kind of['geometry','source_character']){
      renderer.setSize(width,height,false);
      const scene=G.scene=new T.Scene(),camera=G.camera=new T.PerspectiveCamera(63,width/height,.05,150);
      camera.position.set(3.15,2.75,4.75);camera.lookAt(.1,.42,-.45);camera.updateMatrixWorld(true);
      const material=new T.MeshStandardMaterial({color:0xffffff});
      const add=(name,geometry,position,rotation=[0,0,0])=>{const mesh=new T.Mesh(geometry,material);mesh.name=name;mesh.position.fromArray(position);mesh.rotation.fromArray(rotation);scene.add(mesh);return mesh;};
      add('Floor',new T.PlaneGeometry(9,8),[0,-.04,-.65],[-Math.PI/2,0,0]);
      add('Crate',new T.BoxGeometry(.85,.8,.85),[-.85,.36,-.6],[0,.32,0]);
      add('Overhang',new T.BoxGeometry(2.1,.14,1.35),[-.05,1.15,-1.4],[0,-.21,.08]);
      add('Support',new T.BoxGeometry(.18,1.16,.24),[-.76,.54,-1.28]);
      add('SmoothSphere',new T.SphereGeometry(.38,24,18),[1.1,.34,-.28]);
      add('Post',new T.CylinderGeometry(.065,.065,1.5,12),[1.64,.71,-1.6]);
      add('WallA',new T.BoxGeometry(.5,1.6,2.6),[-1.62,.76,-1.9]);
      add('WallB',new T.BoxGeometry(2.9,1.6,.24),[-.18,.76,-3.08]);
      const transparent=add('TransparentOverride',new T.SphereGeometry(.22,16,12),[-.25,.19,.78]);transparent.material=new T.MeshBasicMaterial({transparent:true,opacity:.08});
      let character=null;
      if(kind==='source_character'){
        let seed=31173;const random=Math.random;Math.random=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;};
        character=new Character({weapon:'dualies',style:{hair:3,hat:2,skin:3,outfit:6,eyes:4,brows:1},color:new T.Color('#ff8a14')});Math.random=random;
        character.setLod('game');character.root.position.set(.1,0,.28);character.root.rotation.y=-.62;scene.add(character.root);
        for(let i=0;i<60;i++)character.update(1/30,{form:'kid',grounded:true,speed:2,localMove:{x:.3,z:1},ink:.7});
        character.root.updateMatrixWorld(true);character.skeleton.update();
      }
      const ao=new GTAOPass(scene,camera,width,height);ao.output=GTAOPass.OUTPUT.Off;
      const dummy=new T.WebGLRenderTarget(width,height,{type:T.HalfFloatType,depthBuffer:false});
      ao.render(renderer,dummy,dummy,0,false);
      const normal=read(ao.normalRenderTarget),depthCopy=new T.WebGLRenderTarget(width,height,{type:T.FloatType,depthBuffer:false});
      copy.uniforms.inputTexture.value=ao.depthTexture;renderer.setRenderTarget(depthCopy);renderer.clear();quad.render(renderer);
      cases.push({name:`${width}x${height}_${kind}`,size:[width,height],gpu,camera_world:camera.matrixWorld.toArray(),fov:camera.fov,near:camera.near,far:camera.far,normal,depth:read(depthCopy,false),...captureGeometry(scene)});
      renderer.setRenderTarget(null);ao.dispose();dummy.dispose();depthCopy.dispose();character?.dispose();scene.traverse(o=>{if(o.geometry)o.geometry.dispose();});
    }
    quad.dispose();copy.dispose();renderer.dispose();return cases;
  });
  if(errors.length)throw Error(errors.join('\n'));
  for(const record of results){
    const write=async(name,value)=>{const bytes=Buffer.from(value.base64,'base64'),filename=`${record.name}_${name}.${value.format}.bin`;await fs.writeFile(path.join(directory,filename),bytes);delete value.base64;value.path=`res://tests/ao/transport_reference/${filename}`;value.sha256=createHash('sha256').update(bytes).digest('hex');};
    await write('normal',record.normal);await write('depth',record.depth);
    for(let i=0;i<record.meshes.length;i++){const mesh=record.meshes[i];for(const[name,value]of Object.entries(mesh.attributes))await write(`mesh${i}_${name}`,value);await write(`mesh${i}_index`,mesh.index);}
  }
  const fixture={version:1,source:'Original GTAOPass MeshNormalMaterial smooth geometry override; actual 87-bone GPU matrices',flip_y_native:true,normal_absolute_tolerance:.002,depth_absolute_tolerance:.000002,coverage_mismatch_tolerance:0,cases:results};
  await fs.writeFile(path.join(root,'splatink/tests/ao/normal_transport_reference.json'),JSON.stringify(fixture,null,2));
  console.log(JSON.stringify({cases:results.length,meshes:results.map(x=>x.meshes.length),source_bones:results.map(x=>x.rigs.map(r=>r.bone_names.length)),browser_errors:errors.length,output:'tests/ao/normal_transport_reference.json'}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
