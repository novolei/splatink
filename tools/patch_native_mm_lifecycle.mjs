import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const file=path.join(project,'.tools/mm-native/source/src/editor/mm_editor_plugin.cpp');
let source=fs.readFileSync(file,'utf8').replace(/\r\n/g,'\n');
const before='    remove_control_from_bottom_panel(_editor);\n    _bottom_panel_button = nullptr;';
const after=`    remove_control_from_bottom_panel(_editor);
    // Bottom-panel removal detaches the control; the plugin still owns it.
    // Free now during editor teardown, before deferred deletion stops draining.
    memdelete(_editor);
    _editor = nullptr;
    _bottom_panel_button = nullptr;`;
if(source.includes('memdelete(_editor)'))throw Error('Lifecycle fix already applied');
if(source.split(before).length!==2)throw Error('Lifecycle patch anchor changed');
fs.writeFileSync(file,source.replace(before,after));
console.log('Applied editor-only bottom panel ownership cleanup; query/animation unchanged');
