// Read-only original web HUD fixture on the same flat background as reticle_contract.gd.
// Run with the bundled Node runtime on Windows. No original source files are modified.
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const output=path.join(root,'splatink/shots/reference/reticle');
const cases=[
 ['shooter',{weapon:'shooter',spread:4,onTarget:null}],
 ['enemy-target',{weapon:'shooter',spread:42,onTarget:'enemy'}],
 ['spawn-shield',{weapon:'shooter',spread:4,onTarget:null,shield:true}],
 ['charger',{weapon:'charger',charge:.72,spread:4,onTarget:null}],
];
const server=http.createServer(async(request,response)=>{
 try{
  const filename=path.resolve(root,'.'+decodeURIComponent(new URL(request.url,'http://localhost').pathname));
  if(!filename.startsWith(root+path.sep))throw new Error('outside source root');
  response.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.woff2':'font/woff2'})[path.extname(filename)]||'application/octet-stream');
  response.end(await fs.readFile(filename));
 }catch{response.statusCode=404;response.end();}
});
await new Promise(resolve=>server.listen(8495,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
try{
 await fs.mkdir(output,{recursive:true});
 const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
 for(const [name,settings] of cases){
  await page.goto('http://127.0.0.1:8495/tools/ui-lab.html?screen=hud&clean=1&auto=0&news=0');
  await page.evaluate(()=>document.fonts.ready);
  await page.addStyleTag({content:'#scene{display:none!important}html,body{background:#6e8899!important}.iw-hud>*{display:none!important}.iw-hud .iw-xh{display:block!important}.iw-hud-over{display:none!important}'});
  await page.evaluate(settings=>{
   lab.set({time:94.4,ink:.72,hp:1,charge:0,spread:4,onTarget:null,weapon:'shooter',subAim:false,...settings});
   if(settings.shield)lab.shield(30);
  },settings);
  await page.waitForTimeout(1100);
  await page.evaluate(()=>lab.freeze());
  await page.screenshot({path:path.join(output,name+'.png')});
  console.log('SOURCE_RETICLE '+name);
 }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
