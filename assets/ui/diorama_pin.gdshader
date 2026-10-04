shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink:source_color=vec4(1.0,.54,.08,1.0);
uniform float kind=0.0;
uniform float pin_k=1.0;
uniform float badge_scale=1.0;
uniform float clock=0.0;
uniform float hover=0.0;
uniform bool dead=false;
uniform bool draw_ground=true;
vec4 over(vec4 below,vec4 above){float a=above.a+below.a*(1.0-above.a);return vec4((above.rgb*above.a+below.rgb*below.a*(1.0-above.a))/max(a,.0001),a);}
void fragment(){
 vec2 p=UV*vec2(76.8,115.2)-vec2(38.4,86.4);vec4 black=vec4(.08235,.07059,.1098,1.0);vec4 c=vec4(0.0);
 float ground=clamp(1.0-length(p/vec2(kind>1.5?14.08:9.6,4.35)),0.0,1.0)*.9;
 if(draw_ground){c=over(c,vec4(ink.rgb,ground));
 float stem=(1.0-smoothstep(1.5,2.8,abs(p.x)))*step(-28.16*pin_k,p.y)*step(p.y,0.0);
 c=over(c,vec4(black.rgb,stem));float line=(1.0-smoothstep(1.0,1.5,abs(p.x)))*step(-28.16*pin_k,p.y)*step(p.y,0.0);c=over(c,vec4(1.0,1.0,1.0,line));}
 float diameter=kind>1.5?42.24:kind>.5?32.0:37.12;float r=diameter*.5*badge_scale;
 vec2 q=p-vec2(0.0,-28.16-r);float d=length(q);float shadow=exp(-pow(max(0.0,length(q-vec2(0.0,6.0))-r)/7.0,2.0))*.35;
 c=over(c,vec4(0.0,0.0,0.0,shadow));
 float outer=kind>1.5?5.38:kind>.5?2.82:4.61;float a=1.0-smoothstep(r+outer-.8,r+outer+.8,d);
 c=over(c,vec4(kind>1.5?vec3(1.0):kind>.5?ink.rgb:black.rgb,a));
 if(kind<.5||kind>1.5){float inner=kind>1.5?3.58:2.82;c=over(c,vec4(kind>1.5?ink.rgb:vec3(1.0),1.0-smoothstep(r+inner-.8,r+inner+.8,d)));}
 vec3 color=kind>.5?black.rgb:ink.rgb;float radial=length(q/r-vec2(-.30,-.40))/1.7;
 if(kind<.5){color=radial<.62?mix(mix(ink.rgb,vec3(1.0),.28),ink.rgb,radial/.62):mix(ink.rgb,ink.rgb*.7,clamp((radial-.62)/.38,0.0,1.0));}
 if(dead){float grey=dot(color,vec3(.2126,.7152,.0722));color=vec3(grey*.72);}
 c=over(c,vec4(color,1.0-smoothstep(r-.8,r+.8,d)));
 float pulse=fract(clock/(kind>1.5?1.6:1.0));float pr=r*mix(.85,1.5,pulse);float ring=(1.0-smoothstep(1.0,2.0,abs(d-pr)))*(.9*(1.0-pulse))*(kind>1.5?.8:hover);
 c=over(c,vec4(ink.rgb,ring));COLOR=c*COLOR;
}
