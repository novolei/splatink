shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
varying vec4 ink;
varying vec4 state;
void vertex() { ink=COLOR; state=INSTANCE_CUSTOM; }
void fragment() {
	vec2 p=vec2(UV.x*2.0-1.0,1.0-UV.y*2.0);
	float r=length(p), kind=floor(state.b/10.0+0.001), core=state.b-kind*10.0;
	vec3 col=vec3(0);
	if(kind<0.5) {
		float g=pow(max(1.0-r,0.0),2.2), c=pow(max(1.0-r*1.8,0.0),3.0);
		col=ink.rgb*g+vec3(1.0,0.97,0.92)*c*core;
	} else if(kind<1.5) {
		float cr=max(exp(-abs(p.x)*22.0)*exp(-abs(p.y)*2.6),exp(-abs(p.y)*22.0)*exp(-abs(p.x)*2.6));
		vec2 d=vec2(p.x+p.y,p.x-p.y)*0.7071;
		float diagonal=max(exp(-abs(d.x)*30.0)*exp(-abs(d.y)*6.0),exp(-abs(d.y)*30.0)*exp(-abs(d.x)*6.0))*0.4;
		float halo=pow(max(1.0-r,0.0),3.0)*0.45, hot=pow(max(1.0-r*3.2,0.0),2.0);
		col=ink.rgb*(cr+diagonal+halo)+vec3(1.0,0.98,0.95)*hot*core;
	} else if(kind<2.5) {
		float rim=(1.0-smoothstep(0.0,0.16,abs(r-0.8)))*0.8+smoothstep(0.5,0.95,r)*step(r,0.9)*0.25;
		float highlight=1.0-smoothstep(0.0,0.24,length(p-vec2(-0.3,0.34)));
		col=ink.rgb*rim+vec3(1)*highlight*(0.6+core*0.2);
	} else {
		float ring=exp(-pow((r-0.78)*7.0,2.0));
		col=ink.rgb*ring+vec3(1)*ring*ring*core*0.3;
	}
	ALBEDO=col; ALPHA=ink.a*state.a;
}
