// Read-only source UI Lab capture, with fixed fixture values and a DOM geometry record.
// No source files, local storage or existing services are changed.
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const output=path.join(root,'splatink/shots/reference/ui');
const fixtures=['loading','title','main','mode','setup','loadout','locker','settings','howto','credits','pause','results','online','lobby','hud','settings-video','settings-audio','settings-gameplay','locker-hair','locker-face','locker-outfit','setup-boss','hud-charger','hud-map','news-1','news-2'];
const server=http.createServer(async(request,response)=>{
 try{const uri=new URL(request.url,'http://localhost').pathname;const file=path.resolve(root,'.'+decodeURIComponent(uri));if(!file.startsWith(root+path.sep))throw Error('path');response.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.woff2':'font/woff2','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream');response.end(await fs.readFile(file));}catch{response.statusCode=404;response.end();}
});
await fs.mkdir(output,{recursive:true});await new Promise(resolve=>server.listen(8495,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
const errors=[];page.on('pageerror',error=>errors.push(String(error)));
try{
 for(const name of process.argv.slice(2).length?process.argv.slice(2):fixtures){
  await page.goto('http://127.0.0.1:8495/tools/ui-lab.html?screen=main&clean=1&auto=0&news=0&netmock=1&mockauto=0&mocklat=0&mockfill=0');
  await page.evaluate(()=>document.fonts.ready);
  await page.waitForFunction(()=>window.lab?.menus?._mockMod);
  await page.evaluate(async(name)=>{
   const lab=window.lab;const menus=lab.menus;
   if(name==='loading'){lab.go('loading');lab.loading(.4,'Building the plaza…');}
   else if(name.startsWith('news-')){lab.go('main');menus._news.show();if(name==='news-2'){await lab.wait(850);menus._news.next();}}
   else if(name==='lobby'){
    const n=menus._net();await n.create('Jayden');n.code='CE7QX';
    const names=['Mako','Tentakool','inkjet','Wavebreaker','Tidal Tia','Blot','Pixel'];
    for(let i=0;i<7;i++)n.mock.add({name:names[i],team:i<3?0:1,weapon:['roller','charger','blaster','blaster','charger','shooter','roller'][i],ready:i%3!==0});
    lab.go('lobby',{force:true});
   }
   else if(name.startsWith('settings-')){menus._settingsTab=['video','audio','gameplay'].indexOf(name.slice(9))+1;lab.go('settings',{force:true});}
   else if(name.startsWith('locker-')){menus._lockerTab=['hair','face','outfit'].indexOf(name.slice(7))+1;lab.go('locker',{force:true});}
   else if(name==='setup-boss'){menus._setup={times:{},...(menus._setup||{}),mode:'boss',duration:240};lab.go('setup',{force:true});}
   else if(name.startsWith('hud')){const original=lab.hudObj.update.bind(lab.hudObj);lab.hudObj.update=(dt,f)=>{window.__uiLabHudFrame=f;original(dt,f)};lab.hud();lab.set({time:94.4,ink:.72,special:.82,hp:1,weapon:name==='hud-charger'?'charger':'shooter',charge:name==='hud-charger'?.72:0,spread:4,onTarget:null,expanded:name==='hud-map',prompt:'Hold [SHIFT] to swim'});}
   else if(name==='results')lab.results();
   else lab.go(name,{force:true});
  },name);
  await page.waitForTimeout(name==='results'?8000:1600);
  await page.evaluate(()=>lab.freeze());
  if(name.startsWith('hud')){
   const frame=await page.evaluate(()=>{const f=window.__uiLabHudFrame;return {map:lab.hudObj.mapSlot.querySelector('canvas').toDataURL('image/png'),players:f.map.players,markers:f.markers,beacons:lab.hudObj.lab.beacons}});
   const fixtureFolder=path.join(root,'splatink/assets/ui/fixtures');await fs.mkdir(fixtureFolder,{recursive:true});
   await fs.writeFile(path.join(fixtureFolder,name+'-map.png'),Buffer.from(frame.map.split(',')[1],'base64'));delete frame.map;
   await fs.writeFile(path.join(fixtureFolder,name+'.json'),JSON.stringify(frame,null,2));
  }
  const metrics=await page.evaluate(()=>{
   const selection='.iw-screen,.iw-panel,.iw-btn,.iw-tabs,.iw-pmatch,.iw-pclock,.iw-pyou,.iw-roster,.iw-rrow,.iw-controls,.iw-lob__top,.iw-lob__status,.iw-lob__settings,.iw-lob__bottom,.iw-lob__bottom,.iw-res__head,.iw-res__table,.iw-prof,.iw-profile,.iw-loader,.iw-xp,.iw-news,.iw-news__card,.iw-news__hero,.iw-news__body,.iw-news__kicker,.iw-news__title,.iw-news__lede,.iw-news__list,.iw-news__list li,.iw-news__btns,.iw-news__foot,.iw-news__stamp,.iw-news__tape,.iw-hud';
   return [...document.querySelectorAll(selection)].filter(node=>{const r=node.getBoundingClientRect();return r.width&&r.height}).map(node=>{const r=node.getBoundingClientRect(),s=getComputedStyle(node);return {class:node.className,text:node.textContent?.trim().slice(0,180),rect:[r.x,r.y,r.width,r.height].map(x=>Math.round(x*100)/100),local:[node.offsetLeft,node.offsetTop,node.offsetWidth,node.offsetHeight],font:s.fontFamily,fontSize:s.fontSize,color:s.color,background:s.backgroundColor,transform:s.transform};});
  });
  await page.screenshot({path:path.join(output,name+'.png')});
  await fs.writeFile(path.join(output,name+'.json'),JSON.stringify({fixture:name,viewport:[1280,720],errors:[...errors],metrics},null,2));
  console.log(name);errors.length=0;
 }
}finally{await browser.close();server.close();}
