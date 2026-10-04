// Invoke unmodified source FX methods without a renderer. Typed source pool
// buffers are retained so Float32 writes, expiry swaps and overflow RNG survive.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let seed=5129981,draws=[];
Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const n=seed/4294967296;draws.push(n);return n;};
const {FX}=await import('../../src/fx/fx.js');
function pool(cap){return {cap,n:0,P:new Float32Array(cap*3),V:new Float32Array(cap*3),C:new Float32Array(cap*3),X:new Float32Array(cap*14),geo:{instanceCount:0,userData:{dyn:[]},attributes:Object.fromEntries(['aPosSize','aColA','aMisc'].map(k=>[k,{array:new Float32Array(cap*4)}]))}};}
function snapshot(p){return Array.from({length:p.n},(_,i)=>({p:Array.from(p.P.slice(i*3,i*3+3)),v:Array.from(p.V.slice(i*3,i*3+3)),c:Array.from(p.C.slice(i*3,i*3+3)),x:Array.from(p.X.slice(i*14,i*14+14)),position_size:Array.from(p.geo.attributes.aPosSize.array.slice(i*4,i*4+4)),color_alpha:Array.from(p.geo.attributes.aColA.array.slice(i*4,i*4+4)),misc:Array.from(p.geo.attributes.aMisc.array.slice(i*4,i*4+4))}));}
const spec=(kind,life,drag,buoy,fadeIn,spin,wobble=0,fadeOut=0)=>({kind,life,drag,buoy,fadeIn,spin,wobble,fadeOut,start:.13,end:.9,alpha:.73});
const cases=[
 {name:'puff_source_kinds',cap:8,additive:false,specs:[spec(0,.31,4.5,.2,.08,1.2),spec(1,1.1,2.5,0,.05,.4),spec(2,12.4,1.6,-.7,.5,1.8,.9,1.5),spec(3,1.5,1.2,.9,.18,0,.35,.6),spec(4,.63,3.2,.15,.04,1.2)],frames:780,dt:1/60},
 {name:'glow_linear_alpha',cap:8,additive:true,specs:[spec(2,.3,0,0,0,0),spec(12,.8,1,0,.05,1.5),spec(21,.54,1,0,.04,0),spec(30,.18,0,0,0,0)],frames:56,dt:1/60},
 {name:'overflow_replaces_source_slots',cap:3,additive:false,specs:Array.from({length:11},(_,i)=>spec(i%5,.04+i*.025,2.2,.2,.03,i*.1,i%2*.2)),frames:30,dt:1/60},
 {name:'long_frame_drag_and_expiry',cap:4,additive:false,specs:[spec(0,.025,0,0,0,0),spec(2,2.4,20,-.7,.5,1.8,.9,1.5),spec(0,2.1,-.3,.8,0,2,.2,.3)],frames:8,dt:.4}
];
const traces=[];
for(const c of cases){
 const fx=Object.create(FX.prototype),p=pool(c.cap);fx.puffs=c.additive?pool(c.cap):p;fx.glows=c.additive?p:pool(c.cap);
 const operations=[];
 for(let index=0;index<c.specs.length;index++){
  const s=c.specs[index],pos=[index*.31-.7,.4+index*.06,-.2+index*.19].map(Math.fround),vel=[1.8-index*.17,.75-index*.13,-1.2+index*.22].map(Math.fround),col={r:Math.fround(.21+index*.13),g:Math.fround(.73-index*.03),b:Math.fround(.42+index*.06)};
  draws=[];
  FX.prototype._sprite.call(fx,p,...pos,...vel,col,s.start,s.end,s.life,s.alpha,s.drag,s.buoy,s.kind,s.fadeIn,s.spin,s.wobble,s.fadeOut);
  operations.push({input:{...s,pos,vel,col:[col.r,col.g,col.b]},random:draws});
 }
 const frames=[];
 for(let frame=0;frame<c.frames;frame++){
  FX.prototype._updateSprites.call(fx,p,c.dt,c.additive);
  frames.push({dt:c.dt,n:p.n,records:snapshot(p)});
 }
 traces.push({name:c.name,capacity:c.cap,additive:c.additive,operations,frames});
}
await fs.writeFile(path.join(base,'data/fx_sprites.json'),JSON.stringify({source:'unmodified src/fx/fx.js FX._sprite and FX._updateSprites with original Float32Array pools',traces}));
console.log(JSON.stringify({traces:traces.length,frames:traces.reduce((n,t)=>n+t.frames.length,0)}));
