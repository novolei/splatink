// Original PropKit cloth waves: flex / wave source attributes and source atlas.
shader_type spatial;render_mode cull_disabled;
uniform float uTime=0.0;uniform sampler2D atlas:source_color,filter_linear_mipmap;
void vertex(){vec3 ipos=MODEL_MATRIX[3].xyz;float flex=CUSTOM0.x;vec3 wave=CUSTOM1.xyz;float cph=ipos.x*0.83+ipos.z*0.61+ipos.y*0.37;float ca=uTime*wave.x+cph+VERTEX.x*wave.y;float cb=uTime*wave.x*2.3+cph*1.7+VERTEX.y*3.0;float cw=sin(ca)+0.35*sin(cb);NORMAL=normalize(NORMAL+vec3(-flex*wave.z*wave.y*cos(ca),-flex*wave.z*1.05*cos(cb),0.0));VERTEX.z+=flex*wave.z*cw;}
void fragment(){vec4 tx=texture(atlas,UV);ALBEDO=mix(COLOR.rgb,tx.rgb,tx.a);ROUGHNESS=0.82;}
