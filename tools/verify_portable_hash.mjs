import assert from 'node:assert/strict';
// Apply float32 at each shader operation and compare the original source PCG.
const f=Math.fround;
function mul(a,b){const x=[a&255,(a>>>8)&255,(a>>>16)&255,a>>>24],y=[b&255,(b>>>8)&255,(b>>>16)&255,b>>>24];
 const p0=f(x[0]*y[0]),p1=f(f(x[1]*y[0])+f(x[0]*y[1]));
 const p2=f(f(f(x[2]*y[0])+f(x[1]*y[1]))+f(x[0]*y[2]));
 const p3=f(f(f(f(x[3]*y[0])+f(x[2]*y[1]))+f(x[1]*y[2]))+f(x[0]*y[3]));
 return (p0+(p1<<8)+(p2<<16)+(p3<<24))>>>0;}
function pcg(v,op){const s=(op(v,747796405)+2891336453)>>>0,w=op((s>>>((s>>>28)+4))^s,277803737)>>>0;return ((w>>>22)^w)>>>0;}
let seed=0xFFFFFFFF;
for(let i=0;i<1000000;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;assert.equal(pcg(seed,mul),pcg(seed,Math.imul));assert.equal(mul(seed,0xFFFFFFFF),Math.imul(seed,0xFFFFFFFF)>>>0);}
console.log('PORTABLE_HASH 2000000 exact float32 checks passed');
