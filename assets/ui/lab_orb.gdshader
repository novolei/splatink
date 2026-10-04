shader_type canvas_item;
render_mode unshaded;
uniform float level=0.;
uniform vec4 ink:source_color=vec4(1.,.54,.078,1.);
void fragment(){vec2 p=(UV-.5)*2.;float theta=atan(p.y,p.x);float r=.90+.012*sin(theta*3.)+.018*cos(theta*2.+.4);float d=length(p)-r;float mask=1.-smoothstep(0.,.025,d);float rim=smoothstep(-.065,-.03,d);float wave=.5+.5*sin(UV.x*25.+TIME*3.9);float top=1.-level+.028*wave;vec3 c=vec3(.055,.043,.086);if(UV.y>top)c=ink.rgb*(1.-UV.y*.12)+vec3(.04)*(1.-smoothstep(top,top+.03,UV.y));float gloss=exp(-length((UV-vec2(.32,.24))*vec2(5.,8.)))*.45;c=mix(c,vec3(1.),gloss);c=mix(c,vec3(1.),rim);COLOR=vec4(c,mask);}
