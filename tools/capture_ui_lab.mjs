import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const req=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=req('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const server=http.createServer(async(request,response)=>{try{const uri=new URL(request.url,'http://localhost').pathname;const file=path.resolve(root,'.'+decodeURIComponent(uri));if(!file.startsWith(root+path.sep))throw Error('path');response.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.woff2':'font/woff2'})[path.extname(file)]||'application/octet-stream');response.end(await fs.readFile(file));}catch{response.statusCode=404;response.end();}});
await new Promise(resolve=>server.listen(8494,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
try{for(const screen of process.argv.slice(2).length?process.argv.slice(2):['main','play','setup','loadout','locker','settings','howto','online','lobby','credits','pause','results','title','hud']){
 await page.goto(`http://127.0.0.1:8494/tools/ui-lab.html?screen=${screen}&clean=1&auto=0&news=0`);
 await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(3000);
 const file=path.join(root,'splatink/shots/reference/ui',screen+'.png');await fs.mkdir(path.dirname(file),{recursive:true});await page.screenshot({path:file});console.log(screen);
}}finally{await browser.close();server.close();}
