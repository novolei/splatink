/** Actual source UnrealBloomPass GPU reference, before grade/tone mapping.
 * No CPU blur approximation: all stages are read from original HALF targets.
 */
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
    if(url==='/bloom-reference'){
      res.setHeader('Content-Type','text/html');
      res.end('<canvas id="gpu"></canvas><script type="importmap">{"imports":{"three":"/vendor/three/build/three.module.js","three/addons/":"/vendor/three/jsm/"}}</script>');return;
    }
    if(url==='/favicon.ico'){res.statusCode=204;res.end();return;}
    const file=path.resolve(root,'.'+url);
    if(!file.startsWith(root+path.sep))throw Error('path outside source');
    res.setHeader('Content-Type',{'.js':'text/javascript','.mjs':'text/javascript','.json':'application/json'}[path.extname(file)]||'application/octet-stream');
    res.end(await fs.readFile(file));
  }catch{res.statusCode=404;res.end('missing');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',args:['--enable-webgl','--ignore-gpu-blocklist']});
const errors=[];
try{
  const page=await browser.newPage({viewport:{width:80,height:64}});
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
  await page.goto(`http://127.0.0.1:${server.address().port}/bloom-reference`);
  const results=await page.evaluate(async()=>{
    const T=await import('/vendor/three/build/three.module.js');
    const {UnrealBloomPass}=await import('/vendor/three/jsm/postprocessing/UnrealBloomPass.js');
    const {FullScreenQuad}=await import('/vendor/three/jsm/postprocessing/Pass.js');
    const renderer=new T.WebGLRenderer({canvas:document.querySelector('#gpu'),antialias:false});
    renderer.toneMapping=T.NoToneMapping;renderer.outputColorSpace=T.LinearSRGBColorSpace;
    const copy=new T.ShaderMaterial({depthTest:false,depthWrite:false,toneMapped:false,uniforms:{inputTexture:{value:null}},
      vertexShader:'varying vec2 uv0;void main(){uv0=uv;gl_Position=vec4(position.xy,0.,1.);}',
      fragmentShader:'varying vec2 uv0;uniform sampler2D inputTexture;void main(){gl_FragColor=texture2D(inputTexture,uv0);}'});
    const quad=new FullScreenQuad(copy);
    const encode=half=>{const bytes=new Uint8Array(half.buffer);let raw='';for(let i=0;i<bytes.length;i+=32768)raw+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(raw);};
    const read=target=>{
      renderer.setRenderTarget(target);
      const gl=renderer.getContext(),pixels=new Float32Array(target.width*target.height*4);
      gl.readPixels(0,0,target.width,target.height,gl.RGBA,gl.FLOAT,pixels);
      const error=gl.getError();if(error!==gl.NO_ERROR)throw Error('Bloom source readPixels: '+error);
      return {width:target.width,height:target.height,base64:encode(Uint16Array.from(pixels,T.DataUtils.toHalfFloat))};
    };
    const results=[];
    const presets=[['day',.28,.45,2.4],['sunset',.4,.55,1.7],['wide',.75,1,.85],['disabled',0,.45,2.4]];
    for(const [width,height]of [[64,48],[65,49]])for(const [name,strength,radius,threshold]of presets){
      renderer.setSize(width,height,false);
      const input=new Uint16Array(width*height*4);
      for(let y=0;y<height;y++)for(let x=0;x<width;x++){
        const u=x/(width-1),v=y/(height-1);
        // Asymmetric HDR ramps, threshold-adjacent patches, isolated coloured
        // impulses and edge blooms catch orientation/rounding/colour mistakes.
        let rgb=[u*3.2,.1+v*2.7,.05+(1-u)*v*2.3];
        if(x>width*.12&&x<width*.24&&y>height*.23&&y<height*.49)rgb=[threshold+.006,threshold+.006,threshold+.006];
        if(x===2&&y===3)rgb=[25,2,.5];
        if(x===width-1&&y===height-2)rgb=[.2,12,6];
        if(x>width*.64&&x<width*.76&&y>height*.6&&y<height*.76)rgb=[10,2.5,.1];
        const index=(y*width+x)*4;
        for(let c=0;c<3;c++)input[index+c]=T.DataUtils.toHalfFloat(rgb[c]);
        input[index+3]=T.DataUtils.toHalfFloat(.2+.8*u);
      }
      const texture=new T.DataTexture(input,width,height,T.RGBAFormat,T.HalfFloatType);
      texture.minFilter=T.LinearFilter;texture.magFilter=T.LinearFilter;texture.flipY=false;texture.needsUpdate=true;
      const target=new T.WebGLRenderTarget(width,height,{type:T.HalfFloatType,depthBuffer:false});
      copy.uniforms.inputTexture.value=texture;
      renderer.setRenderTarget(target);renderer.clear();quad.render(renderer);
      const stages={input:read(target)};
      const bloom=new UnrealBloomPass(new T.Vector2(width,height),strength,radius,threshold);
      bloom.render(renderer,null,target,0,false);
      stages.bright=read(bloom.renderTargetBright);
      for(let level=0;level<5;level++)stages['vertical'+level]=read(bloom.renderTargetsVertical[level]);
      stages.composite=read(bloom.renderTargetsHorizontal[0]);
      stages.output=read(target);
      results.push({name:`${width}x${height}_${name}`,size:[width,height],strength,radius,threshold,stages});
      renderer.setRenderTarget(null);bloom.dispose();target.dispose();texture.dispose();
    }
    quad.dispose();copy.dispose();renderer.dispose();return results;
  });
  if(errors.length)throw Error(errors.join('\n'));
  const directory=path.join(out,'data/bloom_reference');await fs.mkdir(directory,{recursive:true});
  const cases=[];
  for(const result of results){
    const stages={};
    for(const [name,stage]of Object.entries(result.stages)){
      const filename=`${result.name}_${name}.rgba16f.bin`;
      await fs.writeFile(path.join(directory,filename),Buffer.from(stage.base64,'base64'));
      stages[name]={size:[stage.width,stage.height],path:`res://data/bloom_reference/${filename}`};
    }
    cases.push({...result,stages});
  }
  const fixture={source:'vendor/three/jsm/postprocessing/UnrealBloomPass.js actual GPU HALF render targets',format:'rgba16f',flip_y:false,compare_channels:'rgb',native_alpha_contract:'Preserve input alpha for transparent studio overlays; source additive blend changes alpha.',absolute_tolerance:.003,relative_tolerance:.002,cases};
  await fs.writeFile(path.join(out,'data/bloom_gpu_reference.json'),JSON.stringify(fixture,null,2));
  console.log(JSON.stringify({cases:cases.length,stages:cases.length*9,pixels:cases.reduce((n,c)=>n+c.size[0]*c.size[1],0),output:'data/bloom_gpu_reference.json',browser_errors:errors.length}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
