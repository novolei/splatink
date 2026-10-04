shader_type canvas_item;
render_mode unshaded;
// The four source clip-path vertices, in CSS percentage coordinates.
uniform vec2 tape_size=vec2(93.312,33.968);
uniform vec4 tape_color:source_color=vec4(1.0,.9568627,.8392157,.82);
float edge(vec2 p,vec2 a,vec2 b){vec2 direction=b-a;return (direction.x*(p.y-a.y)-direction.y*(p.x-a.x))/max(length(direction),.0001);}
void fragment(){
	vec4 tint=COLOR;
 vec2 p=UV*tape_size;
 vec2 a=vec2(.03,.08)*tape_size;vec2 b=vec2(.97,0.0)*tape_size;vec2 c=vec2(1.0,.92)*tape_size;vec2 d=vec2(0.0,1.0)*tape_size;
 float inside=min(min(edge(p,a,b),edge(p,b,c)),min(edge(p,c,d),edge(p,d,a)));
	COLOR=vec4(tape_color.rgb,tape_color.a*smoothstep(-.5,.5,inside))*tint;
}
