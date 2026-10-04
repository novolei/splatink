shader_type canvas_item;
render_mode unshaded;
uniform float value=.5;
uniform float ghost=0.;
uniform vec4 ink:source_color=vec4(1.0,.54,.078,1.0);
uniform vec2 quad_size=vec2(130.,14.);
float rounded(vec2 p,vec2 b,float r){vec2 q=abs(p)-b+r;return min(max(q.x,q.y),0.)+length(max(q,0.))-r;}
void fragment(){
	vec2 px=UV*quad_size;float distance=rounded(px-quad_size*.5,quad_size*.5,quad_size.y*.5);
	float mask=1.-smoothstep(-.5,.5,distance);vec4 c=vec4(0.,0.,0.,.5);
	if(ghost>0.){float gd=rounded(px-vec2(quad_size.x*ghost*.5,quad_size.y*.5),vec2(quad_size.x*ghost*.5,quad_size.y*.5),min(quad_size.y*.5,quad_size.x*ghost*.5));float gm=1.-smoothstep(-.5,.5,gd);c=mix(c,vec4(1.,1.,1.,.38),gm);}
	if(value>0.){float vd=rounded(px-vec2(quad_size.x*value*.5,quad_size.y*.5),vec2(quad_size.x*value*.5,quad_size.y*.5),min(quad_size.y*.5,quad_size.x*value*.5));float vm=1.-smoothstep(-.5,.5,vd);c=mix(c,vec4(mix(mix(ink.rgb,vec3(1.),.32),mix(ink.rgb,vec3(0.),.28),UV.y),1.),vm);}
	float tick=step(.1-2./quad_size.x,mod(UV.x,.1));c.rgb=mix(c.rgb,vec3(.039,.031,.071),tick*.45);
	float border=1.-smoothstep(1.,2.,-distance);c.rgb=mix(c.rgb,vec3(1.),border*.08);
	COLOR=vec4(c.rgb,c.a*mask);
}
