shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 uColor:source_color=vec3(1.0,0.3,0.3);
uniform float uAlpha=1.0;
uniform float uTime=0.0;
uniform float uK=0.0;
void fragment(){
	vec2 p=UV*2.0-1.0;float r=length(p);float ang=atan(p.y,p.x);
	float rim=1.0-smoothstep(0.012,0.045,abs(r-0.955));
	float dashes=step(0.45,fract(ang/6.2831853*16.0-uTime*(0.5+uK*1.8)))*(1.0-smoothstep(0.012,0.04,abs(r-0.87)));
	float ph=fract(uTime*(1.0+uK*4.0));
	float wave=(1.0-smoothstep(0.0,0.07,abs(r-ph*0.95)))*(1.0-ph)*0.85;
	float fill=(0.1+0.24*uK)*(0.55+0.45*smoothstep(0.0,0.95,r))*step(r,0.955);
	float dark=1.0-smoothstep(0.0,0.03,abs(r-0.99));
	float a=max(max(rim,dashes*0.9),max(wave,fill));
	vec3 col=mix(uColor,vec3(1.0),rim*0.3+wave*0.25);
	ALBEDO=mix(col,vec3(0.04),dark*0.7);ALPHA=max(a,dark*0.5)*uAlpha;
	if(ALPHA<0.004)discard;
}
