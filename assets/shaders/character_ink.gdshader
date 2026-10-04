shader_type spatial;
render_mode diffuse_lambert,cull_back;
uniform vec3 uTeam=vec3(1.0,0.254,0.007);
uniform float hit_flash=0.0;
uniform float charge=0.0;
uniform vec3 base_color=vec3(0.015);
uniform float use_base_color=0.0;
uniform float base_roughness=0.16;
uniform vec3 emission_color=vec3(0.0);
uniform float emission_intensity=0.0;
uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
void fragment(){ALBEDO=mix(uTeam,base_color,use_base_color);ROUGHNESS=base_roughness;SPECULAR=0.5;CLEARCOAT=1.0-use_base_color;CLEARCOAT_ROUGHNESS=0.12;EMISSION=vec3(hit_flash)+emission_color*emission_intensity;vec3 normal=NORMAL;float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix)*AO;}
