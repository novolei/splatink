/** Indices follow the checked-in source's sequential spring/pose allocators. */
import fs from 'node:fs/promises';
const source=await fs.readFile(new URL('../../src/game/character.js',import.meta.url),'utf8');
const pose=source.slice(source.indexOf('let _k = 0;'),source.indexOf('const PN ='));
let offset=0;
export const poseIndices={};
for(const match of pose.matchAll(/([A-Z][A-Z0-9_]*)\s*=\s*S\((\d*)\)/g)){
  poseIndices[match[1]]=offset;
  offset+=match[2]?Number(match[2]):1;
}
const springs=source.slice(source.indexOf('let _sk = 0;'),source.indexOf('const SPN ='));
export const springIndices=Object.fromEntries([...springs.matchAll(/(S_\w+)\s*=\s*SPG\(\)/g)].map((match,index)=>[match[1],index*2]));
for(const name of ['HEAD','HLP','HLY','STAB','HIPS','SPINE','CHEST','NECK'])if(poseIndices[name]===undefined)throw new Error('Missing source pose index '+name);
export function sourceHeadParameters(character){
  const p=character.P,i=poseIndices;
  return [[p[i.HEAD],p[i.HEAD+1],p[i.HEAD+2]],[p[i.HLP],p[i.HLY],p[i.STAB]],[p[i.HIPS]+p[i.SPINE]+p[i.CHEST]+p[i.NECK],p[i.HIPS+2]+p[i.SPINE+2]+p[i.CHEST+2],0]];
}
