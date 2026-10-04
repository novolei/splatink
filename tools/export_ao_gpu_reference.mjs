/** Actual original GTAOPass geometry-normal/depth/AO/PD GPU fixture.
 * Draft native kernels remain under tests/ao; no production compositor changes.
 * Run: node --experimental-loader ./splatink/tools/source_loader.mjs ./splatink/tools/export_ao_gpu_reference.mjs
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {ShaderChunk} from 'three';
import {GTAOShader} from '../../vendor/three/jsm/shaders/GTAOShader.js';
import {PoissonDenoiseShader} from '../../vendor/three/jsm/shaders/PoissonDenoiseShader.js';

const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const directory=path.join(root,'splatink/tests/ao');
await fs.mkdir(directory,{recursive:true});
const block=`layout(set=0,binding=5,std140)uniform SceneParams{
 mat4 projection;mat4 projection_inverse;mat4 world;
 vec4 size_radius_exponent;vec4 thickness_scale_falloff_blend;
 vec4 denoise_phi_radius;vec4 near_far_index;
}p;
#define cameraProjectionMatrix p.projection
#define cameraProjectionMatrixInverse p.projection_inverse
#define cameraWorldMatrix p.world
#define resolution p.size_radius_exponent.xy
#define cameraNear p.near_far_index.x
#define cameraFar p.near_far_index.y
`;
function kernel(source,defines,pd=false){
  let body=source.replace(/varying\s+vec2\s+vUv\s*;/g,'')
    .replace(/uniform\s+(?:highp\s+)?\w+\s+\w+\s*;/g,'')
    .replace('#include <common>',ShaderChunk.common).replace('#include <packing>',ShaderChunk.packing)
    .replace(/discard\s*;/g,'imageStore(result_image,pixel,vec4(1.0));')
    .replace(/gl_FragColor\s*=\s*([^;]+);/g,'imageStore(result_image,pixel,$1);')
    .replace('void main() {','void main() {\n ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(pixel,ivec2(resolution))))return;\n vec2 vUv=(vec2(pixel)+0.5)/resolution;');
  return `// Mechanical port of the vendored source shader, preserving its sample math.
#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1)in;
layout(set=0,binding=0)uniform sampler2D tNormal;
layout(set=0,binding=1)uniform sampler2D tDepth;
layout(set=0,binding=2)uniform sampler2D tNoise;
${pd?'layout(set=0,binding=3)uniform sampler2D tDiffuse;':''}
layout(set=0,binding=4,rgba16f)uniform restrict writeonly image2D result_image;
${block}
${Object.entries(defines).map(([k,v])=>`#define ${k} ${v}`).join('\n')}
${pd?`#define radius p.denoise_phi_radius.w
#define lumaPhi p.denoise_phi_radius.x
#define depthPhi p.denoise_phi_radius.y
#define normalPhi p.denoise_phi_radius.z
#define index int(p.near_far_index.z)`:`#define radius p.size_radius_exponent.z
#define distanceExponent p.size_radius_exponent.w
#define thickness p.thickness_scale_falloff_blend.x
#define scale p.thickness_scale_falloff_blend.y
#define distanceFallOff p.thickness_scale_falloff_blend.z`}
${body}
`;
}
await fs.writeFile(path.join(directory,'source_gtao.glsl'),kernel(GTAOShader.fragmentShader,{...GTAOShader.defines,SAMPLES:12}));
// The actual source updatePdMaterial call does not regenerate SAMPLE_VECTORS:
// initial radiusExponent=1 is retained despite the pass property defaulting to2.
await fs.writeFile(path.join(directory,'source_pd.glsl'),kernel(PoissonDenoiseShader.fragmentShader,PoissonDenoiseShader.defines,true));
await fs.writeFile(path.join(directory,'source_blend.glsl'),`#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1)in;
layout(set=0,binding=0)uniform sampler2D input_color;
layout(set=0,binding=1)uniform sampler2D denoised;
layout(set=0,binding=4,rgba16f)uniform restrict writeonly image2D result_image;
${block}
void main(){ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(pixel,ivec2(resolution))))return;
 vec2 uv=(vec2(pixel)+.5)/resolution;vec4 original=textureLod(input_color,uv,0.0);vec4 ao=textureLod(denoised,uv,0.0);
 imageStore(result_image,pixel,original*vec4(mix(vec3(1.0),ao.rgb,p.thickness_scale_falloff_blend.w),ao.a));}
`);
if(process.argv.includes('--shaders-only')){console.log('Draft source AO/PD/blend kernels generated under tests/ao.');process.exit(0);}
const server=http.createServer(async(req,res)=>{
  try{
    const url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(url==='/ao-reference'){
      res.setHeader('Content-Type','text/html');res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;
    }
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
  await page.goto(`http://127.0.0.1:${server.address().port}/ao-reference`);
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
    const copy=new T.ShaderMaterial({depthTest:false,depthWrite:false,toneMapped:false,uniforms:{inputTexture:{value:null},depthOnly:{value:false}},
      vertexShader:'varying vec2 uv0;void main(){uv0=uv;gl_Position=vec4(position.xy,0.,1.);}',
      fragmentShader:'varying vec2 uv0;uniform sampler2D inputTexture;uniform bool depthOnly;void main(){vec4 v=texture2D(inputTexture,uv0);gl_FragColor=depthOnly?vec4(v.r,0.,0.,1.):v;}'});
    const quad=new FullScreenQuad(copy);
    const encode=bytes=>{let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s);};
    const read=(target,half=true)=>{
      renderer.setRenderTarget(target);const pixels=new Float32Array(target.width*target.height*4);
      gl.readPixels(0,0,target.width,target.height,gl.RGBA,gl.FLOAT,pixels);const err=gl.getError();if(err!==gl.NO_ERROR)throw Error('Source AO GPU readPixels '+err);
      if(pixels.some(x=>!Number.isFinite(x)))throw Error('Nonfinite original GTAO output');
      const typed=half?Uint16Array.from(pixels,T.DataUtils.toHalfFloat):pixels;
      return {size:[target.width,target.height],format:half?'rgba16f':'rgba32f',base64:encode(new Uint8Array(typed.buffer))};
    };
    const noise=texture=>({size:[texture.image.width,texture.image.height],format:'rgba8',base64:encode(texture.image.data)});
    const cases=[];
    for(const [width,height]of [[64,48],[65,49]])for(const kind of ['geometry','source_character']){
      renderer.setSize(width,height,false);
      const scene=G.scene=new T.Scene(),camera=G.camera=new T.PerspectiveCamera(63,width/height,.05,150);
      camera.position.set(3.15,2.75,4.75);camera.lookAt(.1,.42,-.45);camera.updateMatrixWorld(true);
      const material=new T.MeshStandardMaterial({color:0xffffff});
      const add=(geometry,position,rotation=[0,0,0])=>{const m=new T.Mesh(geometry,material);m.position.fromArray(position);m.rotation.fromArray(rotation);scene.add(m);return m;};
      add(new T.PlaneGeometry(9,8),[0,-.04,-.65],[-Math.PI/2,0,0]);
      add(new T.BoxGeometry(.85,.8,.85),[-.85,.36,-.6],[0,.32,0]);
      add(new T.BoxGeometry(2.1,.14,1.35),[-.05,1.15,-1.4],[0,-.21,.08]);
      add(new T.BoxGeometry(.18,1.16,.24),[-.76,.54,-1.28]);
      add(new T.SphereGeometry(.38,24,18),[1.1,.34,-.28]);
      add(new T.CylinderGeometry(.065,.065,1.5,12),[1.64,.71,-1.6]);
      add(new T.BoxGeometry(.5,1.6,2.6),[-1.62,.76,-1.9]);
      add(new T.BoxGeometry(2.9,1.6,.24),[-.18,.76,-3.08]);
      // Exact original override behavior includes transparent meshes, skips lines,
      // and source Character gates small moving weapon parts and owned far LODs.
      const transparent=add(new T.SphereGeometry(.22,16,12),[-.25,.19,.78]);transparent.material=new T.MeshBasicMaterial({transparent:true,opacity:.08});
      scene.add(new T.Line(new T.BufferGeometry().setFromPoints([new T.Vector3(-2,0,1),new T.Vector3(2,1,-2)]),new T.LineBasicMaterial()));
      let character=null;
      if(kind==='source_character'){
        character=new Character({weapon:'dualies',style:{hair:3,hat:2,skin:3,outfit:6,eyes:4,brows:1},color:new T.Color('#ff8a14')});
        character.setLod('game');character.root.position.set(.1,0,.28);character.root.rotation.y=-.62;scene.add(character.root);
        for(let i=0;i<60;i++)character.update(1/30,{form:'kid',grounded:true,speed:2,localMove:{x:.3,z:1},ink:.7});
        character.root.updateMatrixWorld(true);character.skeleton.update();
      }
      let seed=17341;const originalRandom=Math.random;Math.random=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;};
      const ao=new GTAOPass(scene,camera,width,height);Math.random=originalRandom;
      ao.output=GTAOPass.OUTPUT.Default;ao.blendIntensity=.8;
      ao.updateGtaoMaterial({radius:1.1,distanceExponent:1.6,thickness:1,scale:1.5,samples:12,distanceFallOff:1});
      ao.updatePdMaterial({lumaPhi:10,depthPhi:2,normalPhi:3,radius:6,rings:2,samples:16});
      const pixels=new Uint16Array(width*height*4);
      for(let y=0;y<height;y++)for(let x=0;x<width;x++){const i=(y*width+x)*4,u=x/(width-1),v=y/(height-1);for(let k=0;k<4;k++)pixels[i+k]=T.DataUtils.toHalfFloat([.15+u*3.1,.24+v*2.2,.08+(1-u)*v*1.8,.15+.85*u][k]);}
      const inputTexture=new T.DataTexture(pixels,width,height,T.RGBAFormat,T.HalfFloatType);inputTexture.flipY=false;inputTexture.needsUpdate=true;
      const input=new T.WebGLRenderTarget(width,height,{type:T.HalfFloatType,depthBuffer:false}),output=input.clone();
      copy.uniforms.inputTexture.value=inputTexture;copy.uniforms.depthOnly.value=false;renderer.setRenderTarget(input);renderer.clear();quad.render(renderer);
      ao.render(renderer,output,input,0,false);
      const stages={input:read(input),normal:read(ao.normalRenderTarget),ao:read(ao.gtaoRenderTarget),pd:read(ao.pdRenderTarget),output:read(output)};
      const depthCopy=new T.WebGLRenderTarget(width,height,{type:T.FloatType,depthBuffer:false});
      copy.uniforms.inputTexture.value=ao.depthTexture;copy.uniforms.depthOnly.value=true;renderer.setRenderTarget(depthCopy);renderer.clear();quad.render(renderer);stages.depth=read(depthCopy,false);
      const uniforms=Object.fromEntries(Object.entries(ao.gtaoMaterial.uniforms).filter(([,u])=>typeof u.value==='number').map(([k,u])=>[k,u.value]));
      cases.push({name:`${width}x${height}_${kind}`,size:[width,height],gpu,stages,noises:{ao:noise(ao.gtaoNoiseTexture),pd:noise(ao.pdNoiseTexture)},projection:camera.projectionMatrix.toArray(),projection_inverse:camera.projectionMatrixInverse.toArray(),world:camera.matrixWorld.toArray(),params:{...uniforms,blendIntensity:ao.blendIntensity,lumaPhi:ao.pdMaterial.uniforms.lumaPhi.value,depthPhi:ao.pdMaterial.uniforms.depthPhi.value,normalPhi:ao.pdMaterial.uniforms.normalPhi.value,pdRadius:ao.pdMaterial.uniforms.radius.value,index:ao.pdMaterial.uniforms.index.value},gtao_defines:ao.gtaoMaterial.defines,pd_defines:ao.pdMaterial.defines,character_bones:character?.boneList.length||0});
      renderer.setRenderTarget(null);ao.dispose();input.dispose();output.dispose();depthCopy.dispose();inputTexture.dispose();character?.dispose();scene.traverse(o=>{if(o.geometry)o.geometry.dispose();});
    }
    quad.dispose();copy.dispose();renderer.dispose();return cases;
  });
  if(errors.length)throw Error(errors.join('\n'));
  const references=path.join(directory,'reference');await fs.mkdir(references,{recursive:true});
  for(const record of results)for(const group of ['stages','noises'])for(const [name,value]of Object.entries(record[group])){
    const filename=`${record.name}_${name}.${value.format}.bin`,bytes=Buffer.from(value.base64,'base64');await fs.writeFile(path.join(references,filename),bytes);
    delete value.base64;value.path=`res://tests/ao/reference/${filename}`;value.sha256=createHash('sha256').update(bytes).digest('hex');
  }
  const fixture={version:1,source:'Actual vendored GTAOPass.js + MeshNormalMaterial WebGL geometry/depth GPU passes',flip_y:false,depth_convention:'WebGL nonreversed clip Z -1..1; original 24_8 depth sampled to float32',quality:'High/Ultra',absolute_tolerance:.001,relative_tolerance:.001,quirks:['PD SAMPLE_VECTORS retains initial radiusExponent1 despite pass property2','Original asymmetric PD mat2 is preserved','Source HALF intermediate quantization','Original per-pass actual noise bytes; AO5x5,PD64x64','Alpha retained by source multiply blend'],cases:results};
  await fs.writeFile(path.join(directory,'source_reference.json'),JSON.stringify(fixture,null,2));
  console.log(JSON.stringify({cases:results.length,stages:results.length*6,browser_errors:errors.length,gpu:results[0].gpu,output:'tests/ao/source_reference.json'}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
