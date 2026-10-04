shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx,cull_disabled;
uniform vec3 deep_color : source_color = vec3(.04,.31,.54);
uniform vec3 shallow_color : source_color = vec3(.07,.65,.72);
uniform vec3 crest_color : source_color = vec3(.28,.88,.84);
uniform float calm=.55;
varying vec3 wpos;
void vertex(){wpos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;VERTEX.y+=sin(wpos.x*.33+TIME*.9)*.06*calm+sin(wpos.z*.43-TIME*.6)*.055*calm;}
void fragment(){float n=sin(wpos.x*1.7+TIME*1.8)*cos(wpos.z*1.4-TIME*.9);vec2 wave=vec2(cos(wpos.x*.33+TIME*.9),cos(wpos.z*.43-TIME*.6))*.14*calm;NORMAL=normalize(NORMAL+vec3(wave.x,0,wave.y));float f=pow(1.0-max(dot(NORMAL,VIEW),0.0),3.0);ALBEDO=mix(deep_color,shallow_color,.25+f*.5);ALBEDO=mix(ALBEDO,crest_color,smoothstep(.82,1.0,n)*.15);ROUGHNESS=.17;METALLIC=.18;CLEARCOAT=1.0;CLEARCOAT_ROUGHNESS=.09;}
