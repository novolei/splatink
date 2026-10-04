// Reuse the original private Heap class verbatim; preserve its equal-priority
// insertion/pop decisions in an independent native optimization contract.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const text=await fs.readFile(path.join(base,'../src/game/nav.js'),'utf8');
const Heap=Function(text.slice(text.indexOf('\nclass Heap {'))+'\nreturn Heap;')();
const traces=[],priorities=[];
for(const kind of ['equal','descending','float64_neighbors','mixed']){
 const heap=new Heap(),operations=[];let seed=912367;
 const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 for(let index=0;index<4096;index++){
  const id=index%311;
  const priority=kind==='equal'?7:kind==='descending'?4096-index:kind==='float64_neighbors'?1+(index%13)*Number.EPSILON:Math.floor(random()*32)+random()/1024;
  heap.push(id,priority);operations.push({push:id,priority,priority_index:priorities.length});priorities.push(priority);
  if(index%3===2)operations.push({pop:heap.pop()});
 }
 while(heap.size)operations.push({pop:heap.pop()});
 traces.push({kind,operations});
}
await fs.writeFile(path.join(base,'assets/actor_nav/heap_priorities.bin'),Buffer.from(Float64Array.from(priorities).buffer));
await fs.writeFile(path.join(base,'data/nav_heap.json'),JSON.stringify({source:'unmodified src/game/nav.js Heap with Float64 priorities, duplicates and mixed equal keys',fields:'res://assets/actor_nav/heap_priorities.bin',traces},null,2));
console.log(JSON.stringify({traces:traces.length,operations:traces.reduce((n,t)=>n+t.operations.length,0)}));
