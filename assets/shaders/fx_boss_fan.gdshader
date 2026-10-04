shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 uColor:source_color=vec3(1.0,0.3,0.3);
uniform float uAlpha=1.0;
uniform float uTime=0.0;
uniform float uK=0.0;
void fragment(){
	float rim=smoothstep(0.86,0.99,UV.x);
	float stripes=step(0.6,fract(UV.x*7.0-uTime*2.2));
	float a=max(rim*0.9,stripes*0.35*uK)+0.08+0.12*uK;
	ALBEDO=mix(uColor,vec3(1.0),rim*0.2)*1.35;ALPHA=a*uAlpha;
}
