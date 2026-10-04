import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../assets/shaders');
const previous=await fs.readFile(path.join(dir,'ink_surface.gdshader'),'utf8');
const split=previous.indexOf('#include "res://assets/shaders/source_ink_pars.gdshaderinc"');
let header=previous.slice(0,split>=0?split:previous.indexOf('float noise2('));
if(!header.includes('uniform float atlas_size='))header=header.replace('uniform float texel','uniform float atlas_size=2048.0;\nuniform float paint_ppm=18.0;\nuniform float gel_layer=13.0;\nuniform vec3 sun_direction=vec3(-.57,.63,-.52);\nuniform vec4 ripple_params[24];\nuniform vec4 wake_points[48];\nuniform vec4 wake_bounds[4];\nuniform float texel');
header=header.replace(/render_mode[^;]+;/,'render_mode cull_back, diffuse_lambert, specular_schlick_ggx, ambient_light_disabled;');
header+='#include "res://assets/shaders/source_ink_pars.gdshaderinc"\n#include "res://assets/shaders/source_surface_lighting.gdshaderinc"\n';
const fragment=`void fragment(){
 #include "res://assets/shaders/source_surface_fragment.gdshaderinc"
 #include "res://assets/shaders/source_ink_color.gdshaderinc"
 #include "res://assets/shaders/source_ink_normal.gdshaderinc"
 float ao=has_ao&&aux.x>=0.0?texture(ao_atlas,vec2(aux.x,1.0-aux.y)).r:1.0;
 ALBEDO=base;ROUGHNESS=mix(rough,mix(.26,.14,gFresh),gInk);METALLIC=gTexORM.b*(1.0-gInk);
 AO=1.0;AO_LIGHT_AFFECT=0.0;SPECULAR=mix(.5,.27386128,gInk);
 #include "res://assets/shaders/source_surface_physical.gdshaderinc"
}
`;
await fs.writeFile(path.join(dir,'ink_surface.gdshader'),header+fragment);
await fs.writeFile(path.join(dir,'ink_grate.gdshader'),(header+fragment).replace('cull_back','cull_disabled'));
