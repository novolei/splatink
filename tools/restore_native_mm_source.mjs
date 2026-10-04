import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const config=JSON.parse(fs.readFileSync(path.join(project,'tools/native_mm/source-archive.json'),'utf8'));
const archive=path.join(project,'tools/native_mm',config.archive);
const hash=crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
if(hash!==config.sha256||fs.statSync(archive).size!==config.size)throw Error('Native source archive identity mismatch');
const members=execFileSync('tar',['-tzf',archive],{encoding:'utf8'}).trim().split(/\r?\n/);
for(const member of members){
 const normalized=member.replaceAll('\\','/');
 if(normalized.startsWith('/')||normalized.includes(':')||normalized.split('/').includes('..')||!['source','provenance','MAC_BUILD.md'].includes(normalized.split('/')[0]))throw Error(`Unsafe archive member ${member}`);
}
const isolated=path.join(project,'.tools/mm-native');
fs.mkdirSync(isolated,{recursive:true});
fs.writeFileSync(path.join(isolated,'.gdignore'),'');
execFileSync('tar',['-xzf',archive,'-C',isolated],{stdio:'inherit'});
console.log(`Restored verified native source only to ${isolated}; no engine or compiler invoked`);
