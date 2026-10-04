// Rasterize the original CSS feTurbulence tile once; Godot's SVG importer omits SVG filters.
// Read-only INKWAVE source; writes only the owned native UI asset directory.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire('C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const css=await fs.readFile(path.join(root,'styles/ui.css'),'utf8');
const encoded=css.match(/--tex-grain:\s*url\("data:image\/svg\+xml,([^"\n]+)"\)/)?.[1];
if(!encoded)throw new Error('Original --tex-grain data URI was not found');
const svg=decodeURIComponent(encoded);
const raw=path.join(root,'splatink/assets/ui/source_raw/news_grain.svg.txt');
const output=path.join(root,'splatink/assets/ui/source/news_grain.png');
await fs.mkdir(path.dirname(raw),{recursive:true});
await fs.writeFile(raw,svg);
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
try {
 const page=await browser.newPage({viewport:{width:140,height:140},deviceScaleFactor:1});
 await page.setContent(`<style>html,body{margin:0;width:140px;height:140px;background:transparent}img{display:block;width:140px;height:140px}</style><img src="data:image/svg+xml,${encoded}">`);
 await page.evaluate(()=>Promise.all([...document.images].map(img=>img.decode())));
 await page.screenshot({path:output,omitBackground:true});
 console.log('SOURCE_NEWS_GRAIN '+output+' 140x140; raw source '+pathToFileURL(raw));
} finally {await browser.close();}
