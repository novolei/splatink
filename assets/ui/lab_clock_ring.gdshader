shader_type canvas_item;
render_mode unshaded;
uniform float fraction=.5;
uniform vec4 ink:source_color=vec4(1.0,.54,.078,1.0);
void fragment(){
	vec2 p=UV-.5;float r=length(p);
	float mask=(1.0-smoothstep(.49,.5,r))*smoothstep(.285,.295,r);
	float angle=mod(atan(p.y,p.x)+1.57079633+6.2831853,6.2831853)/6.2831853;
	vec4 color=angle<fraction?ink:vec4(1.0,1.0,1.0,.1);COLOR=vec4(color.rgb,color.a*mask);
}
