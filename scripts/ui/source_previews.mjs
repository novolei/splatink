// Extract the original pure SVG recipes without executing browser or game state.
import {createPreview} from '../../../src/ui/menu-art.js';
import {writeFileSync} from 'node:fs';
class Element {
  constructor(tag='div'){this.tag=tag;this.children=[];this.style={setProperty(){}};this.dataset={};this.attrs={};this.classList={add(){},remove(){},toggle(){}};this.innerHTML='';}
  appendChild(c){this.children.push(c);return c;}
  setAttribute(k,v){this.attrs[k]=String(v);}
  getAttribute(k){return this.attrs[k]||'';}
  querySelector(sel){this.queries||={};return this.queries[sel]||=(new Element());}
  querySelectorAll(){return [];}
  get firstElementChild(){return this.querySelector('first');}
}
globalThis.document={createElement:t=>new Element(t),createTextNode:t=>({textContent:t})};
const allText=e=>[e.innerHTML||'',...(e.children||[]).map(allText)].join('');
function svgs(html){const out=[];let depth=0,start=0;for(const m of html.matchAll(/<svg\b[^>]*>|<\/svg>/g)){if(m[0].startsWith('</')){if(--depth===0)out.push(html.slice(start,m.index+m[0].length));}else{if(depth++===0)start=m.index;}}return out;}
const clean=s=>s.replaceAll('var(--a)','#ff8a14').replaceAll('var(--b)','#2f5bff').replaceAll('var(--k)','#15121c').replace(/(<g[^>]*style="color:([^\"]+)"[^>]*>)([\s\S]*?<\/svg>)/g,(_,a,c,b)=>a+b.replaceAll('currentColor',c)).replace('<svg ','<svg xmlns="http://www.w3.org/2000/svg" ').replaceAll('currentColor','#ffffff').replaceAll('class="iw-fa"','fill="#ff8a14"').replaceAll('class="iw-fb"','fill="#2f5bff"').replaceAll('class="iw-pv-bloom__glow iw-fa"','class="iw-pv-bloom__glow" fill="#ff8a14"').replaceAll('class="iw-pv-fov__ghost"','fill="none" stroke="#15121c" opacity=".38" stroke-width="2" stroke-dasharray="5 5"').replaceAll('class="iw-pv-fov__wedge"','class="iw-pv-fov__wedge" fill="#ff8a14" fill-opacity=".28" stroke="#ff8a14" stroke-width="2.5"').replaceAll('class="iw-pv-fov__halo"','fill="white" fill-opacity=".85"').replaceAll('class="iw-pv-aim__trail"','class="iw-pv-aim__trail" stroke="#ff8a14" stroke-width="3" stroke-dasharray="2 6"');
const folder=new URL('../../assets/ui/source/',import.meta.url);
for(const key of ['sensitivity','invertY','fov','shadows','bloom','showFps','minimap','cameraShake','aimAssist','rumble','matchLength']){
 const p=createPreview(key,{value:key==='fov'?82:key==='matchLength'?180:1});
 const arr=svgs(allText(p.el));
 for(let n=0;n<arr.length;n++)writeFileSync(new URL(`preview_${key}_${n}.svg`,folder),clean(arr[n]));
}
