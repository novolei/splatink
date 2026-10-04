shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 uColor:source_color=vec3(1.0,0.3,0.3);
uniform float uAlpha=1.0;
uniform float uTime=0.0;
uniform float uK=0.0;
void fragment(){
	float edge=1.0-smoothstep(0.0,0.08,min(UV.x,1.0-UV.x));
	float chev=step(0.55,fract(UV.y*9.0-abs(UV.x-0.5)*2.2-uTime*1.8));
	float a=max(edge*0.95,max(chev*(0.3+0.35*uK),0.16+0.22*uK))*(1.0-smoothstep(0.92,1.0,UV.y));
	ALBEDO=mix(uColor,vec3(1.0),edge*0.25)*1.35;ALPHA=a*uAlpha;
}
