shader_type canvas_item;
uniform vec4 ink:source_color=vec4(1.,.541,.078,1.);
uniform vec2 panel_size=vec2(128.,42.);
uniform float radius=8.;
void fragment(){
 vec4 tex=texture(TEXTURE,UV);vec3 color=ink.rgb;
 float light=clamp((tex.g-.541)/(.769-.541),0.,1.);
 float dark=clamp((.541-tex.g)/(.541-.384),0.,1.);
 color=mix(color,mix(ink.rgb,vec3(1.),.5),light);
 color=mix(color,ink.rgb*.72,dark);
 color*=1.-.28*(1.-smoothstep(0.,.4,UV.x));
 vec2 p=UV*panel_size;float dot_mask=1.-smoothstep(1.1,1.5,length(mod(p,vec2(5.33))-vec2(2.66)));color+=dot_mask*.035;
 vec2 q=abs(p-panel_size*.5)-panel_size*.5+radius;
 float d=min(max(q.x,q.y),0.)+length(max(q,0.))-radius;
	COLOR=vec4(color,tex.a*(1.-smoothstep(-.6,.6,d)));
}
