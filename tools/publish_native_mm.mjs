import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const isolated=path.join(project,'.tools/mm-native');
const runtime=path.join(project,'addons/motion_matching');
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const source=JSON.parse(fs.readFileSync(path.join(isolated,'provenance/source.json'),'utf8'));
const expected={
 template_debug:'7bea8da6a4dbbc6d3e0c5821b90438f4d28e10bc2b78b3b611b485c4ae632773',
 template_release:'a900a3997779c279bbbe2ac22c207918f39d2ddf3c943bde280e7e5212be922e'
};
const binaries={};
for(const mode of Object.keys(expected)){
 const name=`libgdmotionmatching.windows.${mode}.x86_64.splatlower1.dll`;
 const file=path.join(isolated,'publish/bin/windows',name);
 const digest=hash(file);
 if(digest!==expected[mode])throw Error(`Unreviewed binary ${name}: ${digest}`);
 binaries[mode]={path:`bin/windows/${name}`,sha256:digest,size:fs.statSync(file).size};
}
const mac_expected={template_debug:'542b4df0b2fff8479d4a112498704e767901e955e979fe9db38be26b82aa878c',template_release:'8a54d9979e42e9df5d00b7769d4247c218d08e6f29f6ba661c564a63f109a375'};
const mac_binaries={};
for(const mode of Object.keys(mac_expected)){
 const name=`libgdmotionmatching.macos.${mode}.splatlower1.dylib`;
 const file=path.join(isolated,'transfers/macos-fixed',name);
 if(!fs.existsSync(file))throw Error(`Fixed same-source Mac binary missing: ${name}`);
 const digest=hash(file);
 if(digest!==mac_expected[mode])throw Error(`Unreviewed Mac binary ${name}: ${digest}`);
 mac_binaries[mode]={path:`bin/macos/${name}`,sha256:digest,size:fs.statSync(file).size,architectures:['arm64','x86_64'],status:'compiled; runtime validation pending'};
}
const dumpbin='C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/dumpbin.exe';
const deps=execFileSync(dumpbin,['/dependents',path.join(isolated,'publish',binaries.template_debug.path)],{encoding:'utf8'});
if(!deps.includes('KERNEL32.dll')||/VCRUNTIME|MSVCP/i.test(deps))throw Error('Unexpected dynamic CRT dependency');
fs.mkdirSync(path.join(runtime,'bin/windows'),{recursive:true});
for(const mode of Object.keys(binaries))fs.copyFileSync(path.join(isolated,'publish',binaries[mode].path),path.join(runtime,binaries[mode].path));
fs.mkdirSync(path.join(runtime,'bin/macos'),{recursive:true});
for(const mode of Object.keys(mac_binaries))fs.copyFileSync(path.join(isolated,'transfers/macos-fixed',path.basename(mac_binaries[mode].path)),path.join(runtime,mac_binaries[mode].path));
fs.copyFileSync(path.join(isolated,'source/LICENSE.md'),path.join(runtime,'LICENSE.md'));
fs.writeFileSync(path.join(runtime,'gdmotionmatching.gdextension'),`[configuration]
entry_symbol = "example_library_init"
compatibility_minimum = "4.7"
reloadable = false

[libraries]
windows.debug.x86_64 = "res://addons/motion_matching/${binaries.template_debug.path}"
windows.release.x86_64 = "res://addons/motion_matching/${binaries.template_release.path}"
macos.debug = "res://addons/motion_matching/${mac_binaries.template_debug.path}"
macos.release = "res://addons/motion_matching/${mac_binaries.template_release.path}"
`);
const provenance={...source,version:3,runtime_revision:'splatlower1',binaries,macos_binaries:mac_binaries,
 editor_cleanup_revision:1,
 previous_diagnostic_binaries:{template_debug:'3a20de08a171e078279fc8500db395ec517e271bb6d610195666f8dba2ed3648',template_release:'109db398ec7f54bebe29e87eaa6dcdcac3813ef85315d4859c20cf9c9675786d'},
 toolchain:{compiler:'MSVC 14.44.35207',flags:'/std:c++17 /Zc:__cplusplus /EHsc /MT /O2 /utf-8',scons:'4.10.1',python:'3.14.6',jobs:6,architecture:'x86_64',precision:'single'},
 extension_api:['MMAnimationLibrary.configure_external_database(data,weights,animation_indices,times,offsets)','MMAnimationLibrary.query_normalized_vector(query,current_pose=-1)'],
 source_bridge_sha256:{header:hash(path.join(isolated,'source/src/mm_animation_library.h')),implementation:hash(path.join(isolated,'source/src/mm_animation_library.cpp')),editor_cleanup:hash(path.join(isolated,'source/src/editor/mm_editor_plugin.cpp'))},
 generator_sha256:{prepare:hash(path.join(project,'tools/prepare_native_mm.mjs')),patch:hash(path.join(project,'tools/patch_native_mm.mjs')),editor_cleanup:hash(path.join(project,'tools/patch_native_mm_lifecycle.mjs')),build:hash(path.join(project,'tools/native_mm_sconstruct.py'))},
 constraints:['Opt-in lower-body pose selection only','Never instantiate MMCharacter for Splatink authoritative movement','Original 87-joint GLB bytes retained','macOS universal debug/release compiled from same fixed archive; runtime validation pending','No Android/iOS native binary claimed'],
};
fs.writeFileSync(path.join(runtime,'provenance.json'),JSON.stringify(provenance,null,2)+'\n');
fs.writeFileSync(path.join(runtime,'README.md'),`# Splatink lower-body native motion matching pilot

Runtime is deliberately opt-in with \`--native-locomotion-mm\`. This is the recovered MIT MM source at ${source.base}, with all 19 Rooftop frozen-patch blobs verified, plus a narrow normalized-query API. The actual MMAnimationLibrary native exact search and continuation costs are used. The MMCharacter physics controller is never instantiated.

Only hips and leg/foot/toe animation tracks may be selected by this provider; source weapons, upper body, face, hair, kid/squid switching and authoritative world movement remain with Splatink. Existing 42 in-place locomotion cycles contain no authored start/stop/pivot clips.

Windows debug/release DLL hashes and full source provenance are in provenance.json. macOS universal debug/release were compiled by Root from the same fixed source archive; actual macOS runtime validation is still pending. Runtime addon intentionally excludes build caches and C++ source.
`);
console.log(JSON.stringify({runtime,binaries,mac_binaries,dependencies:deps.match(/\b[A-Za-z0-9_]+\.dll\b/g)},null,2));
