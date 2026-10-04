// Exact small gameplay geometries from the original Three.js implementation.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as THREE from 'three';
const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../data/game');
await fs.mkdir(out,{recursive:true});
const cloud=new THREE.IcosahedronGeometry(1,3);
await fs.writeFile(path.join(out,'cloud_geometry.json'),JSON.stringify({
 source:'src/game/weapons.js: cloudGeo = new THREE.IcosahedronGeometry(1,3)',
 position:Array.from(cloud.attributes.position.array),normal:Array.from(cloud.attributes.normal.array),uv:Array.from(cloud.attributes.uv.array)
})+'\n');
console.log(`Original storm geometry: ${cloud.attributes.position.count} vertices`);
for(const detail of [0,1]){
 const mesh=new THREE.IcosahedronGeometry(1,detail);
 await fs.writeFile(path.join(out,`boss_ink_geometry_${detail}.json`),JSON.stringify({
  source:'src/boss/bossModelFx.js: IcosahedronGeometry(1, quality === low ? 0 : 1)',
  position:Array.from(mesh.attributes.position.array),normal:Array.from(mesh.attributes.normal.array),uv:Array.from(mesh.attributes.uv.array)
 })+'\n');
}
for(const[name,mesh]of [
 ['boss_lane',new THREE.PlaneGeometry(1,1).rotateX(-Math.PI/2).translate(0,0,.5)],
 ['boss_beam',new THREE.CylinderGeometry(1,1,1,12,1,true).rotateX(Math.PI/2).translate(0,0,.5)]
])await fs.writeFile(path.join(out,name+'_geometry.json'),JSON.stringify({position:Array.from(mesh.attributes.position.array),normal:Array.from(mesh.attributes.normal.array),uv:Array.from(mesh.attributes.uv.array),index:Array.from(mesh.index.array)})+'\n');
