shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec4 ink;
varying vec4 state;
void vertex() { ink=COLOR; state=INSTANCE_CUSTOM; }
void fragment() {
	float age=state.r, charge=state.g, sight=state.b;
	float wave=sin(UV.y*100.0-age*32.0)*0.5+0.5;
	float fade=pow(1.0-age,1.4);
	float dashes=mix(1.0,smoothstep(0.3,0.7,wave),smoothstep(0.25,0.9,age)*(1.0-sight));
	vec3 color=mix(ink.rgb,vec3(1.0,0.98,0.90),(1.0-sight)*(1.0-smoothstep(0.04,0.35,age))*0.86);
	ALBEDO=color*(1.3+charge*0.8); EMISSION=color*0.35;
	ALPHA=ink.a*fade*dashes*mix(0.95,0.28,sight);
}
