shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec2 state;
void vertex(){state=INSTANCE_CUSTOM.rg;}
void fragment(){
	vec2 c=UV-0.5;float r=length(c)*2.0;if(r>1.0)discard;
	float a=1.0-smoothstep(0.2,1.0,r);
	float n=0.75+0.25*sin(c.x*9.0+state.g*7.0)*sin(c.y*8.0+state.g*3.0);
	ALBEDO=vec3(0.92,0.94,0.96);ALPHA=a*state.r*n;
}
