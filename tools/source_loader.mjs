import {pathToFileURL} from 'node:url';
import path from 'node:path';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/,'$1')), '../..');
export async function resolve(specifier, context, nextResolve) {
  if (specifier === 'three') return {url:pathToFileURL(path.join(root,'vendor/three/build/three.module.js')).href,shortCircuit:true};
  if (specifier.startsWith('three/addons/')) return {url:pathToFileURL(path.join(root,'vendor/three/jsm',specifier.slice(13))).href,shortCircuit:true};
  return nextResolve(specifier, context);
}
