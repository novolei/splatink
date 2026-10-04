import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import crypto from 'node:crypto';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const native = 'F:/Downloads/godot-motion-matching-master/godot-motion-matching-master';
const rooftop = 'D:/Godot resource/rooftop-bird-team';
const work = path.join(project, '.tools/mm-native');
const source = path.join(work, 'source');
const cpp = path.join(native, 'godot-cpp');
const git = (dir, ...args) => execFileSync('git', ['--no-optional-locks', '-C', dir, ...args], {encoding:'utf8'}).trim();
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const copy = (from, to) => { fs.mkdirSync(path.dirname(to), {recursive:true}); fs.copyFileSync(from,to); };
const base = git(native,'rev-parse','HEAD');
const bindings = git(cpp,'rev-parse','HEAD');
if(base !== '0208dd54902cca8a3bb016ed6591bfc933e2243a' || bindings !== '7e18e40d7591429f915035a7de7cf79457d555cc') throw Error('Native baseline or bindings identity changed');
const patch = path.join(rooftop,'docs/godot-prompter/standards/patches/mm255-native-0208dd54902c-aa4c3be232d9.patch');
if(digest(patch)!=='ef1cf21c7dbd3a0779283ff2545feef8f7a42714e411bb352bdb112b1e051e18') throw Error('Frozen patch identity changed');
const blobs=[];
for(const chunk of fs.readFileSync(patch,'utf8').split(/(?=^diff --git )/m)) {
  const file=chunk.match(/^diff --git a\/(.+) b\/(.+)\r?$/m)?.[2];
  const expected=chunk.match(/^index [a-f0-9]+\.\.([a-f0-9]+)/m)?.[1];
  if(!file || !expected) continue;
  const actual=git(native,'hash-object',`--path=${file}`, '--',path.join(native,file));
  if(actual!==expected)throw Error(`Frozen blob mismatch: ${file}`);
  blobs.push({file,blob:actual});
}
if(blobs.length!==19)throw Error('Expected 19 frozen increment files');
fs.mkdirSync(work,{recursive:true});
fs.writeFileSync(path.join(work,'.gdignore'),'');
for(const file of new Set([...git(native,'ls-files').split('\n'),...blobs.map(v=>v.file)])) {
  const from=path.join(native,file);
  if(fs.existsSync(from)&&fs.statSync(from).isFile())copy(from,path.join(source,file));
}
for(const file of git(cpp,'ls-files').split('\n')) {
  const from=path.join(cpp,file);
  if(fs.existsSync(from)&&fs.statSync(from).isFile())copy(from,path.join(source,'godot-cpp',file));
}
// Generated bindings are required by the frozen prebuilt static library; source
// snapshots contain headers/code only, never the original Git/cache/artifacts.
for(const dir of ['gen/include','gen/src','gdextension']) {
  fs.cpSync(path.join(cpp,dir),path.join(source,'godot-cpp',dir),{recursive:true,filter:f=>!/[.](?:obj|o|os|lib|dll|pdb)$/.test(f)});
}
const libraries={};
for(const mode of ['debug','release']) {
  const name=`libgodot-cpp.windows.template_${mode}.x86_64.lib`;
  const from=path.join(cpp,'bin',name);
  copy(from,path.join(work,'cache/bindings',name));
  libraries[mode]={name,sha256:digest(from)};
}
copy(patch,path.join(work,'provenance/frozen.patch'));
const manifest={version:1,base,bindings,frozen_tree:'aa4c3be232d94b7201d30395dfcc51d69a2c71d1',frozen_patch_sha256:digest(patch),verified_blobs:blobs,bindings_libraries:libraries,source_license:'MIT',reference_directories_read_only:true,api_revision:'splatink-external-query-v1'};
fs.writeFileSync(path.join(work,'provenance/source.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Prepared isolated source: ${blobs.length} frozen blobs verified; ${base}; ${bindings}`);
