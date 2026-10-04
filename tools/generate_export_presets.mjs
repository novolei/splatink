import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const project=path.resolve(process.argv[2]||path.join(path.dirname(fileURLToPath(import.meta.url)),'..'));
const resources=[],raw=[],nativeLibraries=[];
const developmentVersionCode=Math.floor(Date.now()/1000)-1735689600;
const resourceTypes=new Set(['.gd','.tscn','.tres','.gdshader','.gdshaderinc','.glsl','.glb','.png','.webp','.hdr','.exr','.svg','.ttf','.otf','.wav','.ogg','.gdextension']);
const nativeTypes=new Set(['.dll','.dylib','.so']);
async function collect(dir){for(const entry of await fs.readdir(path.join(project,dir),{withFileTypes:true})){const rel=dir+'/'+entry.name;const ext=path.extname(entry.name);if(entry.isDirectory())await collect(rel);else if(nativeTypes.has(ext))nativeLibraries.push(rel);else if(resourceTypes.has(ext))resources.push('res://'+rel);else if(!entry.name.endsWith('.import')&&!entry.name.endsWith('.uid'))raw.push(rel);}}
// Class-name scripts and dynamically composed model/icon/audio paths need explicit inclusion.
for(const dir of ['scripts','scenes','assets','resources','data'])await collect(dir);
// Exporting the extension resource lets Godot select the matching platform library.
// Native binaries are dependencies, rather than raw files embedded in every PCK.
try{await fs.access(path.join(project,'addons'));await collect('addons');}catch(error){if(error.code!=='ENOENT')throw error;}
resources.push('res://icon.svg');resources.sort();raw.sort();
for(const file of ['data/build_stamp.json','data/export_inventory.json'])if(!raw.includes(file))raw.push(file);
const base=(index,name,platform,features='')=>`[preset.${index}]\nname="${name}"\nplatform="${platform}"\nrunnable=true\nadvanced_options=false\ndedicated_server=false\ncustom_features="${features}"\nexport_filter="resources"\nexport_files=PackedStringArray(${resources.map(x=>JSON.stringify(x)).join(', ')})\ninclude_filter=${JSON.stringify(raw.join(','))}\nexclude_filter="tools/*,tests/*,shots/*,builds/*"\nexport_path=""\nencryption_include_filters=""\nencryption_exclude_filters=""\nencrypt_pck=false\nencrypt_directory=false\nscript_export_mode=2\n\n[preset.${index}.options]\n`;
let text=base(0,'Windows Development','Windows Desktop')+`binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\napplication/product_name="Splatink"\napplication/file_description="INKWAVE native development build"\napplication/company_name="INKWAVE"\napplication/product_version="0.1.0"\napplication/file_version="0.1.0"\n\n`;
text+=base(1,'Android Development','Android','mobile')+`gradle_build/use_gradle_build=false\narchitectures/armeabi-v7a=false\narchitectures/arm64-v8a=true\narchitectures/x86=false\narchitectures/x86_64=false\nversion/code=${developmentVersionCode}\nversion/name="0.1.0"\npackage/unique_name="com.inkwave.splatink.dev"\npackage/name="Splatink Dev"\npackage/signed=true\npermissions/internet=true\npermissions/vibrate=true\nscreen/immersive_mode=true\n\n`;
text+=base(2,'macOS Development','macOS')+`binary_format/architecture="universal"\napplication/bundle_identifier="com.inkwave.splatink.dev"\napplication/short_version="0.1.0"\napplication/version="1"\ncodesign/codesign=1\n\n`;
text+=base(3,'iOS Development','iOS','mobile')+`application/app_store_team_id=""\napplication/bundle_identifier="com.inkwave.splatink.dev"\napplication/short_version="0.1.0"\napplication/version="1"\napplication/signature=""\napplication/export_project_only=true\napplication/targeted_device_family=2\napplication/min_ios_version="16.0"\n\n`;
await fs.writeFile(path.join(project,'export_presets.cfg'),text);
nativeLibraries.sort();
await fs.writeFile(path.join(project,'data/export_inventory.json'),JSON.stringify({resources:resources.length,raw:raw.length,nativeLibraries},null,2));
console.log(JSON.stringify({resources:resources.length,raw:raw.length,nativeLibraries,project}));
