shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size=vec2(435.2,29.44);
uniform float value=.4;
float capsule(vec2 p,vec2 b,float radius){vec2 q=abs(p)-b+radius;return min(max(q.x,q.y),0.)+length(max(q,0.))-radius;}
void fragment(){vec2 p=UV*panel_size;float d=capsule(p-panel_size*.5,panel_size*.5,panel_size.y*.5);float mask=1.-smoothstep(-.6,.6,d);vec3 c=vec3(.051,.039,.094);float fw=max(.001,panel_size.x*value);float fd=capsule(p-vec2(fw*.5,panel_size.y*.5),vec2(fw,panel_size.y)*.5,panel_size.y*.5);float fm=1.-smoothstep(-.6,.6,fd);vec3 fill=mix(vec3(1.,.769,.541),vec3(1.,.541,.078),min(1.,UV.y/.4));fill=mix(fill,vec3(.722,.384,.059),smoothstep(.4,1.,UV.y));float stripes=1.-step(10.,mod(p.x*.906+p.y*.423-TIME*31.43,22.));fill=mix(fill,vec3(1.),stripes*.22);float edge=(1.-smoothstep(.7,1.2,abs(p.y-panel_size.y*.28)-panel_size.y*.1))*step(10.24,p.x)*step(p.x,fw-10.24);fill=mix(fill,vec3(1.),edge*.45);COLOR=vec4(mix(c,fill,fm),mask)*COLOR;}
