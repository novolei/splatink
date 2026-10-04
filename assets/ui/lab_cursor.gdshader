shader_type canvas_item;
render_mode unshaded;
uniform vec2 viewport_size=vec2(1280.,720.);
uniform vec4 cursor_rect=vec4(0.);
uniform float radius=19.8;
uniform float pulse_time=0.;
uniform bool reduce_motion=false;
uniform vec4 accent:source_color=vec4(1.,.541176,.078431,1.);
float rounded_box(vec2 p,vec2 b,float r){vec2 q=abs(p)-b+r;return min(max(q.x,q.y),0.)+length(max(q,0.))-r;}
void fragment(){
	vec2 half_size=cursor_rect.zw*.5;
	float d=rounded_box(UV*viewport_size-cursor_rect.xy-half_size,half_size,min(radius,min(half_size.x,half_size.y)));
	float pulse=reduce_motion?0.:.5-.5*cos(pulse_time*6.283185/1.3);
	float outer=6.+pulse*3.;
	float white=(1.-smoothstep(-.65,.65,d))*smoothstep(-3.65,-2.35,d);
	float black=smoothstep(-.65,.65,d)*(1.-smoothstep(2.35,3.65,d));
	float colored=smoothstep(2.35,3.65,d)*(1.-smoothstep(outer-.65,outer+.65,d));
	float glow=exp(-pow(max(0.,d-3.)/(23.04+7.68*pulse),2.)*3.)*step(3.,d)*(.23+.1*pulse);
	float colored_alpha=colored*(.6-.32*pulse);
	float alpha=max(white,max(black,max(colored_alpha,glow)));
	vec3 color=accent.rgb;
	if(black>colored_alpha&&black>glow)color=vec3(.082353,.070588,.109804);
	if(white>black&&white>colored_alpha&&white>glow)color=vec3(1.);
	COLOR=vec4(color,alpha);
}
